# frozen_string_literal: true

require 'spec_helper'
require 'legion/apollo'
require 'legion/extensions/helpers/knowledge'

# Test harness — include the helper into a test class
class KnowledgeTestRunner
  include Legion::Extensions::Helpers::Knowledge

  def self.name
    'Legion::Extensions::TestExt::Runners::TestRunner'
  end
end

RSpec.describe Legion::Extensions::Helpers::Knowledge do
  let(:runner) { KnowledgeTestRunner.new }

  describe '#ingest_knowledge' do
    context 'when Apollo is not available' do
      it 'returns apollo_not_available' do
        result = runner.ingest_knowledge('test text', tags: %w[test])
        expect(result).to eq({ success: false, error: :apollo_not_available })
      end
    end

    context 'when Apollo is available' do
      before do
        allow(Legion::Apollo).to receive(:started?).and_return(true)
        allow(Legion::Apollo).to receive(:ingest).and_return({ success: true, mode: :async })
      end

      it 'sends plain text to Apollo' do
        result = runner.ingest_knowledge('some knowledge', tags: %w[test])
        expect(result[:success]).to be true
        expect(Legion::Apollo).to have_received(:ingest).with(
          hash_including(content: 'some knowledge', tags: %w[test])
        )
      end

      it 'derives lex_name from class hierarchy' do
        runner.ingest_knowledge('text')
        expect(Legion::Apollo).to have_received(:ingest).with(
          hash_including(source_channel: 'testext')
        )
      end

      it 'allows source_channel override' do
        runner.ingest_knowledge('text', source_channel: 'custom')
        expect(Legion::Apollo).to have_received(:ingest).with(
          hash_including(source_channel: 'custom')
        )
      end
    end

    context 'when scope is :local' do
      before do
        stub_const('Legion::Apollo::Local', Module.new do
          extend self

          define_method(:started?) { true }
          define_method(:ingest) { |**_| { success: true, mode: :local } }
        end)
        allow(Legion::Apollo::Local).to receive(:ingest).and_return({ success: true, mode: :local })
      end

      it 'routes to Apollo::Local' do
        result = runner.ingest_knowledge('private data', tags: %w[secret], scope: :local)
        expect(result[:mode]).to eq(:local)
        expect(Legion::Apollo::Local).to have_received(:ingest).with(
          hash_including(content: 'private data')
        )
      end
    end

    context 'when Data::Extract is available' do
      before do
        allow(Legion::Apollo).to receive(:started?).and_return(true)
        allow(Legion::Apollo).to receive(:ingest).and_return({ success: true })
        stub_const('Legion::Data::Extract', double(
                                              extract: { success: true, text: 'extracted text', metadata: { pages: 5 }, type: :pdf }
                                            ))
        allow(File).to receive(:exist?).and_return(true)
      end

      it 'extracts files before ingesting' do
        result = runner.ingest_knowledge('/tmp/doc.pdf', tags: %w[doc])
        expect(result[:success]).to be true
        expect(Legion::Apollo).to have_received(:ingest).with(
          hash_including(content: 'extracted text', tags: include('pages:5'))
        )
      end
    end
  end

  describe '#query_knowledge' do
    context 'when Apollo is not available' do
      it 'returns apollo_not_available' do
        result = runner.query_knowledge(text: 'test')
        expect(result).to eq({ success: false, error: :apollo_not_available })
      end
    end

    context 'when Apollo is available' do
      before do
        allow(Legion::Apollo).to receive(:started?).and_return(true)
        allow(Legion::Apollo).to receive(:query).and_return({ success: true, results: [] })
      end

      it 'delegates to Apollo.query' do
        result = runner.query_knowledge(text: 'question', limit: 3)
        expect(result[:success]).to be true
        expect(Legion::Apollo).to have_received(:query).with(text: 'question', limit: 3)
      end
    end

    context 'when scope is :local' do
      before do
        stub_const('Legion::Apollo::Local', Module.new do
          extend self

          define_method(:started?) { true }
          define_method(:query) { |**_| { success: true, results: [{ content: 'local result' }], mode: :local } }
        end)
        allow(Legion::Apollo::Local).to receive(:query).and_return({ success: true, results: [], mode: :local })
      end

      it 'queries only local store' do
        allow(Legion::Apollo::Local).to receive(:query).and_return({ success: true, results: [], mode: :local })
        result = runner.query_knowledge(text: 'test', scope: :local)
        expect(result[:mode]).to eq(:local)
      end
    end

    context 'when scope is :all' do
      before do
        allow(Legion::Apollo).to receive(:started?).and_return(true)
        allow(Legion::Apollo).to receive(:query).and_return({ success: true, results: [{ content: 'global', content_hash: 'g1' }] })
        stub_const('Legion::Apollo::Local', Module.new do
          extend self

          define_method(:started?) { true }
          define_method(:query) { |**_| { success: true, results: [{ content: 'local', content_hash: 'l1' }] } }
        end)
        allow(Legion::Apollo::Local).to receive(:query).and_return({ success: true, results: [{ content: 'local', content_hash: 'l1' }] })
      end

      it 'merges results from both stores' do
        result = runner.query_knowledge(text: 'test', scope: :all)
        expect(result[:results].size).to eq(2)
      end

      it 'deduplicates by content_hash with local winning' do
        allow(Legion::Apollo).to receive(:query).and_return({ success: true, results: [{ content: 'global version', content_hash: 'same' }] })
        allow(Legion::Apollo::Local).to receive(:query).and_return({ success: true, results: [{ content: 'local version', content_hash: 'same' }] })
        result = runner.query_knowledge(text: 'test', scope: :all)
        expect(result[:results].size).to eq(1)
        expect(result[:results].first[:content]).to eq('local version')
      end
    end
  end
end
