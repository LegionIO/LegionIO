# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::Extensions::Helpers::Secret do
  let(:test_module) do
    Module.new do
      extend Legion::Extensions::Helpers::Base
      extend Legion::Extensions::Helpers::Secret

      def self.calling_class
        Legion::Extensions::Github::Runners::Repositories
      end

      def self.calling_class_array
        %w[Legion Extensions Github Runners Repositories]
      end
    end
  end

  before do
    described_class.reset_identity!
    stub_const('Legion::Settings', Module.new {
      extend self
      def [](key)
        { vault: { connected: true } } if key == :crypt
      end
    })
  end

  describe '.resolve_identity!' do
    it 'returns nil when no auth sources available' do
      expect(described_class.resolve_identity!).to be_nil
    end

    it 'prefers kerberos principal over all other sources' do
      stub_const('Legion::Crypt', Module.new {
        extend self
        def kerberos_principal
          'kerb_user'
        end
      })
      expect(described_class.resolve_identity!).to eq('kerb_user')
      expect(described_class.identity_source).to eq(:kerberos)
    end

    it 'falls back to entra when kerberos is unavailable' do
      token_cache_instance = double('token_cache', user_principal: 'entra_user')
      token_cache_class = double('TokenCache', instance: token_cache_instance)
      allow(token_cache_class).to receive(:respond_to?).with(:instance).and_return(true)
      allow(token_cache_instance).to receive(:respond_to?).with(:user_principal).and_return(true)

      stub_const('Legion::Extensions::MicrosoftTeams::Helpers::TokenCache', token_cache_class)

      expect(described_class.resolve_identity!).to eq('entra_user')
      expect(described_class.identity_source).to eq(:entra)
    end
  end

  describe '#secret' do
    it 'returns a SecretAccessor scoped to the extension lex_name' do
      accessor = test_module.secret
      expect(accessor).to be_a(Legion::Extensions::Helpers::SecretAccessor)
    end

    it 'returns the same accessor on repeated calls' do
      expect(test_module.secret).to equal(test_module.secret)
    end
  end
end

RSpec.describe Legion::Extensions::Helpers::SecretAccessor do
  subject(:accessor) { described_class.new(lex_name: 'github') }

  before do
    Legion::Extensions::Helpers::Secret.reset_identity!
    allow(ENV).to receive(:fetch).with('USER', 'default').and_return('testuser')
  end

  describe '#[]' do
    it 'reads from per-user vault path' do
      stub_const('Legion::Crypt', Module.new {
        extend self
        def get(path)
          { token: 'abc123' } if path == 'users/testuser/github/api_key'
        end
        def kerberos_principal; nil; end
      })

      expect(accessor[:api_key]).to eq({ token: 'abc123' })
    end

    it 'reads from shared path when shared: true' do
      stub_const('Legion::Crypt', Module.new {
        extend self
        def get(path)
          { token: 'shared_tok' } if path == 'shared/github/api_key'
        end
        def kerberos_principal; nil; end
      })

      expect(accessor[:api_key, shared: true]).to eq({ token: 'shared_tok' })
    end

    it 'uses explicit user when provided' do
      stub_const('Legion::Crypt', Module.new {
        extend self
        def get(path)
          { token: 'other_tok' } if path == 'users/other_person/github/api_key'
        end
        def kerberos_principal; nil; end
      })

      expect(accessor[:api_key, user: 'other_person']).to eq({ token: 'other_tok' })
    end

    it 'returns nil when Legion::Crypt is not defined' do
      hide_const('Legion::Crypt')
      expect(accessor[:api_key]).to be_nil
    end
  end

  describe '#[]=' do
    it 'writes to per-user vault path' do
      crypt = Module.new {
        extend self
        def write(path, **data); end
        def kerberos_principal; nil; end
      }
      stub_const('Legion::Crypt', crypt)
      allow(crypt).to receive(:write)

      accessor[:api_key] = { token: 'new_tok' }
      expect(crypt).to have_received(:write).with('users/testuser/github/api_key', token: 'new_tok')
    end
  end

  describe '#write' do
    it 'writes to shared path when shared: true' do
      crypt = Module.new {
        extend self
        def write(path, **data); end
        def kerberos_principal; nil; end
      }
      stub_const('Legion::Crypt', crypt)
      allow(crypt).to receive(:write)

      accessor.write(:api_key, token: 'shared_tok', shared: true)
      expect(crypt).to have_received(:write).with('shared/github/api_key', token: 'shared_tok')
    end
  end

  describe '#exist?' do
    it 'checks per-user path by default' do
      crypt = Module.new {
        extend self
        def exist?(path)
          path == 'users/testuser/github/api_key'
        end
        def kerberos_principal; nil; end
      }
      stub_const('Legion::Crypt', crypt)

      expect(accessor.exist?(:api_key)).to be true
      expect(accessor.exist?(:missing_key)).to be false
    end
  end

  describe '#delete' do
    it 'deletes from per-user path' do
      crypt = Module.new {
        extend self
        def delete(path); end
        def kerberos_principal; nil; end
      }
      stub_const('Legion::Crypt', crypt)
      allow(crypt).to receive(:delete)

      accessor.delete(:api_key)
      expect(crypt).to have_received(:delete).with('users/testuser/github/api_key')
    end
  end

  describe 'identity resolution in path' do
    it 'uses kerberos principal when available' do
      crypt = Module.new {
        extend self
        def get(path); end
        def kerberos_principal
          'kerb_user'
        end
      }
      stub_const('Legion::Crypt', crypt)
      allow(crypt).to receive(:get)

      Legion::Extensions::Helpers::Secret.resolve_identity!
      accessor[:api_key]
      expect(crypt).to have_received(:get).with('users/kerb_user/github/api_key')
    end
  end
end

RSpec.describe 'Helpers::Lex includes Secret' do
  it 'includes Secret module' do
    expect(Legion::Extensions::Helpers::Lex.ancestors).to include(Legion::Extensions::Helpers::Secret)
  end
end
