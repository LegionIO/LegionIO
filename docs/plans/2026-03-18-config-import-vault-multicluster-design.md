# Config Import + Multi-Cluster Vault Design

## Problem

LegionIO currently supports a single Vault cluster (`crypt.vault.address/port/token`). In enterprise environments, engineers work with multiple Vault clusters (dev, test, stage, production) and need different tokens for each. There's also no way to bootstrap a new developer's environment from a shared config — they must manually create JSON files in `~/.legionio/settings/`.

## Solution

Three changes across three repos:

### 1. legion-crypt: Multi-Cluster Vault Support

Upgrade `crypt.vault` from a single cluster to a named clusters hash with a `default` pointer.

#### Settings Schema

```json
{
  "crypt": {
    "vault": {
      "default": "prod",
      "clusters": {
        "dev": {
          "address": "vault-dev.example.com",
          "port": 8200,
          "protocol": "https",
          "namespace": "myapp",
          "token": null,
          "auth_method": "ldap"
        },
        "stage": {
          "address": "vault-stage.example.com",
          "port": 8200,
          "protocol": "https",
          "namespace": "myapp",
          "token": null,
          "auth_method": "ldap"
        },
        "prod": {
          "address": "vault.example.com",
          "port": 8200,
          "protocol": "https",
          "namespace": "myapp",
          "token": null,
          "auth_method": "ldap"
        }
      }
    }
  }
}
```

#### Backward Compatibility

If `crypt.vault.clusters` is absent but `crypt.vault.address` is present, treat it as a single unnamed cluster (current behavior). The migration path is:

```ruby
# Old style (still works)
Legion::Settings[:crypt][:vault][:address]  # => "vault.example.com"

# New style
Legion::Crypt.cluster(:prod)    # => cluster config hash
Legion::Crypt.cluster            # => default cluster config hash
Legion::Crypt.default_cluster    # => "prod"
```

#### New Module: `Legion::Crypt::VaultCluster`

Manages per-cluster Vault connections:

```ruby
module Legion::Crypt
  module VaultCluster
    # Get a configured ::Vault client for a named cluster
    def vault_client(name = nil)
      name ||= default_cluster_name
      @vault_clients ||= {}
      @vault_clients[name] ||= build_client(clusters[name])
    end

    # Cluster config hash
    def cluster(name = nil)
      name ||= default_cluster_name
      clusters[name]
    end

    def default_cluster_name
      vault_settings[:default] || clusters.keys.first
    end

    def clusters
      vault_settings[:clusters] || {}
    end

    # Connect to all clusters that have tokens
    def connect_all
      clusters.each do |name, config|
        next unless config[:token]
        connect_cluster(name)
      end
    end

    private

    def build_client(config)
      client = ::Vault::Client.new(
        address: "#{config[:protocol]}://#{config[:address]}:#{config[:port]}",
        token:   config[:token]
      )
      client.namespace = config[:namespace] if config[:namespace]
      client
    end
  end
end
```

#### New Module: `Legion::Crypt::LdapAuth`

LDAP authentication against Vault's LDAP auth method (HTTP API, no vault CLI):

```ruby
module Legion::Crypt
  module LdapAuth
    # Authenticate to a single cluster via LDAP
    # POST /v1/auth/ldap/login/:username
    # Returns: { token:, lease_duration:, renewable:, policies: }
    def ldap_login(cluster_name:, username:, password:)
      client = vault_client(cluster_name)
      # Or raw HTTP if ::Vault gem doesn't expose ldap auth:
      response = client.post("/v1/auth/ldap/login/#{username}", password: password)
      token = response.auth.client_token
      # Store token in cluster config (in-memory only, not written to disk with password)
      clusters[cluster_name][:token] = token
      clusters[cluster_name][:connected] = true
      { token: token, lease_duration: response.auth.lease_duration,
        renewable: response.auth.renewable, policies: response.auth.policies }
    end

    # Authenticate to ALL configured clusters with same credentials
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
```

#### Existing Code Changes

- `Legion::Crypt.start` — if `clusters` present, call `connect_all` instead of `connect_vault`
- `Legion::Crypt::Vault.read/write/get` — route through `vault_client(name)` for cluster-aware reads
- `Legion::Crypt::Vault.connect_vault` — still works for legacy single-cluster config
- `Legion::Crypt::VaultRenewer` — renew tokens for ALL connected clusters
- `Legion::Settings::Resolver` — `vault://` refs gain optional cluster prefix: `vault://prod/secret/data/myapp#password` (falls back to default cluster if no prefix)

