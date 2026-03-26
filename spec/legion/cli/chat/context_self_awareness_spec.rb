# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/cli/chat/context'

RSpec.describe Legion::CLI::Chat::Context, '.to_system_prompt self-awareness' do
  let(:tmpdir) { Dir.mktmpdir('context-self-awareness-test') }

  after { FileUtils.rm_rf(tmpdir) }

  before do
    # Stub out network-dependent helpers so tests are deterministic.
    allow(described_class).to receive(:daemon_hint).and_return(nil)
    allow(described_class).to receive(:apollo_hint).and_return(nil)
    allow(described_class).to receive(:memory_hint).and_return(nil)
  end

  describe 'self-awareness injection' do
    context 'when lex-agentic-self is loaded' do
      before do
        runners_mod = Module.new do
          def self.self_narrative
            { prose: 'I am a brain_modeled cognitive_agent with 47 active extensions.' }
          end
        end
        stub_const('Legion::Extensions::Agentic::Self::Metacognition::Runners::Metacognition', runners_mod)
      end

      it 'includes the self-awareness section in the system prompt' do
        result = described_class.to_system_prompt(tmpdir)
        expect(result).to include('Current self-awareness:')
      end

      it 'includes the narrative prose in the system prompt' do
        result = described_class.to_system_prompt(tmpdir)
        expect(result).to include('I am a brain_modeled cognitive_agent with 47 active extensions.')
      end
    end

    context 'when lex-agentic-self is NOT loaded' do
      it 'does not include the self-awareness section' do
        result = described_class.to_system_prompt(tmpdir)
        expect(result).not_to include('Current self-awareness:')
      end

      it 'still returns a valid system prompt' do
        result = described_class.to_system_prompt(tmpdir)
        expect(result).to include('Legion')
      end
    end

    context 'when self_narrative raises an exception' do
      before do
        runners_mod = Module.new do
          def self.self_narrative
            raise StandardError, 'metacognition unavailable'
          end
        end
        stub_const('Legion::Extensions::Agentic::Self::Metacognition::Runners::Metacognition', runners_mod)
      end

      it 'does not raise' do
        expect { described_class.to_system_prompt(tmpdir) }.not_to raise_error
      end

      it 'does not include the self-awareness section' do
        result = described_class.to_system_prompt(tmpdir)
        expect(result).not_to include('Current self-awareness:')
      end

      it 'still returns a valid system prompt' do
        result = described_class.to_system_prompt(tmpdir)
        expect(result).to include('Legion')
      end
    end
  end
end
