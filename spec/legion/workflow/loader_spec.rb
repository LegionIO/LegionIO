# frozen_string_literal: true

require 'spec_helper'
require 'legion/workflow/manifest'
require 'legion/workflow/loader'

module Legion
  module Data
    module Model
      Extension = Class.new unless const_defined?(:Extension, false)
      Runner = Class.new unless const_defined?(:Runner, false)
      Function = Class.new unless const_defined?(:Function, false)
      Relationship = Class.new unless const_defined?(:Relationship, false)
      Chain = Class.new unless const_defined?(:Chain, false)
    end
  end
end

RSpec.describe Legion::Workflow::Loader do
  subject(:loader) { described_class.new }

  before do
    allow(Gem::Specification).to receive(:find_all_by_name).and_return([double])
  end

  describe '#install' do
    let(:manifest) do
      instance_double(
        Legion::Workflow::Manifest,
        valid?: true,
        name: 'test-workflow',
        requires: ['lex-codegen'],
        relationships: [
          {
            name: 'step-one',
            trigger: { extension: 'codegen', runner: 'from_gap', function: 'generate' },
            action: { extension: 'eval', runner: 'code_review', function: 'review_generated' },
            conditions: { all: [{ fact: 'success', operator: 'equal', value: true }] },
            transformation: nil,
            delay: 0,
            allow_new_chains: false
          }
        ]
      )
    end

    context 'when manifest is invalid' do
      let(:manifest) { instance_double(Legion::Workflow::Manifest, valid?: false, errors: ['name is required']) }

      it 'returns errors' do
        result = loader.install(manifest)
        expect(result[:success]).to be false
        expect(result[:errors]).to include('name is required')
      end
    end

    context 'when gems are missing' do
      before { allow(Gem::Specification).to receive(:find_all_by_name).with('lex-codegen').and_return([]) }

      it 'returns missing_gems error' do
        result = loader.install(manifest)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:missing_gems)
      end
    end

    context 'when trigger function not found' do
      before do
        allow(Legion::Data::Model::Extension).to receive(:where).and_return(double(first: nil))
        allow(Legion::Data::Model::Chain).to receive(:where).and_return(double(first: nil))
        allow(Legion::Data::Model::Chain).to receive(:insert).and_return(1)
      end

      it 'returns trigger_not_found error' do
        result = loader.install(manifest)
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:trigger_not_found)
      end
    end

    context 'when all functions resolve' do
      let(:ext_codegen) { double(values: { id: 1 }) }
      let(:ext_eval) { double(values: { id: 2 }) }
      let(:runner_from_gap) { double(values: { id: 10 }) }
      let(:runner_code_review) { double(values: { id: 20 }) }
      let(:func_generate) { double(values: { id: 100 }) }
      let(:func_review) { double(values: { id: 200 }) }

      before do
        allow(Legion::Data::Model::Chain).to receive(:where).and_return(double(first: nil))
        allow(Legion::Data::Model::Chain).to receive(:insert).and_return(5)

        allow(Legion::Data::Model::Extension).to receive(:where).with(name: 'codegen').and_return(double(first: ext_codegen))
        allow(Legion::Data::Model::Extension).to receive(:where).with(name: 'eval').and_return(double(first: ext_eval))

        allow(Legion::Data::Model::Runner).to receive(:where).with(extension_id: 1, name: 'from_gap').and_return(double(first: runner_from_gap))
        allow(Legion::Data::Model::Runner).to receive(:where).with(extension_id: 2, name: 'code_review').and_return(double(first: runner_code_review))

        allow(Legion::Data::Model::Function).to receive(:where).with(runner_id: 10, name: 'generate').and_return(double(first: func_generate))
        allow(Legion::Data::Model::Function).to receive(:where).with(runner_id: 20, name: 'review_generated').and_return(double(first: func_review))

        allow(Legion::Data::Model::Relationship).to receive(:insert).and_return(42)
      end

      it 'creates chain and relationships' do
        result = loader.install(manifest)
        expect(result[:success]).to be true
        expect(result[:chain_id]).to eq(5)
        expect(result[:relationship_ids]).to eq([42])
      end

      it 'sets allow_new_chains on first relationship' do
        expect(Legion::Data::Model::Relationship).to receive(:insert).with(
          hash_including(allow_new_chains: true, chain_id: 5)
        ).and_return(42)
        loader.install(manifest)
      end
    end
  end

  describe '#uninstall' do
    context 'when workflow not found' do
      before { allow(Legion::Data::Model::Chain).to receive(:where).with(name: 'missing').and_return(double(first: nil)) }

      it 'returns not_found' do
        result = loader.uninstall('missing')
        expect(result[:success]).to be false
        expect(result[:error]).to eq(:not_found)
      end
    end

    context 'when workflow exists' do
      let(:chain) { double(values: { id: 5 }, delete: true) }

      before do
        allow(Legion::Data::Model::Chain).to receive(:where).with(name: 'test').and_return(double(first: chain))
        allow(Legion::Data::Model::Relationship).to receive(:where).with(chain_id: 5).and_return(double(delete: 3))
      end

      it 'deletes relationships and chain' do
        result = loader.uninstall('test')
        expect(result[:success]).to be true
        expect(result[:deleted_relationships]).to eq(3)
      end
    end
  end

  describe '#list' do
    before do
      allow(Legion::Data::Model::Chain).to receive(:all).and_return([
        double(values: { id: 1, name: 'wf-one' }),
        double(values: { id: 2, name: 'wf-two' })
      ])
      allow(Legion::Data::Model::Relationship).to receive(:where).and_return(double(count: 3))
    end

    it 'returns workflow summaries' do
      result = loader.list
      expect(result.size).to eq(2)
      expect(result.first[:name]).to eq('wf-one')
      expect(result.first[:relationships]).to eq(3)
    end
  end
end
