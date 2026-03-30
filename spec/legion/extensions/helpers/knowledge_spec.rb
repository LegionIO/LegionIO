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

  # Anonymous subclass that overrides layered defaults to verify the LEX override path
  let(:custom_runner_class) do
    Class.new do
      include Legion::Extensions::Helpers::Knowledge

      def self.name
        'Legion::Extensions::CustomExt::Runners::CustomRunner'
      end

      def knowledge_default_scope
        :local
      end

      def knowledge_default_tags
        %w[custom ext-tag]
      end
    end
  end

  let(:custom_runner) { custom_runner_class.new }

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

      it 'merges knowledge_default_tags into the call' do
        allow(Legion::Apollo).to receive(:ingest).and_return({ success: true, mode: :async })
        custom_runner.instance_variable_set(:@apollo_started, nil)
        allow(Legion::Apollo).to receive(:started?).and_return(true)
        custom_runner.ingest_knowledge('tagged text', tags: %w[explicit])
        expect(Legion::Apollo).to have_received(:ingest).with(
          hash_including(tags: include('custom', 'ext-tag', 'explicit'))
        )
      end

      it 'uses empty knowledge_default_tags by default' do
        runner.ingest_knowledge('plain', tags: %w[only])
        expect(Legion::Apollo).to have_received(:ingest).with(
          hash_including(tags: %w[only])
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

  # --- Status checks ---

  describe '#knowledge_connected?' do
    context 'when neither store is available' do
      it 'returns false' do
        expect(runner.knowledge_connected?).to be false
      end
    end

    context 'when only global Apollo is available' do
      before { allow(Legion::Apollo).to receive(:started?).and_return(true) }

      it 'returns true' do
        expect(runner.knowledge_connected?).to be true
      end
    end

    context 'when only Apollo::Local is available' do
      before do
        stub_const('Legion::Apollo::Local', Module.new do
          extend self

          define_method(:started?) { true }
        end)
      end

      it 'returns true' do
        expect(runner.knowledge_connected?).to be true
      end
    end

    context 'when both stores are available' do
      before do
        allow(Legion::Apollo).to receive(:started?).and_return(true)
        stub_const('Legion::Apollo::Local', Module.new do
          extend self

          define_method(:started?) { true }
        end)
      end

      it 'returns true' do
        expect(runner.knowledge_connected?).to be true
      end
    end
  end

  describe '#knowledge_global_connected?' do
    it 'returns false when Apollo is not available' do
      expect(runner.knowledge_global_connected?).to be false
    end

    it 'returns true when Apollo is started' do
      allow(Legion::Apollo).to receive(:started?).and_return(true)
      expect(runner.knowledge_global_connected?).to be true
    end

    it 'returns false when Apollo.started? returns false' do
      allow(Legion::Apollo).to receive(:started?).and_return(false)
      expect(runner.knowledge_global_connected?).to be false
    end
  end

  describe '#knowledge_local_connected?' do
    it 'returns false when Apollo::Local is not defined' do
      expect(runner.knowledge_local_connected?).to be false
    end

    it 'returns true when Apollo::Local is started' do
      stub_const('Legion::Apollo::Local', Module.new do
        extend self

        define_method(:started?) { true }
      end)
      expect(runner.knowledge_local_connected?).to be true
    end

    it 'returns false when Apollo::Local.started? returns false' do
      stub_const('Legion::Apollo::Local', Module.new do
        extend self

        define_method(:started?) { false }
      end)
      expect(runner.knowledge_local_connected?).to be false
    end
  end

  # --- Layered defaults ---

  describe '#knowledge_default_scope' do
    context 'when Legion::Settings is not defined' do
      it 'returns :all' do
        expect(runner.knowledge_default_scope).to eq(:all)
      end
    end

    context 'when Settings returns a scope' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:apollo, :local, :default_query_scope).and_return('local')
      end

      it 'returns the settings value as a symbol' do
        expect(runner.knowledge_default_scope).to eq(:local)
      end
    end

    context 'when Settings returns nil' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:apollo, :local, :default_query_scope).and_return(nil)
      end

      it 'falls back to :all' do
        expect(runner.knowledge_default_scope).to eq(:all)
      end
    end

    context 'when Settings raises' do
      before do
        allow(Legion::Settings).to receive(:dig).and_raise(StandardError, 'boom')
      end

      it 'falls back to :all' do
        expect(runner.knowledge_default_scope).to eq(:all)
      end
    end

    context 'when overridden in a LEX subclass' do
      it 'returns the overridden scope' do
        expect(custom_runner.knowledge_default_scope).to eq(:local)
      end
    end
  end

  describe '#knowledge_default_tags' do
    it 'returns an empty array by default' do
      expect(runner.knowledge_default_tags).to eq([])
    end

    it 'returns the overridden tags in a LEX subclass' do
      expect(custom_runner.knowledge_default_tags).to eq(%w[custom ext-tag])
    end
  end

  # --- default_query_scope private delegate ---

  describe 'private #default_query_scope' do
    it 'delegates to knowledge_default_scope' do
      expect(runner).to receive(:knowledge_default_scope).and_call_original
      runner.send(:default_query_scope)
    end

    it 'returns the same value as knowledge_default_scope' do
      expect(runner.send(:default_query_scope)).to eq(runner.knowledge_default_scope)
    end
  end
end
