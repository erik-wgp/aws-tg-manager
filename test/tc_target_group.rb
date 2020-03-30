#!/bin/env ruby

require_relative '../lib/init.rb'

#$DEBUG = true

class TestTargetGroup < Test::Unit::TestCase
  def setup
    $tag_names = {
      "INSTANCE_GROUPS_TAG" => "InstanceGroups",
      "TG_INSTANCE_GROUPS_TAG" => "InstanceGroups",
      "TG_POLICY_TAG" => "Policy"
    }

    @full_state = {
      "groupA" => {
        "i-servera1" => { state: "healthy", configured: true },
        "i-servera2" => { state: "healthy", configured: true },
        "i-servera3" => { state: "healthy", configured: true }
      },
      "groupB" => {
        "i-serverb1" => { state: "healthy", configured: true },
        "i-serverb2" => { state: "healthy", configured: true },
        "i-serverb3" => { state: "healthy", configured: true }
      }
    }

    @tags_ig_min    = { "Policy" =>                "instance_group_min=3", "InstanceGroups" => "groupA groupB" }
    @tags_total_min = { "Policy" => "instance_min=3",                      "InstanceGroups" => "groupA groupB" }
    @tags_both_min  = { "Policy" => "instance_min=3 instance_group_min=3", "InstanceGroups" => "groupA groupB" }

    @tags_no_min1   = { "Policy" => "instance_min=0 instance_group_min=3", "InstanceGroups" => "groupA groupB" }
    @tags_no_min2   = { "Policy" => "instance_min=3 instance_group_min=0", "InstanceGroups" => "groupA groupB" }
    @tags_no_min3   = { "Policy" => "instance_min=0 instance_group_min=0", "InstanceGroups" => "groupA groupB" }
    @tags_no_min4   = { "Policy" => "instance_min=0",                      "InstanceGroups" => "groupA groupB" }
    @tags_no_min5   = { "Policy" =>                "instance_group_min=0", "InstanceGroups" => "groupA groupB" }

  end

  def assign_health_state(tg, state)
    state.each do |ig_name, ig_data|
      ig_data.each do |instance_id, instance_data|
        tg.set_instance_configured(ig_name, instance_id, instance_data[:configured])
        tg.set_instance_state(instance_id, instance_data[:state])
      end
    end
  end

  def test_valid_tg
    @tg = TargetGroup.new(arn: "tg-arn-string", name: "tg-name", tags: @tags_both_min)
    assign_health_state(@tg, @full_state)
    assert_empty @tg.validate
  end

  def test_ig_low
    @tg = TargetGroup.new(arn: "tg-arn-string", name: "tg-name", tags: @tags_ig_min)

    @full_state["groupB"].delete("i-serverb2")
    assign_health_state(@tg, @full_state)
    assert_false @tg.validate.empty?
  end

  def test_total_low
    @tg = TargetGroup.new(arn: "tg-arn-string", name: "tg-name", tags: @tags_total_min)
    assign_health_state(@tg, { "groupA" => { "server1" => { state: "healthy", configured: true } } })
    assert_false @tg.validate.empty?
  end

  def test_unconfigured_instance
    @tg = TargetGroup.new(arn: "tg-arn-string", name: "tg-name", tags: @tags_no_min4)
    @full_state["groupA"]["i-servera4"] = { state: "healthy", configured: true }
    assign_health_state(@tg, @full_state)
    assert_false @tg.validate_strict.size == 1
  end

  def test_unconfigured_instance_and_ig
    @tg = TargetGroup.new(arn: "tg-arn-string", name: "tg-name", tags: @tags_both_min)

    @full_state["groupC"] = {}
    @full_state["groupC"]["i-serverc1"] = { state: "healthy", configured: true }
    assign_health_state(@tg, @full_state)

    errors = @tg.validate_strict

    assert_true (errors && errors.size == 1)
    assert_match(/unconfigured instance group: groupC/, errors[0])
  end

end

