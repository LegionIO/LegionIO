# frozen_string_literal: true

require 'spec_helper'
require 'legion/workflow/manifest'

RSpec.describe Legion::Workflow::Manifest do
  let(:valid_yaml) do
    {
      name: 'test-workflow',
      version: '0.1.0',
      description: 'A test workflow',
      requires: ['lex-codegen'],
      relationships: [
        {
          name: 'step-one',
          trigger: { extension: 'codegen', runner: 'from_gap', function: 'generate' },
          action: { extension: 'eval', runner: 'code_review', function: 'review_generated' },
          conditions: { all: [{ fact: 'success', operator: 'equal', value: true }] }
        }
      ]
    }
  end

  let(:tmpfile) do
    require 'tempfile'
    require 'json'
    f = Tempfile.new(['workflow', '.yml'])
    f.write(YAML.dump(::JSON.parse(::JSON.generate(valid_yaml))))
    f.rewind
    f
  end

  after { tmpfile.close! }

  describe '.new' do
    it 'parses a valid manifest' do
      manifest = described_class.new(path: tmpfile.path)
      expect(manifest.name).to eq('test-workflow')
      expect(manifest.version).to eq('0.1.0')
      expect(manifest.requires).to eq(['lex-codegen'])
      expect(manifest.relationships.size).to eq(1)
    end
  end

  describe '#valid?' do
    it 'returns true for valid manifest' do
      manifest = described_class.new(path: tmpfile.path)
      expect(manifest).to be_valid
    end

    context 'with missing name' do
      let(:valid_yaml) { { relationships: [{ trigger: { extension: 'a', runner: 'b', function: 'c' }, action: { extension: 'd', runner: 'e', function: 'f' } }] } }

      it 'returns false' do
        manifest = described_class.new(path: tmpfile.path)
        expect(manifest).not_to be_valid
        expect(manifest.errors).to include('name is required')
      end
    end

    context 'with empty relationships' do
      let(:valid_yaml) { { name: 'empty', relationships: [] } }

      it 'returns false' do
        manifest = described_class.new(path: tmpfile.path)
        expect(manifest).not_to be_valid
        expect(manifest.errors).to include('at least one relationship is required')
      end
    end
  end

  describe '#relationships' do
    it 'parses trigger and action refs' do
      manifest = described_class.new(path: tmpfile.path)
      rel = manifest.relationships.first
      expect(rel[:trigger][:extension]).to eq('codegen')
      expect(rel[:action][:function]).to eq('review_generated')
      expect(rel[:conditions]).to be_a(Hash)
    end
  end
end
