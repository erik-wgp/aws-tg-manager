class TargetGroup
  attr_accessor :arn, :name, :tags, :policies, :tg_instance_groups, :instance_state

  def initialize(args)
    @raw = args[:raw_data]
    @arn = args[:arn]
    @name = args[:name]

    @tags = args[:tags]

    @tg_instance_groups = []
    instance_groups_string = @tags[$tag_names["TG_INSTANCE_GROUPS_TAG"]]
    if instance_groups_string
      @tg_instance_groups = instance_groups_string.split(/[\s,]+/)
    end

    @policies = {}
    policy_string = @tags[$tag_names["TG_POLICY_TAG"]]
    if policy_string
      @policies = policy_string.split(/\s+/).map { |kv| kv.split(/=/) }.to_h
    end

    @ig_grouping = { "unconfigured" => {} }
    @config = {}
  end

  def set_instance_configured(ig_name, instance_id, configured)
    @ig_grouping[instance_id] ||= {}
    @ig_grouping[instance_id] = ig_name

    @config[ig_name] ||= {}
    @config[ig_name][instance_id] ||= {}
    @config[ig_name][instance_id][:configured] = configured
  end

  def set_instance_state(instance_id, state_str)
    ig_name = @ig_grouping[instance_id]
    ig_name ||= "unconfigured"

    @config[ig_name] ||= {}
    @config[ig_name][instance_id] ||= {}
    @config[ig_name][instance_id][:state] = state_str
  end

  def accepts_instance_group(instance_group)
    return @tg_instance_groups.include? instance_group
  end

  def match_instance_groups(possible_instance_groups)
    (possible_instance_groups & @tg_instance_groups).sort
  end

  # no worries if false, this is called for every target group
  # to find matches
  def attempt_add_instance(instance_id)
    @config.each do |ig_name, ig_data|
      if ig_data[instance_id] && ig_data[instance_id][:configured] == true
        if ig_data[instance_id][:state]
          # instance appears to already be configured
          puts "#{name}:#{ig_name}:#{instance_id}: already configured, state is #{ig_data[instance_id][:state]}"
        else
          set_instance_state(instance_id, "expected")
          return true
        end
      end
    end

    return false
  end

  def attempt_add_group(ig_name)
    adding = []

    if @config[ig_name] && ! @config[ig_name].empty?
      @config[ig_name].keys.each do |instance_id|
        if attempt_add_instance(instance_id)
          adding << instance_id
        end
      end
    end

    adding
  end

  def attempt_add_groupOLD(ig_name)
    adding = []

    if @config[ig_name]
      if @config[ig_name][ig_data] && ! @config[ig_name][ig_data].empty?
        @config[ig_name][ig_data].keys.each do |instance_id|
          if attempt_add_instance(instance_id)
            adding << instance_id
          end
        end
      end
    end

    adding
  end

  def attempt_remove_instance(instance_id)
    @config.each do |ig_name, ig_data|
      if ig_data[instance_id]
        if ig_data[instance_id][:state]
          if [ "draining", "removing" ].include? ig_data[instance_id][:state]
            puts "#{name}:#{ig_name}:#{instance_id}: already removed (ig_data[instance_id][:state])"
            return false
          else
            set_instance_state(instance_id, "removing")
            set_instance_configured(ig_name, instance_id, false)
            return true
          end
        else
          # instance is configured but already missing
          puts "instance is configured but already missing"
          return false
        end
      end
    end

    return false
  end

  def attempt_remove_group(ig_name)
    removing = []

    if @config[ig_name] && ! @config[ig_name].empty?
      @config[ig_name].keys.each do |instance_id|
        if attempt_remove_instance(instance_id)
          removing << instance_id
        end
      end
    end

    removing
  end

  def print
    puts print_to_str.join("\n")
  end

  def print_to_str
    out = []
    out << "\n== Target group " + @name

    @tg_instance_groups.each do |ig_name|

      if ! @config[ig_name]
        out << "   #{ig_name} (empty)"
      else
        out << "   #{ig_name}"
        @config[ig_name].each do |instance_id, instance_data|

          out << sprintf("     %-25s %-15s %-15s",
                  Instance.name_id(instance_id),
                  (instance_data[:configured] == true ? "configured" : "unconfigured"),
                  instance_data[:state] )
        end
      end
    end

    out
  end

  def healthy_count
    @config.map { |ig_name, ig_data|
      next unless @tg_instance_groups.include? ig_name
      ig_data.select { |instance_id, instance_data|
        instance_data[:state] == "healthy" || instance_data[:state] == "expected"
      }.size
    }.reduce(&:+)
  end

  def ig_healthy_count(ig_name)
    ( @config[ig_name] || [] ).select { |instance_id, instance_data|
      instance_data[:state] == "healthy" || instance_data[:state] == "expected"
    }.size
  end

  def validate
    errors = []

    ## too few overall instances
    if policies["instance_min"]
      total_instances = healthy_count
      if total_instances < policies["instance_min"].to_i
        errors << "not enough total instances: #{total_instances} < #{policies["instance_min"]}"
      end
    end

    ## instance groups with too few instances
    if policies["instance_group_min"]
      @config.each do |ig_name, ig_data|
        # if the TG isn't tagged to have this group, lets not count it
        next unless @tg_instance_groups.include? ig_name

        ig_total_instances = ig_healthy_count(ig_name)
        if ig_total_instances < policies["instance_group_min"].to_i
          errors << "not enough instances in group #{ig_name}: #{ig_total_instances} < #{policies["instance_group_min"]}"
        end
      end
    end

    # unconfigured instances
    @config.each do |ig_name, ig_data|
      if ! @tg_instance_groups.include? ig_name
        errors << "unconfigured instance group: #{ig_name}"
      else
        ig_data.each do |instance_id, instance_data|
          if ! instance_data[:configured] && ! [ "removing", "draining" ].include?(instance_data[:state])
            errors << "instance #{instance_id} in #{ig_name} is unexpected based on tags"
          end
        end
      end
    end

    errors
  end

  def validate_strict
    errors = validate

    ## missing instances
    @config.each do |ig_name, ig_data|
      ig_data.each do |instance_id, instance_data|
        if instance_data[:configured] && ! [ "healthy", "adding" ].include?(instance_data[:state])
          errors << "instance #{instance_id} missing in #{ig_name}"
        end
      end
    end

    errors
  end
end
