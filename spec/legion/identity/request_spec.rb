# frozen_string_literal: true

require 'spec_helper'
require 'legion/identity/request'

RSpec.describe Legion::Identity::Request do
  let(:principal_id)   { 'user-abc-123' }
  let(:canonical_name) { 'jane-doe' }
  let(:kind)           { :human }
  let(:groups)         { %w[admins readers] }
  let(:source)         { :kerberos }
  let(:metadata)       { { department: 'engineering' } }

  let(:request) do
    described_class.new(
      principal_id:   principal_id,
      canonical_name: canonical_name,
      kind:           kind,
      groups:         groups,
      source:         source,
      metadata:       metadata
    )
  end

  describe '#initialize' do
    it 'sets principal_id' do
      expect(request.principal_id).to eq(principal_id)
    end

    it 'sets canonical_name' do
      expect(request.canonical_name).to eq(canonical_name)
    end

    it 'sets kind' do
      expect(request.kind).to eq(kind)
    end

    it 'sets groups' do
      expect(request.groups).to eq(groups)
    end

    it 'sets source' do
      expect(request.source).to eq(source)
    end

    it 'sets metadata' do
      expect(request.metadata).to eq(metadata)
    end

    it 'defaults groups to an empty array' do
      req = described_class.new(principal_id: principal_id, canonical_name: canonical_name, kind: kind)
      expect(req.groups).to eq([])
    end

    it 'defaults source to nil' do
      req = described_class.new(principal_id: principal_id, canonical_name: canonical_name, kind: kind)
      expect(req.source).to be_nil
    end

    it 'freezes groups' do
      expect(request.groups).to be_frozen
    end

    it 'freezes the object after creation' do
      expect(request).to be_frozen
    end
  end

  describe '.from_env' do
    it 'returns the identity object stored at env[legion.principal]' do
      env = { 'legion.principal' => request }
      expect(described_class.from_env(env)).to equal(request)
    end

    it 'returns nil when the key is absent' do
      expect(described_class.from_env({})).to be_nil
    end
  end

  describe '.from_auth_context' do
    let(:claims) do
      {
        sub:    'svc-worker-42',
        name:   'Worker Bot',
        kind:   :service,
        groups: ['workers'],
        source: :entra
      }
    end

    it 'builds a Request from the claims hash' do
      req = described_class.from_auth_context(claims)
      expect(req).to be_a(described_class)
    end

    it 'maps sub to principal_id' do
      expect(described_class.from_auth_context(claims).principal_id).to eq('svc-worker-42')
    end

    it 'maps name to canonical_name' do
      expect(described_class.from_auth_context(claims).canonical_name).to eq('worker bot')
    end

    it 'maps kind' do
      expect(described_class.from_auth_context(claims).kind).to eq(:service)
    end

    it 'maps groups' do
      expect(described_class.from_auth_context(claims).groups).to eq(['workers'])
    end

    it 'maps source' do
      expect(described_class.from_auth_context(claims).source).to eq(:entra)
    end

    it 'normalizes canonical_name to lowercase' do
      req = described_class.from_auth_context(claims.merge(name: 'UPPER CASE'))
      expect(req.canonical_name).to eq('upper case')
    end

    it 'strips leading and trailing whitespace from canonical_name' do
      req = described_class.from_auth_context(claims.merge(name: '  spaced  '))
      expect(req.canonical_name).to eq('spaced')
    end

    it 'replaces dots with hyphens in canonical_name' do
      req = described_class.from_auth_context(claims.merge(name: 'jane.doe'))
      expect(req.canonical_name).to eq('jane-doe')
    end

    it 'falls back to preferred_username when name is absent' do
      req = described_class.from_auth_context(
        sub:                'u1',
        preferred_username: 'jdoe@example.com',
        kind:               :human,
        groups:             [],
        source:             :entra
      )
      expect(req.canonical_name).to eq('jdoe@example-com')
    end

    it 'defaults kind to :human when not provided' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', groups: [], source: nil)
      expect(req.kind).to eq(:human)
    end

    it 'defaults groups to [] when not provided' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', source: nil)
      expect(req.groups).to eq([])
    end
  end

  describe '#groups' do
    it 'is frozen' do
      expect(request.groups).to be_frozen
    end
  end

  describe '#identity_hash' do
    subject(:hash) { request.identity_hash }

    it 'includes principal_id' do
      expect(hash[:principal_id]).to eq(principal_id)
    end

    it 'includes canonical_name' do
      expect(hash[:canonical_name]).to eq(canonical_name)
    end

    it 'includes kind' do
      expect(hash[:kind]).to eq(kind)
    end

    it 'includes groups' do
      expect(hash[:groups]).to eq(groups)
    end

    it 'includes source' do
      expect(hash[:source]).to eq(source)
    end
  end

  describe '#to_rbac_principal' do
    it 'maps :service kind to :worker type' do
      req = described_class.new(principal_id: 'svc1', canonical_name: 'my-service', kind: :service)
      expect(req.to_rbac_principal[:type]).to eq(:worker)
    end

    it 'keeps :human kind as :human type' do
      expect(request.to_rbac_principal[:type]).to eq(:human)
    end

    it 'keeps :machine kind as :machine type' do
      req = described_class.new(principal_id: 'mc1', canonical_name: 'my-machine', kind: :machine)
      expect(req.to_rbac_principal[:type]).to eq(:machine)
    end

    it 'sets identity to canonical_name' do
      expect(request.to_rbac_principal[:identity]).to eq(canonical_name)
    end
  end

  describe '#to_caller_hash' do
    subject(:hash) { request.to_caller_hash }

    it 'nests everything under requested_by' do
      expect(hash).to have_key(:requested_by)
    end

    it 'sets id to principal_id' do
      expect(hash[:requested_by][:id]).to eq(principal_id)
    end

    it 'sets identity to canonical_name' do
      expect(hash[:requested_by][:identity]).to eq(canonical_name)
    end

    it 'sets type to kind' do
      expect(hash[:requested_by][:type]).to eq(kind)
    end

    it 'sets credential to source' do
      expect(hash[:requested_by][:credential]).to eq(source)
    end
  end

  describe 'SOURCE_NORMALIZATION' do
    subject(:map) { described_class::SOURCE_NORMALIZATION }

    it 'maps :api_key to :api' do
      expect(map[:api_key]).to eq(:api)
    end

    it 'maps :jwt to :jwt' do
      expect(map[:jwt]).to eq(:jwt)
    end

    it 'maps :kerberos to :kerberos' do
      expect(map[:kerberos]).to eq(:kerberos)
    end

    it 'maps :local to :system' do
      expect(map[:local]).to eq(:system)
    end

    it 'maps :system to :system' do
      expect(map[:system]).to eq(:system)
    end

    it 'is frozen' do
      expect(map).to be_frozen
    end
  end

  describe '.from_auth_context with source normalization' do
    it 'normalizes :api_key source to :api' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', source: :api_key)
      expect(req.source).to eq(:api)
    end

    it 'normalizes :local source to :system' do
      req = described_class.from_auth_context(sub: 'u1', name: 'system', source: :local)
      expect(req.source).to eq(:system)
    end

    it 'normalizes :kerberos source to :kerberos (passthrough)' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', source: :kerberos)
      expect(req.source).to eq(:kerberos)
    end

    it 'normalizes :jwt source to :jwt (passthrough)' do
      req = described_class.from_auth_context(sub: 'u1', name: 'service', source: :jwt)
      expect(req.source).to eq(:jwt)
    end

    it 'preserves unknown source values as-is' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', source: :entra)
      expect(req.source).to eq(:entra)
    end

    it 'handles nil source gracefully' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', source: nil)
      expect(req.source).to be_nil
    end

    it 'normalizes string source values by converting to symbol first' do
      req = described_class.from_auth_context(sub: 'u1', name: 'alice', source: 'local')
      expect(req.source).to eq(:system)
    end
  end
end
