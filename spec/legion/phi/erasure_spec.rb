# frozen_string_literal: true

require 'spec_helper'
require 'legion/phi/erasure'

RSpec.describe Legion::Phi::Erasure do
  before { described_class.reset_erasure_log! }

  # ---------------------------------------------------------------------------
  # .erase_record
  # ---------------------------------------------------------------------------
  describe '.erase_record' do
    let(:record) { { ssn: '123-45-6789', name: 'Alice', age: 30 } }

    it 'replaces PHI fields with erasure markers' do
      result = described_class.erase_record(record: record, phi_fields: %i[ssn name])
      expect(result[:ssn]).to include('[ERASED]')
      expect(result[:name]).to include('[ERASED]')
    end

    it 'preserves non-PHI fields' do
      result = described_class.erase_record(record: record, phi_fields: %i[ssn])
      expect(result[:age]).to eq(30)
    end

    it 'does not modify the original record' do
      original_ssn = record[:ssn]
      described_class.erase_record(record: record, phi_fields: %i[ssn])
      expect(record[:ssn]).to eq(original_ssn)
    end

    it 'returns the record unchanged when phi_fields is empty' do
      result = described_class.erase_record(record: record, phi_fields: [])
      expect(result[:ssn]).to eq('123-45-6789')
    end

    it 'returns the record unchanged when phi_fields is nil' do
      result = described_class.erase_record(record: record, phi_fields: nil)
      expect(result[:ssn]).to eq('123-45-6789')
    end

    it 'returns the record unchanged when record is not a Hash' do
      expect(described_class.erase_record(record: 'not-a-hash', phi_fields: %i[ssn])).to eq('not-a-hash')
    end

    it 'includes key_id metadata in erasure marker' do
      result = described_class.erase_record(record: record, phi_fields: %i[ssn], key_id: 'key-abc')
      expect(result[:ssn]).to include('key_id=key-abc')
    end

    it 'skips fields not present in the record' do
      result = described_class.erase_record(record: record, phi_fields: %i[ssn nonexistent_field])
      expect(result).not_to have_key(:nonexistent_field)
      expect(result[:ssn]).to include('[ERASED]')
    end

    it 'handles nil field values gracefully' do
      record_with_nil = { ssn: nil, age: 30 }
      result = described_class.erase_record(record: record_with_nil, phi_fields: %i[ssn])
      expect(result[:ssn]).to eq('[ERASED]')
    end
  end

  # ---------------------------------------------------------------------------
  # .erase_for_subject
  # ---------------------------------------------------------------------------
  describe '.erase_for_subject' do
    it 'returns an erasure audit entry' do
      result = described_class.erase_for_subject(subject_id: 'patient-99')
      expect(result[:subject_id]).to eq('patient-99')
      expect(result[:status]).to eq('completed')
      expect(result[:method]).to eq('cryptographic_erasure')
    end

    it 'includes a key_id in the audit entry' do
      result = described_class.erase_for_subject(subject_id: 'patient-99')
      expect(result[:key_id]).not_to be_nil
      expect(result[:key_id]).not_to be_empty
    end

    it 'includes an erased_at timestamp' do
      result = described_class.erase_for_subject(subject_id: 'patient-99')
      expect(result[:erased_at]).to match(/^\d{4}-\d{2}-\d{2}T/)
    end

    it 'appends to the erasure log' do
      described_class.erase_for_subject(subject_id: 'patient-100')
      expect(described_class.erasure_log.size).to eq(1)
      expect(described_class.erasure_log.first[:subject_id]).to eq('patient-100')
    end

    context 'when Legion::Audit is defined' do
      before do
        stub_const('Legion::Audit', Module.new)
        allow(Legion::Audit).to receive(:record)
      end

      it 'calls Legion::Audit.record with phi_erasure event_type' do
        described_class.erase_for_subject(subject_id: 'patient-101')
        expect(Legion::Audit).to have_received(:record).with(
          hash_including(event_type: 'phi_erasure', principal_id: 'patient-101')
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .erasure_log
  # ---------------------------------------------------------------------------
  describe '.erasure_log' do
    it 'returns an empty array initially' do
      expect(described_class.erasure_log).to eq([])
    end

    it 'returns a frozen copy (not the live array)' do
      described_class.erase_for_subject(subject_id: 's-1')
      log = described_class.erasure_log
      expect(log).to be_frozen
    end

    it 'accumulates entries from multiple erases' do
      described_class.erase_for_subject(subject_id: 's-1')
      described_class.erase_for_subject(subject_id: 's-2')
      expect(described_class.erasure_log.size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # .reset_erasure_log!
  # ---------------------------------------------------------------------------
  describe '.reset_erasure_log!' do
    it 'clears the log' do
      described_class.erase_for_subject(subject_id: 's-x')
      described_class.reset_erasure_log!
      expect(described_class.erasure_log).to eq([])
    end
  end
end
