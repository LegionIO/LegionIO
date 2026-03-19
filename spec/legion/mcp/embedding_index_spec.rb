# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/embedding_index'

RSpec.describe Legion::MCP::EmbeddingIndex do
  let(:fake_embedder) do
    ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
  end

  let(:tool_data) do
    [
      { name: 'legion.run_task',      description: 'Execute a Legion task using dot notation.', params: %w[task params] },
      { name: 'legion.list_tasks',    description: 'List all tasks with optional filtering.',   params: %w[limit]       },
      { name: 'legion.get_status',    description: 'Get Legion service health status.', params: [] }
    ]
  end

  before(:each) do
    described_class.reset!
  end

  # ---------------------------------------------------------------------------
  # build_from_tool_data
  # ---------------------------------------------------------------------------

  describe '.build_from_tool_data' do
    it 'populates the index with correct size' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      expect(described_class.size).to eq(3)
    end

    it 'builds correct composite text that includes name' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      entry = described_class.entry('legion.run_task')
      expect(entry[:composite_text]).to include('legion.run_task')
    end

    it 'builds correct composite text that includes description' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      entry = described_class.entry('legion.run_task')
      expect(entry[:composite_text]).to include('Execute a Legion task using dot notation.')
    end

    it 'builds correct composite text that includes params' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      entry = described_class.entry('legion.run_task')
      expect(entry[:composite_text]).to include('task')
      expect(entry[:composite_text]).to include('params')
    end

    it 'omits Params section from composite when params is empty' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      entry = described_class.entry('legion.get_status')
      expect(entry[:composite_text]).not_to include('Params:')
    end

    it 'stores embedding vectors in index entries' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      entry = described_class.entry('legion.run_task')
      expect(entry[:vector]).to be_an(Array)
      expect(entry[:vector]).not_to be_empty
    end

    it 'skips entries when embedder returns nil' do
      nil_embedder = ->(_text) {}
      described_class.build_from_tool_data(tool_data, embedder: nil_embedder)
      expect(described_class.size).to eq(0)
    end

    it 'skips entries when embedder returns an empty array' do
      empty_embedder = ->(_text) { [] }
      described_class.build_from_tool_data(tool_data, embedder: empty_embedder)
      expect(described_class.size).to eq(0)
    end

    it 'stores built_at timestamp on each entry' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      entry = described_class.entry('legion.list_tasks')
      expect(entry[:built_at]).to be_a(Time)
    end
  end

  # ---------------------------------------------------------------------------
  # semantic_match
  # ---------------------------------------------------------------------------

  describe '.semantic_match' do
    before do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
    end

    it 'returns scored matches sorted by score descending' do
      results = described_class.semantic_match('list all tasks', embedder: fake_embedder)
      scores = results.map { |r| r[:score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it 'returns hashes with :name and :score keys' do
      results = described_class.semantic_match('run task', embedder: fake_embedder)
      results.each do |r|
        expect(r).to have_key(:name)
        expect(r).to have_key(:score)
      end
    end

    it 'respects the limit parameter' do
      results = described_class.semantic_match('task', embedder: fake_embedder, limit: 2)
      expect(results.length).to be <= 2
    end

    it 'returns at most 5 results by default' do
      large_data = Array.new(10) do |i|
        { name: "legion.tool_#{i}", description: "Tool number #{i} does something.", params: [] }
      end
      described_class.reset!
      described_class.build_from_tool_data(large_data, embedder: fake_embedder)
      results = described_class.semantic_match('tool does something', embedder: fake_embedder)
      expect(results.length).to be <= 5
    end

    it 'returns empty array when index is empty' do
      described_class.reset!
      results = described_class.semantic_match('run task', embedder: fake_embedder)
      expect(results).to eq([])
    end

    it 'returns empty array when embedder returns nil' do
      nil_embedder = ->(_text) {}
      results = described_class.semantic_match('run task', embedder: nil_embedder)
      expect(results).to eq([])
    end

    it 'returns empty array when embedder is nil' do
      results = described_class.semantic_match('run task', embedder: nil)
      expect(results).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # cosine_similarity
  # ---------------------------------------------------------------------------

  describe '.cosine_similarity' do
    it 'returns 1.0 for identical vectors' do
      vec = [1.0, 2.0, 3.0]
      expect(described_class.cosine_similarity(vec, vec)).to be_within(1e-10).of(1.0)
    end

    it 'returns 0.0 for orthogonal vectors' do
      vec_a = [1.0, 0.0, 0.0]
      vec_b = [0.0, 1.0, 0.0]
      expect(described_class.cosine_similarity(vec_a, vec_b)).to be_within(1e-10).of(0.0)
    end

    it 'returns 0.0 for a zero vector (vec_a)' do
      vec_a = [0.0, 0.0, 0.0]
      vec_b = [1.0, 2.0, 3.0]
      expect(described_class.cosine_similarity(vec_a, vec_b)).to eq(0.0)
    end

    it 'returns 0.0 for a zero vector (vec_b)' do
      vec_a = [1.0, 2.0, 3.0]
      vec_b = [0.0, 0.0, 0.0]
      expect(described_class.cosine_similarity(vec_a, vec_b)).to eq(0.0)
    end

    it 'returns a value between -1 and 1' do
      vec_a = [3.0, 1.0, 4.0, 1.0, 5.0]
      vec_b = [2.0, 7.0, 1.0, 8.0, 2.0]
      result = described_class.cosine_similarity(vec_a, vec_b)
      expect(result).to be >= -1.0
      expect(result).to be <= 1.0
    end

    it 'returns -1.0 for opposite vectors' do
      vec_a = [1.0, 0.0]
      vec_b = [-1.0, 0.0]
      expect(described_class.cosine_similarity(vec_a, vec_b)).to be_within(1e-10).of(-1.0)
    end
  end

  # ---------------------------------------------------------------------------
  # size, populated?, coverage
  # ---------------------------------------------------------------------------

  describe '.size' do
    it 'returns 0 when index is empty' do
      expect(described_class.size).to eq(0)
    end

    it 'returns correct count after build' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      expect(described_class.size).to eq(3)
    end
  end

  describe '.populated?' do
    it 'returns false when index is empty' do
      expect(described_class.populated?).to be false
    end

    it 'returns true after building with valid tool data' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      expect(described_class.populated?).to be true
    end
  end

  describe '.coverage' do
    it 'returns 0.0 when index is empty' do
      expect(described_class.coverage).to eq(0.0)
    end

    it 'returns 1.0 when all entries have vectors' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      expect(described_class.coverage).to eq(1.0)
    end

    it 'returns a fractional ratio when only some entries have vectors' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      # Inject an entry without a vector to simulate partial coverage
      described_class.mutex.synchronize do
        described_class.index['legion.no_vector'] = {
          name:           'legion.no_vector',
          composite_text: 'no vector tool',
          vector:         nil,
          built_at:       Time.now
        }
      end
      # 3 with vectors out of 4 total
      expect(described_class.coverage).to be_within(0.01).of(0.75)
    end
  end

  # ---------------------------------------------------------------------------
  # reset!
  # ---------------------------------------------------------------------------

  describe '.reset!' do
    it 'clears the index' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      described_class.reset!
      expect(described_class.size).to eq(0)
    end

    it 'makes populated? return false after clearing' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      described_class.reset!
      expect(described_class.populated?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # entry
  # ---------------------------------------------------------------------------

  describe '.entry' do
    it 'returns nil for an unknown tool name' do
      expect(described_class.entry('legion.nonexistent')).to be_nil
    end

    it 'returns the correct entry hash for a known tool' do
      described_class.build_from_tool_data(tool_data, embedder: fake_embedder)
      result = described_class.entry('legion.run_task')
      expect(result).to be_a(Hash)
      expect(result[:name]).to eq('legion.run_task')
    end
  end

  # ---------------------------------------------------------------------------
  # default_embedder
  # ---------------------------------------------------------------------------

  describe '.default_embedder' do
    it 'returns nil when Legion::LLM is not defined' do
      hide_const('Legion::LLM') if defined?(Legion::LLM)
      expect(described_class.default_embedder).to be_nil
    end

    it 'returns nil when Legion::LLM does not respond to started?' do
      stub_const('Legion::LLM', Module.new)
      expect(described_class.default_embedder).to be_nil
    end

    it 'returns nil when Legion::LLM.started? is false' do
      llm = Module.new do
        def self.started?
          false
        end
      end
      stub_const('Legion::LLM', llm)
      expect(described_class.default_embedder).to be_nil
    end

    it 'returns a callable lambda when Legion::LLM is started' do
      llm = Module.new do
        def self.started?
          true
        end

        def self.embed(_text)
          { vector: [0.1, 0.2, 0.3] }
        end
      end
      stub_const('Legion::LLM', llm)
      embedder = described_class.default_embedder
      expect(embedder).to respond_to(:call)
      expect(embedder.call('hello')).to eq([0.1, 0.2, 0.3])
    end
  end

  # ---------------------------------------------------------------------------
  # safe_embed
  # ---------------------------------------------------------------------------

  describe '.safe_embed' do
    it 'returns nil when embedder is nil' do
      expect(described_class.safe_embed('hello', nil)).to be_nil
    end

    it 'returns the vector array on success' do
      result = described_class.safe_embed('hello', fake_embedder)
      expect(result).to be_an(Array)
      expect(result.length).to eq(26)
    end

    it 'rescues StandardError and returns nil' do
      exploding_embedder = ->(_text) { raise StandardError, 'embed failed' }
      expect(described_class.safe_embed('hello', exploding_embedder)).to be_nil
    end

    it 'returns nil when embedder returns a non-Array' do
      bad_embedder = ->(_text) { 'not an array' }
      expect(described_class.safe_embed('hello', bad_embedder)).to be_nil
    end

    it 'returns nil when embedder returns an empty array' do
      empty_embedder = ->(_text) { [] }
      expect(described_class.safe_embed('hello', empty_embedder)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # build_composite
  # ---------------------------------------------------------------------------

  describe '.build_composite' do
    it 'joins name, separator, and description' do
      result = described_class.build_composite('legion.test', 'A test tool.', [])
      expect(result).to eq('legion.test -- A test tool.')
    end

    it 'appends params line when params are present' do
      result = described_class.build_composite('legion.test', 'A test tool.', %w[foo bar])
      expect(result).to include('Params: foo, bar')
    end

    it 'omits params line when params are empty' do
      result = described_class.build_composite('legion.test', 'A test tool.', [])
      expect(result).not_to include('Params:')
    end
  end
end