### 2. LegionIO: `legion config import` / `legionio config import` CLI Command

New subcommand under `Config`:

```
legionio config import <source>     # URL or local file path
legion config import <source>       # same command available in interactive binary
```

#### Behavior

1. **Fetch source:**
   - If `source` starts with `http://` or `https://` — HTTP GET, follow redirects
   - Otherwise — read local file
2. **Decode payload:**
   - Try `JSON.parse(body)` first
   - If that fails, try `JSON.parse(Base64.decode64(body))`
   - If both fail, error with "not valid JSON or base64-encoded JSON"
3. **Validate structure:**
   - Must be a Hash
   - Warn on unrecognized top-level keys (not in known settings keys)
4. **Write to `~/.legionio/settings/imported.json`:**
   - Deep merge with existing imported.json if present
   - Or overwrite with `--force`
5. **Display summary:**
   - Which settings sections were imported (crypt, transport, cache, etc.)
   - How many vault clusters configured
   - Remind user to run `legion` for onboarding vault auth

#### Example Config File

```json
{
  "crypt": {
    "vault": {
      "default": "prod",
      "clusters": {
        "dev":   { "address": "vault-dev.uhg.com",   "port": 8200, "protocol": "https", "auth_method": "ldap" },
        "test":  { "address": "vault-test.uhg.com",  "port": 8200, "protocol": "https", "auth_method": "ldap" },
        "stage": { "address": "vault-stage.uhg.com", "port": 8200, "protocol": "https", "auth_method": "ldap" },
        "prod":  { "address": "vault.uhg.com",       "port": 8200, "protocol": "https", "auth_method": "ldap" }
      }
    }
  },
  "transport": {
    "host": "rabbitmq.uhg.com",
    "port": 5672,
    "vhost": "legion"
  },
  "cache": {
    "driver": "dalli",
    "servers": ["memcached.uhg.com:11211"]
  }
}
```

### 3. legion-tty: Onboarding Vault Auth Step

After the wizard (name + LLM providers), before the reveal box:

```
[digital rain]
[intro - kerberos identity, github quick]
[wizard - name, LLM providers]
[NEW: vault auth prompt]
[reveal box - now includes vault cluster status]
```

#### Flow

1. Check if any vault clusters are configured in settings
2. If none, skip entirely
3. If clusters exist, ask: "I found N Vault clusters. Connect now?" (TTY::Prompt confirm)
4. If yes:
   - Default username = kerberos `samaccountname` (from `@kerberos_identity[:samaccountname]`), fallback to `ENV['USER']`
   - Ask: "Username:" with default pre-filled (TTY::Prompt ask)
   - Ask: "Password:" with `echo: false` (hidden input)
   - For each LDAP-configured cluster, attempt `Legion::Crypt.ldap_login`
   - Show green checkmark / red X per cluster with name
5. Store tokens in memory (settings hash), NOT on disk with the password
6. Reveal box now shows vault cluster connection status

#### New Background Probe: Not Needed

Vault auth requires user interaction (password prompt), so it runs inline after the wizard, not in a background thread.

## Alternatives Considered

**Use lex-vault instead of vault gem for multi-cluster:** lex-vault's Faraday-based client is simpler and already supports per-instance address/token/namespace. Could replace the `vault` gem dependency in legion-crypt entirely. Deferred — not a requirement for this iteration but a good future optimization.

**Kerberos auth for Vault:** Not a default Vault auth method. Would require a custom Vault plugin. Deferred.

**Store tokens on disk:** Vault tokens are renewable and short-lived. Storing them risks stale tokens. Better to re-auth on each `legion` startup if needed. Could add optional token caching later.

## Constraints

- LDAP password is NEVER written to disk or settings files
- Vault tokens are stored in-memory only during the session
- `vault://` resolver must remain backward compatible (no cluster prefix = default cluster)
- Single-cluster config (`crypt.vault.address`) must continue to work unchanged
- Config import file is plain JSON, no wrapper format
- HTTP sources must handle both raw JSON and base64-encoded JSON

## Repos Affected

| Repo | Changes |
|------|---------|
| `legion-crypt` | `VaultCluster` module, `LdapAuth` module, multi-cluster settings, `VaultRenewer` update, backward compat |
| `LegionIO` | `config import` CLI command (both binaries), HTTP fetch + base64 detection |
| `legion-tty` | Onboarding vault auth step after wizard |
| `legion-settings` | `Resolver` update for cluster-prefixed `vault://` refs (optional, can defer) |
