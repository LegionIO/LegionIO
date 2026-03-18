# Config Import + Multi-Cluster Vault Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add multi-cluster Vault support to legion-crypt, a `config import` CLI command, and onboarding Vault LDAP auth in legion-tty.

**Architecture:** Three repos changed independently. legion-crypt lands first (prerequisite), then LegionIO CLI and legion-tty can be done in parallel.

**Tech Stack:** Ruby, vault gem, Faraday (for LDAP HTTP auth), TTY::Prompt (hidden password input)

**Design Doc:** `docs/plans/2026-03-18-config-import-vault-multicluster-design.md`

---

## Phase 1: legion-crypt Multi-Cluster Vault (prerequisite)

### Task 1: Multi-Cluster Settings Schema

**Files:**
- Modify: `legion-crypt/lib/legion/crypt/settings.rb`
- Test: `legion-crypt/spec/legion/settings_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/legion/settings_spec.rb
describe 'vault defaults' do
  it 'includes clusters hash' do
    expect(vault[:clusters]).to eq({})
  end

  it 'includes default key' do
    expect(vault[:default]).to be_nil
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd legion-crypt && bundle exec rspec spec/legion/settings_spec.rb -v`
Expected: FAIL — no `:clusters` or `:default` key in vault defaults

**Step 3: Write minimal implementation**

Add to `Legion::Crypt::Settings.vault`:
```ruby
def self.vault
  {
    enabled:             !Gem::Specification.find_by_name('vault').nil?,
    protocol:            'http',
    address:             'localhost',
    port:                8200,
    token:               ENV['VAULT_DEV_ROOT_TOKEN_ID'] || ENV['VAULT_TOKEN_ID'] || nil,
    connected:           false,
    renewer_time:        5,
    renewer:             true,
    push_cluster_secret: true,
    read_cluster_secret: true,
    kv_path:             ENV['LEGION_VAULT_KV_PATH'] || 'legion',
    leases:              {},
    default:             nil,
    clusters:            {}
  }
end
```

**Step 4: Run test to verify it passes**

Run: `cd legion-crypt && bundle exec rspec spec/legion/settings_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/crypt/settings.rb spec/legion/settings_spec.rb
git commit -m "add clusters and default keys to vault settings schema"
```

### Task 2: VaultCluster Module

**Files:**
- Create: `legion-crypt/lib/legion/crypt/vault_cluster.rb`
- Test: `legion-crypt/spec/legion/vault_cluster_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/legion/vault_cluster_spec.rb
require 'spec_helper'
require 'legion/crypt/vault_cluster'

RSpec.describe Legion::Crypt::VaultCluster do
  let(:test_obj) { Object.new.extend(described_class) }

  before do
    allow(test_obj).to receive(:vault_settings).and_return({
      default: 'prod',
      clusters: {
        dev:  { address: 'vault-dev.example.com', port: 8200, protocol: 'https', token: nil },
        prod: { address: 'vault.example.com', port: 8200, protocol: 'https', token: 'hvs.abc123' }
      }
    })
  end

  describe '#default_cluster_name' do
    it 'returns the configured default' do
      expect(test_obj.default_cluster_name).to eq(:prod)
    end
  end

  describe '#cluster' do
    it 'returns default cluster when no name given' do
      expect(test_obj.cluster[:address]).to eq('vault.example.com')
    end

    it 'returns named cluster' do
      expect(test_obj.cluster(:dev)[:address]).to eq('vault-dev.example.com')
    end

    it 'returns nil for unknown cluster' do
      expect(test_obj.cluster(:unknown)).to be_nil
    end
  end

  describe '#clusters' do
    it 'returns all clusters' do
      expect(test_obj.clusters.keys).to contain_exactly(:dev, :prod)
    end
  end

  describe '#vault_client' do
    it 'returns a Vault::Client for the default cluster' do
      client = test_obj.vault_client
      expect(client).to be_a(::Vault::Client)
      expect(client.address).to eq('https://vault.example.com:8200')
      expect(client.token).to eq('hvs.abc123')
    end

    it 'returns a Vault::Client for a named cluster' do
      client = test_obj.vault_client(:dev)
      expect(client.address).to eq('https://vault-dev.example.com:8200')
    end

    it 'memoizes clients per cluster name' do
      client1 = test_obj.vault_client(:prod)
      client2 = test_obj.vault_client(:prod)
      expect(client1).to equal(client2)
    end
  end

  describe '#connected_clusters' do
    it 'returns clusters that have tokens' do
      expect(test_obj.connected_clusters.keys).to eq([:prod])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd legion-crypt && bundle exec rspec spec/legion/vault_cluster_spec.rb -v`
