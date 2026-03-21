# frozen_string_literal: true

require 'spec_helper'
require 'legion/phi'

RSpec.describe Legion::Phi do
  # ---------------------------------------------------------------------------
  # PHI_TAG constant
  # ---------------------------------------------------------------------------
  describe 'PHI_TAG' do
    it 'is :phi' do
      expect(described_class::PHI_TAG).to eq(:phi)
    end
  end

  # ---------------------------------------------------------------------------
  # .tag
  # ---------------------------------------------------------------------------
  describe '.tag' do
    let(:data) { { ssn: '123-45-6789', name: 'Alice' } }

    it 'adds __phi_fields to the hash' do
      result = described_class.tag(data, fields: [:ssn])
      expect(result[:__phi_fields]).to eq([:ssn])
    end

    it 'returns a new hash without modifying the original' do
      result = described_class.tag(data, fields: [:ssn])
      expect(data).not_to have_key(:__phi_fields)
      expect(result).to have_key(:__phi_fields)
    end

    it 'accepts string field names and converts to symbols' do
      result = described_class.tag(data, fields: ['ssn'])
      expect(result[:__phi_fields]).to eq([:ssn])
    end

    it 'merges with existing __phi_fields' do
      already = described_class.tag(data, fields: [:ssn])
      double_tagged = described_class.tag(already, fields: [:name])
      expect(double_tagged[:__phi_fields]).to contain_exactly(:ssn, :name)
    end

    it 'deduplicates phi fields' do
      result = described_class.tag(data, fields: %i[ssn ssn name])
      expect(result[:__phi_fields]).to eq(%i[ssn name])
    end

    it 'raises ArgumentError when data is not a Hash' do
      expect { described_class.tag('not a hash', fields: [:ssn]) }.to raise_error(ArgumentError, /Hash/)
    end

    it 'raises ArgumentError when fields is not an Array' do
      expect { described_class.tag(data, fields: :ssn) }.to raise_error(ArgumentError, /Array/)
    end
  end

  # ---------------------------------------------------------------------------
  # .tagged?
  # ---------------------------------------------------------------------------
  describe '.tagged?' do
    it 'returns true when __phi_fields key is present' do
      tagged = described_class.tag({ ssn: '123' }, fields: [:ssn])
      expect(described_class.tagged?(tagged)).to be true
    end

    it 'returns false when __phi_fields key is absent' do
      expect(described_class.tagged?({ ssn: '123' })).to be false
    end

    it 'returns false when data is not a Hash' do
      expect(described_class.tagged?('string')).to be false
    end

    it 'returns false for an empty hash' do
      expect(described_class.tagged?({})).to be false
    end

    it 'returns false for nil' do
      expect(described_class.tagged?(nil)).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # .phi_fields
  # ---------------------------------------------------------------------------
  describe '.phi_fields' do
    it 'returns the list of tagged field names' do
      tagged = described_class.tag({ ssn: '1', mrn: '2' }, fields: %i[ssn mrn])
      expect(described_class.phi_fields(tagged)).to contain_exactly(:ssn, :mrn)
    end

    it 'returns an empty array when not tagged' do
      expect(described_class.phi_fields({ ssn: '1' })).to eq([])
    end

    it 'returns an empty array for a non-Hash' do
      expect(described_class.phi_fields(42)).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # .redact
  # ---------------------------------------------------------------------------
  describe '.redact' do
    let(:tagged_data) { described_class.tag({ ssn: '123-45-6789', name: 'Alice', age: 30 }, fields: %i[ssn name]) }

    it 'replaces tagged PHI fields with [REDACTED]' do
      result = described_class.redact(tagged_data)
      expect(result[:ssn]).to eq('[REDACTED]')
      expect(result[:name]).to eq('[REDACTED]')
    end

    it 'preserves non-PHI fields' do
      result = described_class.redact(tagged_data)
      expect(result[:age]).to eq(30)
    end

    it 'returns a copy without modifying the original' do
      original_ssn = tagged_data[:ssn]
      described_class.redact(tagged_data)
      expect(tagged_data[:ssn]).to eq(original_ssn)
    end

    it 'returns the data unchanged if not a Hash' do
      expect(described_class.redact('not a hash')).to eq('not a hash')
    end

    it 'redacts auto-detected PHI fields even without explicit tagging' do
      data = { ssn: '123-45-6789', safe_field: 'safe' }
      result = described_class.redact(data)
      expect(result[:ssn]).to eq('[REDACTED]')
      expect(result[:safe_field]).to eq('safe')
    end
  end

  # ---------------------------------------------------------------------------
  # .auto_detect_fields
  # ---------------------------------------------------------------------------
  describe '.auto_detect_fields' do
    it 'detects ssn field' do
      data = { ssn: '123-45-6789' }
      expect(described_class.auto_detect_fields(data)).to include(:ssn)
    end

    it 'detects mrn field' do
      data = { mrn: 'M123456' }
      expect(described_class.auto_detect_fields(data)).to include(:mrn)
    end

    it 'detects dob field' do
      data = { dob: '1990-01-01' }
      expect(described_class.auto_detect_fields(data)).to include(:dob)
    end

    it 'does not flag unrelated fields' do
      data = { task_id: 1, status: 'pending', metadata: {} }
      expect(described_class.auto_detect_fields(data)).to be_empty
    end

    it 'returns an empty array for a non-Hash' do
      expect(described_class.auto_detect_fields('string')).to eq([])
    end

    it 'handles string keys' do
      data = { 'ssn' => '123' }
      expect(described_class.auto_detect_fields(data)).to include('ssn')
    end
  end

  # ---------------------------------------------------------------------------
  # .erase
  # ---------------------------------------------------------------------------
  describe '.erase' do
    let(:tagged_data) { described_class.tag({ ssn: '123-45-6789', name: 'Alice', age: 30 }, fields: %i[ssn name]) }

    it 'replaces PHI fields with erasure markers' do
      result = described_class.erase(tagged_data, key_id: 'test-key-001')
      expect(result[:ssn]).to include('[ERASED]')
      expect(result[:name]).to include('[ERASED]')
    end

    it 'preserves non-PHI fields' do
      result = described_class.erase(tagged_data, key_id: 'test-key-001')
      expect(result[:age]).to eq(30)
    end

    it 'returns data unchanged when not a Hash' do
      expect(described_class.erase('not a hash', key_id: 'k1')).to eq('not a hash')
    end
  end
end
