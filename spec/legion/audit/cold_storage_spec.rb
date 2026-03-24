# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'legion/audit/cold_storage'

RSpec.describe Legion::Audit::ColdStorage do
  let(:tmpdir) { Dir.mktmpdir('cold_storage_spec') }

  before do
    allow(Legion::Settings).to receive(:[]).and_call_original
    allow(Legion::Settings).to receive(:[]).with(:audit) do
      { retention: { cold_backend: 'local', cold_storage: tmpdir } }
    end
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe '.backend' do
    it 'returns :local by default' do
      expect(described_class.backend).to eq :local
    end

    it 'returns :s3 when configured' do
      allow(Legion::Settings).to receive(:[]).with(:audit) do
        { retention: { cold_backend: 's3' } }
      end
      expect(described_class.backend).to eq :s3
    end
  end

  describe '.upload / .download with :local backend' do
    let(:test_data) { 'compressed-content-here' }
    let(:test_path) { ::File.join(tmpdir, 'test_archive.jsonl.gz') }

    it 'writes data to the given path' do
      result = described_class.upload(data: test_data, path: test_path)
      expect(result[:path]).to eq test_path
      expect(::File.exist?(test_path)).to be true
    end

    it 'reads back the same data' do
      described_class.upload(data: test_data, path: test_path)
      expect(described_class.download(path: test_path)).to eq test_data
    end

    it 'creates intermediate directories' do
      deep_path = ::File.join(tmpdir, 'a', 'b', 'c', 'archive.gz')
      described_class.upload(data: test_data, path: deep_path)
      expect(::File.exist?(deep_path)).to be true
    end
  end

  describe '.upload with :s3 backend when Aws::S3::Client unavailable' do
    before do
      allow(Legion::Settings).to receive(:[]).with(:audit) do
        { retention: { cold_backend: 's3' } }
      end
      hide_const('Aws::S3::Client') if defined?(Aws::S3::Client)
    end

    it 'raises a descriptive error' do
      expect { described_class.upload(data: 'x', path: 'bucket/key') }
        .to raise_error(Legion::Audit::ColdStorage::BackendNotAvailableError, /aws-sdk-s3/)
    end
  end
end
