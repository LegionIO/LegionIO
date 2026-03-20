# frozen_string_literal: true

require 'spec_helper'
require 'legion/alerts'

RSpec.describe 'Legion::Alerts safety rules' do
  let(:default_rules) { Legion::Alerts::DEFAULT_RULES }

  it 'includes safety_action_burst rule' do
    rule = default_rules.find { |r| r[:name] == 'safety_action_burst' }
    expect(rule).not_to be_nil
    expect(rule[:severity]).to eq('warning')
  end

  it 'includes safety_scope_escalation_spike rule' do
    rule = default_rules.find { |r| r[:name] == 'safety_scope_escalation_spike' }
    expect(rule).not_to be_nil
    expect(rule[:severity]).to eq('critical')
  end

  it 'includes safety_probe_detected rule' do
    rule = default_rules.find { |r| r[:name] == 'safety_probe_detected' }
    expect(rule).not_to be_nil
    expect(rule[:severity]).to eq('critical')
    expect(rule[:cooldown_seconds]).to eq(0)
  end

  it 'includes safety_confidence_collapse rule' do
    rule = default_rules.find { |r| r[:name] == 'safety_confidence_collapse' }
    expect(rule).not_to be_nil
    expect(rule[:severity]).to eq('warning')
  end

  it 'has 8 total default rules (4 original + 4 safety)' do
    expect(default_rules.size).to eq(8)
  end
end
