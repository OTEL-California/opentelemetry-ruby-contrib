# frozen_string_literal: true

# Copyright OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

describe OpenTelemetry::Sampler::XRay::RuleCache do
  def create_rule(name, priority, reservoir_size, fixed_rate)
    test_sampling_rule = {
      'RuleName' => name,
      'Priority' => priority,
      'ReservoirSize' => reservoir_size,
      'FixedRate' => fixed_rate,
      'ServiceName' => '*',
      'ServiceType' => '*',
      'Host' => '*',
      'HTTPMethod' => '*',
      'URLPath' => '*',
      'ResourceARN' => '*',
      'Version' => 1
    }
    OpenTelemetry::Sampler::XRay::SamplingRuleApplier.new(OpenTelemetry::Sampler::XRay::SamplingRule.new(test_sampling_rule))
  end

  it 'test_cache_updates_and_sorts_rules' do
    # Set up default rule in rule cache
    default_rule = create_rule('Default', 10_000, 1, 0.05)
    cache = OpenTelemetry::Sampler::XRay::RuleCache.new(OpenTelemetry::SDK::Resources::Resource.create({}))
    cache.update_rules([default_rule])

    # Expect default rule to exist
    assert_equal 1, cache.instance_variable_get(:@rule_appliers).length

    # Set up incoming rules
    rule1 = create_rule('low', 200, 0, 0.0)
    rule2 = create_rule('abc', 100, 0, 0.0)
    rule3 = create_rule('Abc', 100, 0, 0.0)
    rule4 = create_rule('ab', 100, 0, 0.0)
    rule5 = create_rule('A', 100, 0, 0.0)
    rule6 = create_rule('high', 10, 0, 0.0)
    rules = [rule1, rule2, rule3, rule4, rule5, rule6]

    cache.update_rules(rules)

    rule_appliers = cache.instance_variable_get(:@rule_appliers)
    assert_equal rules.length, rule_appliers.length
    assert_equal 'high', rule_appliers[0].sampling_rule.rule_name
    assert_equal 'A', rule_appliers[1].sampling_rule.rule_name
    assert_equal 'Abc', rule_appliers[2].sampling_rule.rule_name
    assert_equal 'ab', rule_appliers[3].sampling_rule.rule_name
    assert_equal 'abc', rule_appliers[4].sampling_rule.rule_name
    assert_equal 'low', rule_appliers[5].sampling_rule.rule_name
  end

  it 'test_rule_cache_expiration_logic' do
    Timecop.freeze(Time.now) do
      default_rule = create_rule('Default', 10_000, 1, 0.05)
      cache = OpenTelemetry::Sampler::XRay::RuleCache.new(OpenTelemetry::SDK::Resources::Resource.create({}))
      cache.update_rules([default_rule])

      Timecop.travel(2 * 60 * 60) # Travel 2 hours into the future
      assert cache.expired?
    end
  end

  it 'test_update_cache_with_only_one_rule_changed' do
    cache = OpenTelemetry::Sampler::XRay::RuleCache.new(OpenTelemetry::SDK::Resources::Resource.create({}))
    rule1 = create_rule('rule_1', 1, 0, 0.0)
    rule2 = create_rule('rule_2', 10, 0, 0.0)
    rule3 = create_rule('rule_3', 100, 0, 0.0)
    rule_appliers = [rule1, rule2, rule3]

    cache.update_rules(rule_appliers)
    rule_appliers_copy = cache.instance_variable_get(:@rule_appliers).dup

    new_rule3 = create_rule('new_rule_3', 5, 0, 0.0)
    new_rule_appliers = [rule1, rule2, new_rule3]
    cache.update_rules(new_rule_appliers)

    current_appliers = cache.instance_variable_get(:@rule_appliers)
    assert_equal 3, current_appliers.length
    assert_equal 'rule_1', current_appliers[0].sampling_rule.rule_name
    assert_equal 'new_rule_3', current_appliers[1].sampling_rule.rule_name
    assert_equal 'rule_2', current_appliers[2].sampling_rule.rule_name

    assert_equal rule_appliers_copy[0], current_appliers[0]
    assert_equal rule_appliers_copy[1], current_appliers[2]
    refute_equal rule_appliers_copy[2], current_appliers[1]
  end

  it 'test_update_rules_removes_older_rule' do
    cache = OpenTelemetry::Sampler::XRay::RuleCache.new(OpenTelemetry::SDK::Resources::Resource.create({}))
    assert_equal 0, cache.instance_variable_get(:@rule_appliers).length

    rule1 = create_rule('first_rule', 200, 0, 0.0)
    cache.update_rules([rule1])

    rule_appliers = cache.instance_variable_get(:@rule_appliers)
    assert_equal 1, rule_appliers.length
    assert_equal 'first_rule', rule_appliers[0].sampling_rule.rule_name

    replacement_rule1 = create_rule('second_rule', 200, 0, 0.0)
    cache.update_rules([replacement_rule1])

    rule_appliers = cache.instance_variable_get(:@rule_appliers)
    assert_equal 1, rule_appliers.length
    assert_equal 'second_rule', rule_appliers[0].sampling_rule.rule_name
  end

  # TODO: Add tests for updating Sampling Targets and getting statistics
end
