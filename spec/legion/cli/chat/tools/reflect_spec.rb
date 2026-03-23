# frozen_string_literal: true

require 'spec_helper'
require 'legion/cli/chat/tools/reflect'

RSpec.describe Legion::CLI::Chat::Tools::Reflect do
  subject(:tool) { described_class.new }

  let(:stub_http) { instance_double(Net::HTTP) }
  let(:success_response) { instance_double(Net::HTTPSuccess, is_a?: true) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(stub_http)
    allow(stub_http).to receive(:open_timeout=)
    allow(stub_http).to receive(:read_timeout=)
  end

  describe '#execute' do
    context 'without LLM available' do
      before do
        allow(stub_http).to receive(:request).and_return(success_response)
        allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        memory_store = Module.new do
          def self.add(_text, scope:); end
        end
        stub_const('Legion::CLI::Chat::MemoryStore', memory_store)
      end

      it 'ingests the raw text as a single entry' do
        result = tool.execute(text: 'Ruby blocks capture their enclosing scope')
        expect(result).to include('Reflected on 1 knowledge entries')
        expect(result).to include('Ruby blocks capture their enclosing scope')
      end
    end

    context 'with LLM available' do
      let(:llm_response) do
        double('response', content: "- Pattern: use **opts for extensible params\n- Convention: snake_case for methods\n")
      end

      before do
        llm = Module.new do
          def self.chat_direct(**); end

          def self.respond_to?(method, *args)
            return true if method == :chat_direct

            super
          end
        end
        stub_const('Legion::LLM', llm)
        allow(llm).to receive(:chat_direct).and_return(llm_response)

        allow(stub_http).to receive(:request).and_return(success_response)
        allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        memory_store = Module.new do
          def self.add(_text, scope:); end
        end
        stub_const('Legion::CLI::Chat::MemoryStore', memory_store)
      end

      it 'extracts and ingests multiple entries' do
        result = tool.execute(text: 'We used **opts pattern and snake_case conventions')
        expect(result).to include('Reflected on 2 knowledge entries')
        expect(result).to include('Pattern: use **opts for extensible params')
        expect(result).to include('Convention: snake_case for methods')
      end

      it 'reports save counts' do
        result = tool.execute(text: 'We used **opts pattern')
        expect(result).to include('Saved: 2 to Apollo, 2 to memory')
      end
    end

    context 'when apollo is unreachable but memory works' do
      before do
        allow(stub_http).to receive(:request).and_raise(Errno::ECONNREFUSED)

        memory_store = Module.new do
          def self.add(_text, scope:); end
        end
        stub_const('Legion::CLI::Chat::MemoryStore', memory_store)
      end

      it 'saves to memory only' do
        result = tool.execute(text: 'Important finding')
        expect(result).to include('0 to Apollo')
        expect(result).to include('1 to memory')
      end
    end

    context 'with no actionable entries from LLM' do
      let(:llm_response) { double('response', content: 'Nothing useful here.') }

      before do
        llm = Module.new do
          def self.chat_direct(**); end

          def self.respond_to?(method, *args)
            return true if method == :chat_direct

            super
          end
        end
        stub_const('Legion::LLM', llm)
        allow(llm).to receive(:chat_direct).and_return(llm_response)
      end

      it 'returns no actionable knowledge message' do
        result = tool.execute(text: 'Just chatting about nothing')
        expect(result).to include('No actionable knowledge')
      end
    end

    context 'with domain specified' do
      before do
        allow(stub_http).to receive(:request).and_return(success_response)
        allow(success_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

        memory_store = Module.new do
          def self.add(_text, scope:); end
        end
        stub_const('Legion::CLI::Chat::MemoryStore', memory_store)
      end

      it 'passes domain to apollo ingest' do
        tool.execute(text: 'Database indexes speed up queries', domain: 'database')
        expect(stub_http).to have_received(:request).with(
          an_object_having_attributes(body: a_string_including('"knowledge_domain":"database"'))
        )
      end
    end
  end
end
