# frozen_string_literal: true

RSpec.describe Legion::Extensions::Reconciliation::Runners::DriftChecker do
  subject(:checker) { Object.new.extend(described_class) }

  let(:resource)  { 'test-service' }
  let(:expected)  { { status: 'running', version: '1.2.0', replicas: 3 } }

  describe '#check' do
    context 'when expected and actual states match' do
      it 'returns drifted: false' do
        result = checker.check(resource: resource, expected: expected, actual: expected.dup)
        expect(result[:drifted]).to be false
      end

      it 'returns empty drift_entries' do
        result = checker.check(resource: resource, expected: expected, actual: expected.dup)
        expect(result[:drift_entries]).to be_empty
      end

      it 'returns zero total in summary' do
        result = checker.check(resource: resource, expected: expected, actual: expected.dup)
        expect(result.dig(:summary, :total)).to eq(0)
      end
    end

    context 'when actual state differs from expected' do
      let(:actual) { { status: 'stopped', version: '1.2.0', replicas: 1 } }

      before do
        allow(Legion::Extensions::Reconciliation::DriftLog).to receive(:record).and_return(
          { drift_id: 'test-uuid', resource: resource, status: 'open' }
        )
      end

      it 'returns drifted: true' do
        result = checker.check(resource: resource, expected: expected, actual: actual)
        expect(result[:drifted]).to be true
      end

      it 'includes the differing paths in summary' do
        result = checker.check(resource: resource, expected: expected, actual: actual)
        expect(result.dig(:summary, :paths)).to include('status', 'replicas')
      end

      it 'records a drift log entry' do
        expect(Legion::Extensions::Reconciliation::DriftLog).to receive(:record)
          .with(hash_including(resource: resource))
          .and_return({ drift_id: 'test-uuid' })
        checker.check(resource: resource, expected: expected, actual: actual)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Legion::Extensions::Reconciliation::DriftLog).to receive(:record).and_raise(StandardError, 'db error')
      end

      it 'returns drifted: false with error key' do
        actual = { status: 'stopped' }
        result = checker.check(resource: resource, expected: expected, actual: actual)
        expect(result[:error]).not_to be_nil
      end
    end
  end

  describe '#check_all' do
    let(:resources) do
      [
        { resource: 'svc-a', expected: { status: 'ok' }, actual: { status: 'ok' } },
        { resource: 'svc-b', expected: { status: 'ok' }, actual: { status: 'fail' } }
      ]
    end

    before do
      allow(Legion::Extensions::Reconciliation::DriftLog).to receive(:record).and_return(
        { drift_id: 'uuid-b', resource: 'svc-b', status: 'open' }
      )
    end

    it 'returns the correct checked count' do
      result = checker.check_all(resources: resources)
      expect(result[:checked]).to eq(2)
    end

    it 'returns the correct drifted count' do
      result = checker.check_all(resources: resources)
      expect(result[:drifted]).to eq(1)
    end

    it 'returns individual results' do
      result = checker.check_all(resources: resources)
      expect(result[:results].size).to eq(2)
    end
  end

  describe '#drift_summary' do
    before do
      allow(Legion::Extensions::Reconciliation::DriftLog).to receive(:summary)
        .and_return({ open: 3, resolved: 10, by_severity: { 'medium' => { open: 3, resolved: 10 } } })
    end

    it 'delegates to DriftLog.summary' do
      expect(checker.drift_summary[:open]).to eq(3)
    end
  end
end
