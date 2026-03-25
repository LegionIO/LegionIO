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
  end
end
