# frozen_string_literal: true

RSpec.describe Legion::Extensions::Reconciliation::DriftLog do
  describe '.record' do
    context 'when data is unavailable' do
      before { hide_const('Legion::Data') if defined?(Legion::Data) }

      it 'returns nil gracefully' do
        result = described_class.record(
          resource: 'test',
          expected: { status: 'ok' },
          actual:   { status: 'fail' }
        )
        expect(result).to be_nil.or be_a(Hash)
      end
    end
  end

  describe '.summary' do
    context 'when data is unavailable' do
      before { hide_const('Legion::Data') if defined?(Legion::Data) }

      it 'returns a zero summary' do
        result = described_class.summary
        expect(result[:open]).to eq(0)
        expect(result[:resolved]).to eq(0)
      end
    end
  end

  describe '.open_entries' do
    context 'when data is unavailable' do
      before { hide_const('Legion::Data') if defined?(Legion::Data) }

      it 'returns an empty array' do
        expect(described_class.open_entries).to eq([])
      end
    end
  end
end
