# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/capability'

RSpec.describe Legion::Extensions::Capability do
  describe '.from_absorber' do
    let(:absorber_class) do
      Class.new(Legion::Extensions::Absorbers::Base) do
        pattern :url, 'example.com/docs/*'
        description 'Test absorber'
        def self.name = 'TestAbsorber'
        def handle(**) = { success: true }
      end
    end

    it 'creates a capability from an absorber class' do
      cap = described_class.from_absorber(
        extension:   'lex-example',
        absorber:    absorber_class,
        patterns:    absorber_class.patterns,
        description: absorber_class.description
      )
      expect(cap.name).to include('absorber')
      expect(cap.extension).to eq('lex-example')
      expect(cap.description).to eq('Test absorber')
      expect(cap.tags).to include('absorber')
    end

    it 'includes pattern info in tags' do
      cap = described_class.from_absorber(
        extension: 'lex-example',
        absorber:  absorber_class,
        patterns:  absorber_class.patterns
      )
      expect(cap.tags.any? { |t| t.include?('pattern:url:') }).to be true
    end
  end
end
