# frozen_string_literal: true

require 'spec_helper'
require 'legion/tenants'

RSpec.describe Legion::Tenants do
  let(:tenants_ds) { double('tenants_dataset') }
  let(:workers_ds) { double('workers_dataset') }
  let(:conn) { double('connection') }

  before do
    allow(Legion::Data).to receive(:connection).and_return(conn)
    allow(conn).to receive(:[]).with(:tenants).and_return(tenants_ds)
    allow(conn).to receive(:[]).with(:digital_workers).and_return(workers_ds)
  end

  describe '.create' do
    it 'creates a tenant record' do
      allow(tenants_ds).to receive(:where).and_return(double(first: nil))
      allow(tenants_ds).to receive(:insert)
      result = described_class.create(tenant_id: 'askid-001', name: 'Test Tenant')
      expect(result[:created]).to be true
    end

    it 'rejects duplicate tenant' do
      allow(tenants_ds).to receive(:where).and_return(double(first: { tenant_id: 'askid-001' }))
      result = described_class.create(tenant_id: 'askid-001')
      expect(result[:error]).to eq('tenant_exists')
    end
  end

  describe '.find' do
    it 'returns tenant by id' do
      allow(tenants_ds).to receive(:where).with(tenant_id: 'askid-001').and_return(double(first: { tenant_id: 'askid-001' }))
      expect(described_class.find('askid-001')).not_to be_nil
    end
  end

  describe '.check_quota' do
    it 'allows when under limit' do
      allow(tenants_ds).to receive(:where).and_return(double(first: { max_workers: 5 }))
      allow(workers_ds).to receive(:where).and_return(double(count: 2))
      result = described_class.check_quota(tenant_id: 'askid-001', resource: :workers)
      expect(result[:allowed]).to be true
    end

    it 'blocks when at limit' do
      allow(tenants_ds).to receive(:where).and_return(double(first: { max_workers: 5 }))
      allow(workers_ds).to receive(:where).and_return(double(count: 5))
      result = described_class.check_quota(tenant_id: 'askid-001', resource: :workers)
      expect(result[:allowed]).to be false
    end
  end
end
