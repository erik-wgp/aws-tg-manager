
require "rubygems"
require 'yaml'
require 'awesome_print'
require 'aws-sdk'
require 'instance.rb'
require 'target_group.rb'

$tag_names = {}

DEFAULT_TG_INSTANCE_GROUPS_TAG = "AutoTGInstanceGroups"
DEFAULT_TG_POLICY_TAG = "AutoTGPolicy"
DEFAULT_INSTANCE_GROUPS_TAG = "AutoTGInstanceGroups"


##
## the config data structure will be like
#{
#    "prod-target-group-alpha" => {
#      "instance-group-1c" =>
#        "prod-alpha-1c-1" => {
#           :state => "healthy|unhealthy|draining|unknown:<state>",
#           :configured => true|false
#        },
#        "prod-alpha-1c-2" => {
#          [...]
#        }
#      },
#      "instance-group-1d" => {
#        [...]
#      }
#    },
#
#    "prod-target-group-bravo" => {
#      [...]
#    }
#}

class ElbManager

  def initialize(config_override = nil)

    profile_name = (ENV["ELB_MANAGER_AWS_PROFILE"]  || ENV["AWS_PROFILE"] || "default")

    Aws.config[:credentials] = Aws::SharedCredentials.new(profile_name: profile_name)

    @elb2 = Aws::ElasticLoadBalancingV2::Client.new(region: "us-east-1")
    @ec2 = Aws::EC2::Client.new(region: "us-east-1")
    @ec2_resource = Aws::EC2::Resource.new(client: @ec2)

    [ "INSTANCE_GROUPS_TAG", "TG_INSTANCE_GROUPS_TAG", "TG_POLICY_TAG" ].each do |tag|
      $tag_names[tag] = ENV[tag]
      $tag_names[tag] ||= eval("DEFAULT_#{tag}")
    end

    @add_queue = {}
    @remove_queue = {}

    load_aws_state
  end

  def load_aws_state
    @target_groups = {}
    @instances = {}
    errors = false

    load_instances
    load_target_groups

    #@target_groups.each do |tg_name, tg| tg.print end
    #@instances.each do |id, instance| instance.print end

    @instances.each do |instance_id, instance|
      instance.instance_groups.each do |ig_name|
        #puts "\tlooking for target group accepting instance group #{ig_name}"
        @target_groups.select { |tg_name, tg| tg.accepts_instance_group(ig_name) }.each do |tg_name, tg|
          #puts "MATCH #{tg_name}, #{ig_name}"
          tg.set_instance_configured(ig_name, instance_id, true)
        end
        # todo - what if instance's instance group has no tg?
      end
    end

    load_target_group_health
    return ! errors
  end

  def queue_remove(tg_name, instance_id)
    @remove_queue[tg_name] ||= {}
    @remove_queue[tg_name][instance_id] = instance_id
  end

  def queue_add(tg_name, instance_id)
    @add_queue[tg_name] ||= {}
    @add_queue[tg_name][instance_id] = instance_id
  end

  def stage_remove_instance_from_state(instance_str)
    # todo abort if @del queue?

    removed_tgs = []
    @target_groups.each do |tg_name, tg|
      instance_id = Instance.id_from_string(instance_str)
      if tg.attempt_remove_instance(instance_id)
        removed_tgs << tg_name
        queue_remove(tg_name, instance_id)
      end
    end

    removed_tgs
  end

  def stage_remove_group_from_state(group_str)
    # todo abort if @del queue?

    removed_tgs = []
    @target_groups.each do |tg_name, tg|
      instance_ids = tg.attempt_remove_group(group_str)
      if ! instance_ids.empty?
        removed_tgs << tg_name
        instance_ids.each { |instance_id| queue_remove(tg_name, instance_id) }
      end
    end

    removed_tgs
  end

  def stage_add_instance_to_state(instance_str)
    # todo abort if @del queue?

    added_tgs = []
    @target_groups.each do |tg_name, tg|
      instance_id = Instance.id_from_string(instance_str)
      if tg.attempt_add_instance(instance_id)
        added_tgs << tg_name
        queue_add(tg_name, instance_id)
      end
    end

    added_tgs
  end

  def stage_add_group_to_state(group_str)
    # todo abort if @del queue?

    added_tgs = []
    @target_groups.each do |tg_name, tg|
      instance_ids = tg.attempt_add_group(group_str)
      if ! instance_ids.empty?
        added_tgs << tg_name
        instance_ids.each { |instance_id| queue_add(tg_name, instance_id) }
      end
    end

    added_tgs
  end

  def execute_removes
    @remove_queue.each do |tg_name, tg_instance_ids|
      tg = @target_groups[tg_name]
      instance_hash = tg_instance_ids.keys.map { |id| [ [ :id, id ] ].to_h  }
      # todo - apparently returns Aws::EmptyStructure:Aws::ElasticLoadBalancingV2::Types::DeregisterTargetsOutput
      # or throws an exception
      instances_string = tg_instance_ids.keys.map { |instance_id| Instance.name_id(instance_id) }.join(' ')
      puts "REMOVE #{tg.arn} #{instances_string}"
      resp = @elb2.deregister_targets({ target_group_arn: tg.arn, targets: instance_hash })
    end
  end

  def execute_adds
    @add_queue.each do |tg_name, tg_instance_ids|
      tg = @target_groups[tg_name]
      instance_hash = tg_instance_ids.keys.map { |id| [ [ :id, id ] ].to_h  }
      # todo - apparently returns Aws::EmptyStructure:Aws::ElasticLoadBalancingV2::Types::DeregisterTargetsOutput
      # or throws an exception

      instances_string = tg_instance_ids.keys.map { |instance_id| Instance.name_id(instance_id) }.join(' ')
      puts "ADD #{tg.arn} #{instances_string}"
      resp = @elb2.register_targets({ target_group_arn: tg.arn, targets: instance_hash })
    end
  end

  def validate
    validate_base
  end

  def validate_and_print
    validate_base(print: true)
  end

  def validate_base(print: false)
    all_errors = {}

    @target_groups.each do |tg_name, tg|
      errors = tg.validate
      tg.print if print
      if ! errors.empty?
        errors.map { |err| puts "   ! #{err}" }
        all_errors[tg_name] = errors
      end
    end

    all_errors
  end

  def load_instances
    @ec2_resource.instances({
      filters: [
        { name: "tag-key", values: [ $tag_names["INSTANCE_GROUPS_TAG"] ] }
      ]
    }).each do |i|
      instance = Instance.new(raw_data: i.data, id: i.instance_id, tags: i.data.tags.map { |t| [ t.key, t.value ] }.to_h )
      @instances[instance.id] = instance
    end
  end

  def load_target_groups

    all_target_groups = @elb2.describe_target_groups[:target_groups]
    all_tg_arns = all_target_groups.map { |tg_data| tg_data.target_group_arn }
    all_tags = {}

    @elb2.describe_tags({ resource_arns: all_tg_arns }).tag_descriptions.each do |resp|
      all_tags[resp.resource_arn] = resp.tags
    end

    all_target_groups.each do |tg_data|
      tags = all_tags[tg_data.target_group_arn].map { |t| [ t.key, t.value ] }.to_h
      tg = TargetGroup.new(raw_data: tg_data, arn: tg_data.target_group_arn, name: tg_data.target_group_name, tags: tags)

      if tg.tags[ $tag_names["TG_INSTANCE_GROUPS_TAG"] ]
        @target_groups[tg.name] = tg
      end
    end
  end

  def load_target_group_health
    @target_groups.each do |tg_name, tg|
      @elb2.describe_target_health({ target_group_arn: tg.arn })[:target_health_descriptions].each do |h|
        tg.set_instance_state(h.target.id, h.target_health.state)
      end
    end
  end

end
