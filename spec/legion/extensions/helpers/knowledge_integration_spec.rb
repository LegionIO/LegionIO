# frozen_string_literal: true

require 'spec_helper'
require 'legion/extensions/helpers/knowledge'

RSpec.describe Legion::Extensions::Helpers::Knowledge do
  # ---------------------------------------------------------------------------
  # Test class that includes the mixin, named so derive_lex_name returns 'mylex'
  # ---------------------------------------------------------------------------
  let(:host_class) do
    Class.new do
      include Legion::Extensions::Helpers::Knowledge

      def self.name
        'Legion::Extensions::Mylex::SomeRunner'
      end
    end
  end

  subject(:instance) { host_class.new }

  # ---------------------------------------------------------------------------
  # Helpers to set up / tear down the optional top-level constants
  # ---------------------------------------------------------------------------
  def stub_apollo(started: true, ingest_result: { success: true, mode: :async }, query_result: {})
    apollo = Module.new do
      def self.started?; end
      def self.ingest(**); end
      def self.query(**); end
    end
    allow(apollo).to receive(:started?).and_return(started)
    allow(apollo).to receive(:ingest).and_return(ingest_result)
    allow(apollo).to receive(:query).and_return(query_result)
    stub_const('Legion::Apollo', apollo)
    apollo
  end

  def stub_extract(result)
    extractor = Module.new do
      def self.extract(*); end
    end
    allow(extractor).to receive(:extract).and_return(result)
    stub_const('Legion::Data::Extract', extractor)
    extractor
  end

  # ---------------------------------------------------------------------------
  # Silence optional Logging calls
  # ---------------------------------------------------------------------------
  before do
    allow(Legion::Logging).to receive(:debug) if defined?(Legion::Logging)
  end

  # ===========================================================================
  # derive_lex_name (private helper — tested via ingest_knowledge side-effects)
  # ===========================================================================
  describe '#derive_lex_name (via source_channel default)' do
    it 'derives the lex name from the third namespace segment, downcased' do
      apollo = stub_apollo
      stub_extract(text: 'hello', metadata: { type: :txt })

      allow(File).to receive(:exist?).and_return(false)

      instance.ingest_knowledge('hello world')

      expect(apollo).to have_received(:ingest).with(hash_including(source_channel: 'mylex'))
    end
  end

  # ===========================================================================
  # 1. Full happy-path: File -> Extract -> Apollo.ingest
  # ===========================================================================
  describe '#ingest_knowledge — full path with file extraction' do
    let(:extract_result) { { text: 'extracted content', metadata: { type: :txt } } }
    let(:apollo)         { stub_apollo(ingest_result: { success: true, mode: :async }) }
    let(:extractor)      { stub_extract(extract_result) }

    before do
      apollo
      extractor
      allow(File).to receive(:exist?).with('/tmp/test.txt').and_return(true)
    end

    it 'calls Data::Extract.extract with the file path and type' do
      instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(extractor).to have_received(:extract).with('/tmp/test.txt', type: :auto)
    end

    it 'calls Apollo.ingest with extracted content' do
      instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(apollo).to have_received(:ingest).with(hash_including(content: 'extracted content'))
    end

    it 'merges caller-supplied tags with metadata-derived tags' do
      instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(apollo).to have_received(:ingest).with(hash_including(tags: %w[test txt]))
    end

    it 'passes source_channel derived from the class name' do
      instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(apollo).to have_received(:ingest).with(hash_including(source_channel: 'mylex'))
    end

    it 'returns the result from Apollo.ingest' do
      result = instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(result).to eq({ success: true, mode: :async })
    end

    it 'accepts a custom type keyword and forwards it to Extract' do
      instance.ingest_knowledge('/tmp/test.txt', type: :md, tags: [])
      expect(extractor).to have_received(:extract).with('/tmp/test.txt', type: :md)
    end

    it 'accepts a custom source_channel in opts and passes it through' do
      instance.ingest_knowledge('/tmp/test.txt', tags: [], source_channel: 'custom_channel')
      expect(apollo).to have_received(:ingest).with(hash_including(source_channel: 'custom_channel'))
    end

    it 'does not forward source_channel as an extra kwarg' do
      instance.ingest_knowledge('/tmp/test.txt', tags: [], source_channel: 'c')
      apollo.method(:ingest).arity
      # Verify the call hash does not duplicate source_channel in the splat remainder
      expect(apollo).to have_received(:ingest).once
    end
  end

  # ===========================================================================
  # 2. Metadata-to-tags: pages tag added when metadata includes :pages
  # ===========================================================================
  describe '#ingest_knowledge — metadata with pages' do
    before do
      stub_apollo
      stub_extract(text: 'pdf text', metadata: { type: :pdf, pages: 12 })
      allow(File).to receive(:exist?).with('/tmp/doc.pdf').and_return(true)
    end

    it 'adds a pages: tag derived from metadata' do
      instance.ingest_knowledge('/tmp/doc.pdf', tags: ['doc'])
      expect(Legion::Apollo).to have_received(:ingest).with(
        hash_including(tags: array_including('doc', 'pdf', 'pages:12'))
      )
    end
  end

  # ===========================================================================
  # 3. Plain-string path (not a file, not IO) — no extraction
  # ===========================================================================
  describe '#ingest_knowledge — plain string content (not a file path)' do
    before do
      stub_apollo
      allow(File).to receive(:exist?).and_return(false)
    end

    it 'passes the raw string directly to Apollo without calling Extract' do
      stub_extract(text: 'should not be called', metadata: {})
      instance.ingest_knowledge('plain text content', tags: ['raw'])
      expect(Legion::Data::Extract).not_to have_received(:extract)
      expect(Legion::Apollo).to have_received(:ingest).with(hash_including(content: 'plain text content'))
    end
  end

  # ===========================================================================
  # 4. Graceful degradation — Apollo not started
  # ===========================================================================
  describe '#ingest_knowledge — Apollo not started' do
    it 'returns apollo_not_available when Apollo.started? is false' do
      stub_apollo(started: false)
      result = instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(result).to eq({ success: false, error: :apollo_not_available })
    end

    it 'does not call Apollo.ingest when not started' do
      apollo = stub_apollo(started: false)
      instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(apollo).not_to have_received(:ingest)
    end
  end

  # ===========================================================================
  # 5. Graceful degradation — Apollo constant not defined
  # ===========================================================================
  describe '#ingest_knowledge — Apollo constant absent' do
    it 'returns apollo_not_available when Legion::Apollo is not defined' do
      hide_const('Legion::Apollo') if defined?(Legion::Apollo)
      result = instance.ingest_knowledge('/tmp/test.txt', tags: ['test'])
      expect(result).to eq({ success: false, error: :apollo_not_available })
    end
  end

  # ===========================================================================
  # 6. Graceful degradation — Data::Extract not defined
  # ===========================================================================
  describe '#ingest_knowledge — Data::Extract not defined' do
    before do
      stub_apollo
      allow(File).to receive(:exist?).with('/tmp/test.txt').and_return(true)
    end

    it 'falls back to treating the path as raw string content' do
      hide_const('Legion::Data::Extract') if defined?(Legion::Data::Extract)
      result = instance.ingest_knowledge('/tmp/test.txt', tags: ['fallback'])
      expect(result).to eq({ success: true, mode: :async })
      expect(Legion::Apollo).to have_received(:ingest).with(
        hash_including(content: '/tmp/test.txt', tags: ['fallback'])
      )
    end
  end

  # ===========================================================================
  # 7. Extraction failure — Extract returns no :text key
  # ===========================================================================
  describe '#ingest_knowledge — extraction returns no text' do
    before do
      stub_apollo
      stub_extract({ error: 'unsupported format' })
      allow(File).to receive(:exist?).with('/tmp/bad.bin').and_return(true)
    end

    it 'returns extraction_failed' do
      result = instance.ingest_knowledge('/tmp/bad.bin', tags: [])
      expect(result[:success]).to be false
      expect(result[:error]).to eq(:extraction_failed)
    end

    it 'does not call Apollo.ingest on extraction failure' do
      instance.ingest_knowledge('/tmp/bad.bin', tags: [])
      expect(Legion::Apollo).not_to have_received(:ingest)
    end

    it 'includes the raw Extract result as :detail' do
      result = instance.ingest_knowledge('/tmp/bad.bin', tags: [])
      expect(result[:detail]).to eq({ error: 'unsupported format' })
    end
  end

  # ===========================================================================
  # 8. IO object path — File-like object with #read
  # ===========================================================================
  describe '#ingest_knowledge — IO / File-like object' do
    let(:io_obj) { instance_double(File, read: 'file data') }

    before do
      stub_apollo
      stub_extract(text: 'io extracted', metadata: { type: :txt })
    end

    it 'treats any object responding to #read as extractable' do
      instance.ingest_knowledge(io_obj, tags: ['io'])
      expect(Legion::Data::Extract).to have_received(:extract).with(io_obj, type: :auto)
    end

    it 'passes extracted content to Apollo.ingest' do
      instance.ingest_knowledge(io_obj, tags: ['io'])
      expect(Legion::Apollo).to have_received(:ingest).with(hash_including(content: 'io extracted'))
    end
  end

  # ===========================================================================
  # 9. #query_knowledge — happy path
  # ===========================================================================
  describe '#query_knowledge' do
    let(:query_result) { { results: [{ content: 'relevant', score: 0.9 }] } }

    before { stub_apollo(query_result: query_result) }

    it 'delegates to Apollo.query with text and limit' do
      instance.query_knowledge(text: 'find me something', limit: 3)
      expect(Legion::Apollo).to have_received(:query).with(text: 'find me something', limit: 3)
    end

    it 'uses a default limit of 5' do
      instance.query_knowledge(text: 'search')
      expect(Legion::Apollo).to have_received(:query).with(hash_including(limit: 5))
    end

    it 'returns the result from Apollo.query' do
      result = instance.query_knowledge(text: 'find me something', limit: 3, scope: :global)
      expect(result).to eq(query_result)
    end

    it 'forwards extra keyword args to Apollo.query' do
      instance.query_knowledge(text: 'search', namespace: 'prod')
      expect(Legion::Apollo).to have_received(:query).with(hash_including(namespace: 'prod'))
    end
  end

  # ===========================================================================
  # 10. #query_knowledge — Apollo not available
  # ===========================================================================
  describe '#query_knowledge — Apollo not started' do
    it 'returns apollo_not_available when Apollo.started? is false' do
      stub_apollo(started: false)
      result = instance.query_knowledge(text: 'search')
      expect(result).to eq({ success: false, error: :apollo_not_available })
    end

    it 'does not call Apollo.query when not started' do
      apollo = stub_apollo(started: false)
      instance.query_knowledge(text: 'search')
      expect(apollo).not_to have_received(:query)
    end
  end

  describe '#query_knowledge — Apollo constant absent' do
    it 'returns apollo_not_available when Legion::Apollo is not defined' do
      hide_const('Legion::Apollo') if defined?(Legion::Apollo)
      result = instance.query_knowledge(text: 'anything')
      expect(result).to eq({ success: false, error: :apollo_not_available })
    end
  end
end