Expected: FAIL — `Legion::Crypt::VaultCluster` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/legion/crypt/vault_cluster.rb
# frozen_string_literal: true

require 'vault'

module Legion
  module Crypt
    module VaultCluster
      def vault_client(name = nil)
        name = (name || default_cluster_name).to_sym
        @vault_clients ||= {}
        @vault_clients[name] ||= build_vault_client(clusters[name])
      end

      def cluster(name = nil)
        name = (name || default_cluster_name).to_sym
        clusters[name]
      end

      def default_cluster_name
        (vault_settings[:default] || clusters.keys.first).to_sym
      end

      def clusters
        vault_settings[:clusters] || {}
      end

      def connected_clusters
        clusters.select { |_, config| config[:token] }
      end

      def connect_all_clusters
        results = {}
        clusters.each do |name, config|
          next unless config[:token]

          client = vault_client(name)
          config[:connected] = client.sys.health_status.initialized?
          results[name] = config[:connected]
        rescue StandardError => e
          config[:connected] = false
          results[name] = false
          log_vault_error(name, e)
        end
        results
      end

      private

      def build_vault_client(config)
        return nil unless config.is_a?(Hash)

        client = ::Vault::Client.new(
          address: "#{config[:protocol]}://#{config[:address]}:#{config[:port]}",
          token:   config[:token]
        )
        client.namespace = config[:namespace] if config[:namespace]
        client
      end

      def log_vault_error(name, error)
        if defined?(Legion::Logging)
          Legion::Logging.error("Vault cluster #{name}: #{error.message}")
        else
          warn("Vault cluster #{name}: #{error.message}")
        end
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd legion-crypt && bundle exec rspec spec/legion/vault_cluster_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/crypt/vault_cluster.rb spec/legion/vault_cluster_spec.rb
git commit -m "add VaultCluster module for multi-cluster vault connections"
```

### Task 3: LdapAuth Module

**Files:**
- Create: `legion-crypt/lib/legion/crypt/ldap_auth.rb`
- Test: `legion-crypt/spec/legion/ldap_auth_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/legion/ldap_auth_spec.rb
require 'spec_helper'
require 'legion/crypt/vault_cluster'
require 'legion/crypt/ldap_auth'

