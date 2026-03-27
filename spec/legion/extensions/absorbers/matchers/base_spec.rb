# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/absorbers/matchers/base'

module Legion
  module Extensions
    module Absorbers
      module Matchers
        class TestMatcherAuto < Base
          def self.type = :test_matcher_auto
          def self.match?(_pattern, _input) = true
        end
      end
    end
  end
end

RSpec.describe Legion::Extensions::Absorbers::Matchers::Base do
  describe '.registry' do
    it 'returns a hash' do
      expect(described_class.registry).to be_a(Hash)
    end
  end

  describe '.for_type' do
    it 'returns nil for unknown types' do
      expect(described_class.for_type(:nonexistent)).to be_nil
    end
  end

  describe '.type' do
    it 'returns nil on base class' do
      expect(described_class.type).to be_nil
    end
  end

  describe 'auto-registration via inherited' do
    it 'registers subclasses that define a type' do
      expect(described_class.for_type(:test_matcher_auto)).to eq(
        Legion::Extensions::Absorbers::Matchers::TestMatcherAuto
      )
    end
  end
end
