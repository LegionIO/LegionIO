# LegionIO TLS Configuration

Quick-start guide for enabling TLS on all LegionIO components.

## Generating Dev Certificates

```bash
sudo ./generate-certs.sh /etc/legionio/tls
```

Requires `openssl` in PATH. Creates:
- `ca.pem` / `ca.key` — self-signed CA
- `server.crt` / `server.key` — server certificate (localhost + 127.0.0.1 SAN)
- `client.crt` / `client.key` — client certificate

## Applying the Settings

Copy `settings-tls.json` to your LegionIO settings directory
(`~/legionio/settings/` or `/etc/legionio/settings/`) and adjust paths.

Feature flags (default false — plain connections preserved unless enabled):
- `data.tls.enabled` — enables TLS for PostgreSQL/MySQL
- `api.tls.enabled` — enables TLS for the Puma HTTP API

## Validating

```bash
legion doctor
```

The TLS doctor check verifies: TLS enabled/verify mode, cert file existence, sslmode correctness.