RSpec.describe Legion::Crypt::LdapAuth do
  let(:test_obj) do
    obj = Object.new
    obj.extend(Legion::Crypt::VaultCluster)
    obj.extend(described_class)
    obj
  end

  let(:clusters_config) do
    {
      default: 'prod',
      clusters: {
        prod:  { address: 'vault.example.com', port: 8200, protocol: 'https', auth_method: 'ldap', token: nil },
        stage: { address: 'vault-stage.example.com', port: 8200, protocol: 'https', auth_method: 'ldap', token: nil },
        dev:   { address: 'vault-dev.example.com', port: 8200, protocol: 'https', auth_method: 'token', token: 'hvs.existing' }
      }
    }
  end

  before do
    allow(test_obj).to receive(:vault_settings).and_return(clusters_config)
  end

  describe '#ldap_login' do
    it 'authenticates to a cluster and stores the token' do
      mock_auth = double(client_token: 'hvs.newtoken', lease_duration: 3600, renewable: true, policies: ['default'])
      mock_secret = double(auth: mock_auth)
      mock_logical = double(write: mock_secret)
      mock_client = instance_double(::Vault::Client, logical: mock_logical)
      allow(test_obj).to receive(:vault_client).with(:prod).and_return(mock_client)

      result = test_obj.ldap_login(cluster_name: :prod, username: 'jdoe', password: 's3cret')
      expect(result[:token]).to eq('hvs.newtoken')
      expect(result[:lease_duration]).to eq(3600)
      expect(clusters_config[:clusters][:prod][:token]).to eq('hvs.newtoken')
    end
  end

  describe '#ldap_login_all' do
    it 'authenticates to all LDAP clusters and skips non-LDAP ones' do
      mock_auth = double(client_token: 'hvs.tok', lease_duration: 3600, renewable: true, policies: ['default'])
      mock_secret = double(auth: mock_auth)
      mock_logical = double(write: mock_secret)
      mock_client = instance_double(::Vault::Client, logical: mock_logical)
      allow(test_obj).to receive(:vault_client).and_return(mock_client)

      results = test_obj.ldap_login_all(username: 'jdoe', password: 's3cret')
      expect(results.keys).to contain_exactly(:prod, :stage)
      expect(results[:prod][:token]).to eq('hvs.tok')
      expect(results[:stage][:token]).to eq('hvs.tok')
    end

    it 'captures errors per cluster without stopping' do
      allow(test_obj).to receive(:vault_client).and_raise(StandardError.new('connection refused'))

      results = test_obj.ldap_login_all(username: 'jdoe', password: 's3cret')
      expect(results[:prod][:error]).to eq('connection refused')
      expect(results[:stage][:error]).to eq('connection refused')
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd legion-crypt && bundle exec rspec spec/legion/ldap_auth_spec.rb -v`
Expected: FAIL — `Legion::Crypt::LdapAuth` not defined

**Step 3: Write minimal implementation**

```ruby
# lib/legion/crypt/ldap_auth.rb
# frozen_string_literal: true

module Legion
  module Crypt
    module LdapAuth
      def ldap_login(cluster_name:, username:, password:)
        client = vault_client(cluster_name)
        secret = client.logical.write("auth/ldap/login/#{username}", password: password)
        auth = secret.auth
        token = auth.client_token

        clusters[cluster_name][:token] = token
        clusters[cluster_name][:connected] = true

        { token: token, lease_duration: auth.lease_duration,
          renewable: auth.renewable, policies: auth.policies }
      end

      def ldap_login_all(username:, password:)
        results = {}
        clusters.each do |name, config|
          next unless config[:auth_method] == 'ldap'

          results[name] = ldap_login(cluster_name: name, username: username, password: password)
        rescue StandardError => e
          results[name] = { error: e.message }
        end
        results
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd legion-crypt && bundle exec rspec spec/legion/ldap_auth_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/crypt/ldap_auth.rb spec/legion/ldap_auth_spec.rb
git commit -m "add LdapAuth module for vault LDAP authentication"
```

### Task 4: Wire Multi-Cluster into Legion::Crypt.start

**Files:**
- Modify: `legion-crypt/lib/legion/crypt.rb`
- Modify: `legion-crypt/lib/legion/crypt/vault.rb`
- Test: `legion-crypt/spec/legion/crypt_spec.rb`

**Step 1: Write the failing test**

```ruby
# Add to spec/legion/crypt_spec.rb
describe '.cluster' do
  it 'delegates to VaultCluster#cluster' do
    expect(Legion::Crypt).to respond_to(:cluster)
  end
end

describe '.ldap_login_all' do
  it 'delegates to LdapAuth#ldap_login_all' do
    expect(Legion::Crypt).to respond_to(:ldap_login_all)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd legion-crypt && bundle exec rspec spec/legion/crypt_spec.rb -v`
Expected: FAIL — `Legion::Crypt.cluster` not defined

**Step 3: Write minimal implementation**

In `lib/legion/crypt.rb`, add:
```ruby
require_relative 'crypt/vault_cluster'
require_relative 'crypt/ldap_auth'

