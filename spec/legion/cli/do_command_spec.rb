# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/output'
require 'legion/cli/do_command'

RSpec.describe Legion::CLI::DoCommand do
  let(:formatter) { instance_double(Legion::CLI::Output::Formatter) }
  let(:options) { { json: false, no_color: false } }

  before do
    allow(formatter).to receive(:detail)
    allow(formatter).to receive(:success)
    allow(formatter).to receive(:error)
    allow(formatter).to receive(:json)
  end

  describe '.run' do
    context 'with empty intent' do
      it 'shows usage error' do
        allow(formatter).to receive(:error)
        expect { described_class.run('', formatter, options) }.to raise_error(SystemExit)
        expect(formatter).to have_received(:error).with(/Usage/)
      end
    end

    context 'with whitespace-only intent' do
      it 'shows usage error' do
        expect { described_class.run('   ', formatter, options) }.to raise_error(SystemExit)
      end
    end

    context 'when no daemon and no registry matches' do
      it 'shows no matching tool error' do
        Legion::Tools::Registry.clear
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)
        expect { described_class.run('nonexistent thing', formatter, options) }.to raise_error(SystemExit)
        expect(formatter).to have_received(:error).with(/No matching tool/)
      end
    end

    context 'when LLM fallback classifies intent' do
      let(:tool_class) do
        Class.new(Legion::Tools::Base) do
          tool_name 'legion.consul.health_check.run'
          description 'Check consul cluster health'
          extension 'consul'
          runner 'health_check'

          class << self
            def call(**_args)
              text_response({ status: 'healthy' })
            end
          end
        end
      end

      before do
        Legion::Tools::Registry.clear
        Legion::Tools::Registry.register(tool_class)
      end

      after { Legion::Tools::Registry.clear }

      it 'routes via LLM when keyword matching fails' do
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

        llm_mod = Module.new do
          def self.ask(**)
            { response: 'legion.consul.health_check.run' }
          end
        end
        stub_const('Legion::LLM', llm_mod)

        described_class.run('is consul ok', formatter, options)
        expect(formatter).to have_received(:success).with(/Matched/)
      end

      it 'falls through when LLM returns NONE' do
        Legion::Tools::Registry.clear
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

        llm_mod = Module.new do
          def self.ask(**)
            { response: 'NONE' }
          end
        end
        stub_const('Legion::LLM', llm_mod)

        expect { described_class.run('completely unrelated', formatter, options) }.to raise_error(SystemExit)
        expect(formatter).to have_received(:error).with(/No matching tool/)
      end
    end

    context 'when registry has a match' do
      let(:tool_class) do
        Class.new(Legion::Tools::Base) do
          tool_name 'legion.consul.health_check.run'
          description 'check consul health'

          class << self
            def call(**_args)
              text_response({ status: 'healthy' })
            end
          end
        end
      end

      before do
        Legion::Tools::Registry.clear
        Legion::Tools::Registry.register(tool_class)
      end

      after { Legion::Tools::Registry.clear }

      it 'returns matched result' do
        allow(Net::HTTP).to receive(:new).and_raise(Errno::ECONNREFUSED)

        described_class.run('check consul health', formatter, options)
        expect(formatter).to have_received(:success).with(/Matched/)
      end
    end
  end

  describe '.build_runner_class (via private method)' do
    it 'builds correct runner class string' do
      result = described_class.send(:build_runner_class, 'lex-consul', 'health_check')
      expect(result).to eq('Legion::Extensions::Consul::Runners::HealthCheck')
    end

    it 'handles multi-word extension names' do
      result = described_class.send(:build_runner_class, 'lex-microsoft-teams', 'message_sender')
      expect(result).to eq('Legion::Extensions::MicrosoftTeams::Runners::MessageSender')
    end
  end
end
