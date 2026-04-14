# frozen_string_literal: true

require 'spec_helper'
require 'legion/fleet/conditioner_rules'

RSpec.describe Legion::Fleet::ConditionerRules do
  describe '.rules' do
    subject(:rules) { described_class.rules }

    it 'returns an array' do
      expect(rules).to be_a(Array)
    end

    it 'has rules for fleet routing' do
      expect(rules).not_to be_empty
    end

    it 'each rule has required keys' do
      rules.each do |rule|
        expect(rule).to have_key(:name)
        expect(rule).to have_key(:conditions)
      end
    end

    it 'includes planning skip rule' do
      names = rules.map { |r| r[:name] }
      expect(names).to include('fleet-skip-planning-trivial')
    end

    it 'includes escalation rule' do
      names = rules.map { |r| r[:name] }
      expect(names).to include('fleet-escalate-max-iterations')
    end
  end

  describe '.seed!' do
    it 'is defined as a class method' do
      expect(described_class).to respond_to(:seed!)
    end

    it 'returns a result hash' do
      result = described_class.seed!
      expect(result).to be_a(Hash)
      expect(result).to have_key(:success)
    end
  end
end