module Legion
  module Crypt
    extend VaultCluster
    extend LdapAuth

    def self.vault_settings
      Legion::Settings[:crypt][:vault]
    end

    # Update start to handle multi-cluster
    def self.start
      # ... existing code ...
      if vault_settings[:clusters]&.any?
        connect_all_clusters
      else
        connect_vault  # legacy single-cluster path
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd legion-crypt && bundle exec rspec spec/legion/crypt_spec.rb -v`
Expected: PASS

**Step 5: Run full suite and commit**

```bash
cd legion-crypt && bundle exec rspec && bundle exec rubocop -A && bundle exec rubocop
git add lib/legion/crypt.rb lib/legion/crypt/vault.rb spec/legion/crypt_spec.rb
git commit -m "wire multi-cluster vault into Legion::Crypt.start with backward compat"
```

### Task 5: Update VaultRenewer for Multi-Cluster

**Files:**
- Modify: `legion-crypt/lib/legion/crypt/vault_renewer.rb`
- Test: `legion-crypt/spec/legion/vault_renewer_spec.rb`

Renewer must iterate `connected_clusters` and renew each token. If no clusters are configured, fall back to single-cluster renewal (existing behavior).

### Task 6: Version Bump + Pipeline

**Files:**
- Modify: `legion-crypt/lib/legion/crypt/version.rb` (bump to 1.4.4)
- Modify: `legion-crypt/CHANGELOG.md`

Run full pre-push pipeline: rspec, rubocop -A, rubocop, version bump, changelog, push.

---

## Phase 2: LegionIO `config import` CLI Command

### Task 7: Config Import Command

**Files:**
- Create: `LegionIO/lib/legion/cli/config_import.rb`
- Modify: `LegionIO/lib/legion/cli/config_command.rb` (register subcommand)
- Test: `LegionIO/spec/legion/cli/config_import_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/legion/cli/config_import_spec.rb
require 'spec_helper'
require 'legion/cli/config_import'

RSpec.describe Legion::CLI::ConfigImport do
  describe '.parse_payload' do
    it 'parses raw JSON' do
      result = described_class.parse_payload('{"crypt": {"vault": {}}}')
      expect(result).to eq({ crypt: { vault: {} } })
    end

    it 'parses base64-encoded JSON' do
      encoded = Base64.strict_encode64('{"transport": {"host": "rmq.example.com"}}')
      result = described_class.parse_payload(encoded)
      expect(result[:transport][:host]).to eq('rmq.example.com')
    end

    it 'raises on invalid input' do
      expect { described_class.parse_payload('not json at all %%%') }.to raise_error(Legion::CLI::Error)
    end
  end

  describe '.fetch_source' do
    it 'reads a local file' do
      tmpfile = Tempfile.new(['config', '.json'])
      tmpfile.write('{"cache": {"driver": "dalli"}}')
      tmpfile.close
      result = described_class.fetch_source(tmpfile.path)
      expect(result).to include('"cache"')
      tmpfile.unlink
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd LegionIO && bundle exec rspec spec/legion/cli/config_import_spec.rb -v`
Expected: FAIL — file doesn't exist

**Step 3: Write minimal implementation**

```ruby
# lib/legion/cli/config_import.rb
# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'uri'
require 'fileutils'

