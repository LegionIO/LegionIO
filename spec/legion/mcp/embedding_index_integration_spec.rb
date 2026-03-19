# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe 'EmbeddingIndex integration' do
  before(:each) do
    Legion::MCP::EmbeddingIndex.reset!
    Legion::MCP::ContextCompiler.reset!
  end

  after(:each) do
    Legion::MCP::EmbeddingIndex.reset!
  end

  describe 'Server.populate_embedding_index' do
    it 'responds to populate_embedding_index' do
      expect(Legion::MCP::Server).to respond_to(:populate_embedding_index)
    end

    it 'populates the index from ContextCompiler tool_index' do
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::Server.populate_embedding_index(embedder: fake_embedder)
      expect(Legion::MCP::EmbeddingIndex.size).to eq(Legion::MCP::ContextCompiler.tool_index.size)
    end

    it 'leaves index empty when embedder is nil' do
      Legion::MCP::Server.populate_embedding_index(embedder: nil)
      expect(Legion::MCP::EmbeddingIndex.size).to eq(0)
    end

    it 'stores vectors for each tool' do
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::Server.populate_embedding_index(embedder: fake_embedder)
      entry = Legion::MCP::EmbeddingIndex.entry('legion.run_task')
      expect(entry).not_to be_nil
      expect(entry[:vector]).to be_an(Array)
    end

    it 'populates all tools from TOOL_CLASSES' do
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::Server.populate_embedding_index(embedder: fake_embedder)
      expect(Legion::MCP::EmbeddingIndex.size).to eq(Legion::MCP::Server::TOOL_CLASSES.size)
    end
  end

  describe 'ContextCompiler semantic integration' do
    it 'uses embeddings for match_tools when index is populated' do
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::Server.populate_embedding_index(embedder: fake_embedder)

      results = Legion::MCP::ContextCompiler.match_tools('execute a function', limit: 5)
      expect(results).not_to be_empty
      expect(results.first[:score]).to be > 0
    end

    it 'falls back to keyword matching when index is empty' do
      results = Legion::MCP::ContextCompiler.match_tools('run task', limit: 5)
      expect(results).not_to be_empty
    end

    it 'returns results with blended scores when index populated' do
      fake_embedder = ->(text) { ('a'..'z').map { |c| text.downcase.count(c).to_f } }
      Legion::MCP::Server.populate_embedding_index(embedder: fake_embedder)

      results = Legion::MCP::ContextCompiler.match_tools('list all extensions', limit: 10)
      expect(results.first[:score]).to be_a(Float)
    end
  end
end
