# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Transport do
  before(:all) do
    unless Legion::Extensions.const_defined?('Agentic', false)
      agentic = Module.new
      cognitive = Module.new
      anchor = Module.new
      cognitive.const_set('Anchor', anchor)
      agentic.const_set('Cognitive', cognitive)
      Legion::Extensions.const_set('Agentic', agentic)
    end
  end

  let(:mock_extension) do
    Module.new do
      extend Legion::Extensions::Helpers::Transport

      def self.calling_class_array
        %w[Legion Extensions Agentic Cognitive Anchor]
      end

      def self.transport_class
        @transport_class ||= begin
          mod = Module.new
          mod.const_set('Exchanges', Module.new)
          mod
        end
      end

      def self.full_path
        '/fake/path'
      end
    end
  end

  describe '#amqp_prefix' do
    it 'returns dot-joined segments with legion prefix' do
      expect(mock_extension.amqp_prefix).to eq('legion.agentic.cognitive.anchor')
    end
  end

  describe '#build_default_exchange' do
    it 'creates an exchange class with exchange_name returning amqp_prefix' do
      exchange_class = mock_extension.build_default_exchange
      # Use allocate to skip initialize (which requires a live RabbitMQ connection)
      expect(exchange_class.allocate.exchange_name).to eq('legion.agentic.cognitive.anchor')
    end

    it 'registers the exchange constant under lex_const name' do
      mock_extension.build_default_exchange
      expect(mock_extension.transport_class::Exchanges.const_defined?('Anchor')).to be true
    end
  end

  let(:flat_extension) do
    Module.new do
      extend Legion::Extensions::Helpers::Transport

      def self.calling_class_array
        %w[Legion Extensions Node]
      end

      def self.transport_class
        @transport_class ||= begin
          mod = Module.new
          mod.const_set('Exchanges', Module.new)
          mod
        end
      end

      def self.full_path
        '/fake/path'
      end
    end
  end

  context 'with a flat extension (single segment)' do
    before(:all) do
      Legion::Extensions.const_set('Node', Module.new) unless Legion::Extensions.const_defined?('Node', false)
    end

    describe '#amqp_prefix' do
      it 'returns legion.node for a flat extension' do
        expect(flat_extension.amqp_prefix).to eq('legion.node')
      end
    end

    describe '#build_default_exchange' do
      it 'creates an exchange class with exchange_name returning legion.node' do
        exchange_class = flat_extension.build_default_exchange
        expect(exchange_class.allocate.exchange_name).to eq('legion.node')
      end

      it 'registers the exchange constant under Node' do
        flat_extension.build_default_exchange
        expect(flat_extension.transport_class::Exchanges.const_defined?('Node')).to be true
      end
    end
  end
end