module Legion
  module CLI
    class ConfigImport
      SETTINGS_DIR = File.expand_path('~/.legionio/settings')
      IMPORT_FILE  = 'imported.json'

      def self.fetch_source(source)
        if source.match?(%r{\Ahttps?://})
          fetch_http(source)
        else
          raise CLI::Error, "File not found: #{source}" unless File.exist?(source)

          File.read(source)
        end
      end

      def self.fetch_http(url)
        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)
        raise CLI::Error, "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end

      def self.parse_payload(body)
        # Try raw JSON first
        parsed = ::JSON.parse(body, symbolize_names: true)
        raise CLI::Error, 'Config must be a JSON object' unless parsed.is_a?(Hash)

        parsed
      rescue ::JSON::ParserError
        # Try base64-decoded JSON
        begin
          decoded = Base64.decode64(body)
          parsed = ::JSON.parse(decoded, symbolize_names: true)
          raise CLI::Error, 'Config must be a JSON object' unless parsed.is_a?(Hash)

          parsed
        rescue ::JSON::ParserError
          raise CLI::Error, 'Source is not valid JSON or base64-encoded JSON'
        end
      end

      def self.write_config(config, force: false)
        FileUtils.mkdir_p(SETTINGS_DIR)
        path = File.join(SETTINGS_DIR, IMPORT_FILE)

        if File.exist?(path) && !force
          existing = ::JSON.parse(File.read(path), symbolize_names: true)
          config = deep_merge(existing, config)
        end

        File.write(path, ::JSON.pretty_generate(config))
        path
      end

      def self.deep_merge(base, overlay)
        base.merge(overlay) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end

      def self.summary(config)
        sections = config.keys.map(&:to_s)
        vault_clusters = config.dig(:crypt, :vault, :clusters)&.keys&.map(&:to_s) || []
        { sections: sections, vault_clusters: vault_clusters }
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `cd LegionIO && bundle exec rspec spec/legion/cli/config_import_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/cli/config_import.rb spec/legion/cli/config_import_spec.rb
git commit -m "add config import utility for URL and local file sources"
```

### Task 8: Wire Import into Config Subcommand

**Files:**
- Modify: `LegionIO/lib/legion/cli/config_command.rb`

Add `import` subcommand to Config Thor class:
```ruby
desc 'import SOURCE', 'Import configuration from a URL or local file'
option :force, type: :boolean, default: false, desc: 'Overwrite existing imported config'
def import(source)
  out = formatter
  require_relative 'config_import'

  out.info("Fetching config from #{source}...")
  body = ConfigImport.fetch_source(source)
  config = ConfigImport.parse_payload(body)
  path = ConfigImport.write_config(config, force: options[:force])
  summary = ConfigImport.summary(config)

  out.success("Config written to #{path}")
  out.info("Sections: #{summary[:sections].join(', ')}")
  if summary[:vault_clusters].any?
    out.info("Vault clusters: #{summary[:vault_clusters].join(', ')}")
    out.info("Run 'legion' to authenticate via LDAP during onboarding")
  end
rescue CLI::Error => e
  formatter.error(e.message)
  raise SystemExit, 1
end
```

**Step 1: Write test, Step 2: Verify fail, Step 3: Implement, Step 4: Verify pass**

**Step 5: Commit**

```bash
git add lib/legion/cli/config_command.rb
git commit -m "add 'config import' subcommand for URL and local file config import"
```

### Task 9: Version Bump + Pipeline for LegionIO

Run full pre-push pipeline. Bump to 1.4.63.

---

## Phase 3: legion-tty Onboarding Vault Auth

### Task 10: VaultAuth Background-Free Prompt

**Files:**
- Create: `legion-tty/lib/legion/tty/screens/vault_auth.rb` (extracted helper, not a full screen)
- Modify: `legion-tty/lib/legion/tty/screens/onboarding.rb`
- Test: `legion-tty/spec/legion/tty/screens/onboarding_spec.rb`

**Step 1: Write the failing test**

```ruby
# Add to onboarding_spec.rb
describe '#run_vault_auth' do
  context 'when no vault clusters configured' do
    it 'skips vault auth entirely' do
      allow(screen).to receive(:vault_clusters_configured?).and_return(false)
      expect(wizard).not_to receive(:confirm)
      screen.send(:run_vault_auth)
    end
  end

  context 'when vault clusters configured' do
    before do
      allow(screen).to receive(:vault_clusters_configured?).and_return(true)
      allow(screen).to receive(:vault_cluster_count).and_return(3)
    end

    it 'asks user if they want to connect' do
      allow(wizard).to receive(:confirm).and_return(false)
      screen.send(:run_vault_auth)
      expect(wizard).to have_received(:confirm).with(/3 Vault clusters/)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `cd legion-tty && bundle exec rspec spec/legion/tty/screens/onboarding_spec.rb -v`
Expected: FAIL

**Step 3: Write minimal implementation**

Add to `onboarding.rb`:

```ruby
def run_vault_auth
  return unless vault_clusters_configured?

  count = vault_cluster_count
  typed_output("I found #{count} Vault cluster#{'s' if count != 1}.")
  @output.puts
  return unless @wizard.confirm("Connect now?")

  username = default_vault_username
  username = @wizard.ask_with_default('Username:', username)
  password = @wizard.ask_secret('Password:')

  typed_output('Authenticating...')
  @output.puts

  results = Legion::Crypt.ldap_login_all(username: username, password: password)
  display_vault_results(results)
end

def vault_clusters_configured?
  return false unless defined?(Legion::Crypt)

  clusters = Legion::Settings.dig(:crypt, :vault, :clusters)
  clusters.is_a?(Hash) && clusters.any?
rescue StandardError
  false
end

def vault_cluster_count
  Legion::Settings.dig(:crypt, :vault, :clusters)&.size || 0
end

def default_vault_username
  if @kerberos_identity
    @kerberos_identity[:samaccountname] || @kerberos_identity[:first_name]&.downcase
  else
    ENV.fetch('USER', 'unknown')
  end
end

def display_vault_results(results)
  results.each do |name, result|
    if result[:error]
      @output.puts "  #{Theme.c(:error, 'X')} #{name}: #{result[:error]}"
    else
      @output.puts "  #{Theme.c(:success, 'ok')} #{name}: connected (#{result[:policies]&.size || 0} policies)"
    end
  end
  @output.puts
  sleep 1
end
```

Wire into `activate` method between `run_wizard` and `collect_background_results`:
```ruby
def activate
  start_background_threads
  run_rain unless @skip_rain
  run_intro
  config = run_wizard
  run_vault_auth          # <-- NEW
  scan_data, github_data = collect_background_results
  # ...
end
```

**Step 4: Run test to verify it passes**

Run: `cd legion-tty && bundle exec rspec spec/legion/tty/screens/onboarding_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/legion/tty/screens/onboarding.rb spec/legion/tty/screens/onboarding_spec.rb
git commit -m "add vault LDAP auth step to onboarding wizard"
```

### Task 11: WizardPrompt Secret Input

**Files:**
- Modify: `legion-tty/lib/legion/tty/components/wizard_prompt.rb`
- Test: `legion-tty/spec/legion/tty/components/wizard_prompt_spec.rb`

Add `ask_secret` and `ask_with_default` methods to WizardPrompt:

```ruby
def ask_secret(question)
  @prompt.mask(question)
end

def ask_with_default(question, default)
  @prompt.ask(question, default: default)
end
```

### Task 12: Vault Summary in Reveal Box

**Files:**
- Modify: `legion-tty/lib/legion/tty/screens/onboarding.rb`

Add `vault_summary_lines` to `build_summary`, showing connected/disconnected vault clusters.

### Task 13: Version Bump + Pipeline for legion-tty

Bump to 0.2.3. Run full pre-push pipeline.

---

## Execution Order

```
Task 1-6  (legion-crypt)   — FIRST, prerequisite
Task 7-9  (LegionIO)       — after Task 6, can parallel with Tasks 10-13
Task 10-13 (legion-tty)    — after Task 6, can parallel with Tasks 7-9
```

## Recommended Execution: `1 → 2 → 3 → 4 → 5 → 6 → [7-9 || 10-13]`
