#!/usr/bin/env bash
set -euo pipefail

# Generates a self-signed CA and service certificates for local TLS development.
# Usage: ./generate-certs.sh [output-dir]
# Default output-dir: /etc/legionio/tls

OUTPUT_DIR="${1:-/etc/legionio/tls}"
DAYS=365
CA_CN="LegionIO Dev CA"
SERVER_CN="legionio-server"
CLIENT_CN="legionio-client"

mkdir -p "${OUTPUT_DIR}"

echo "Generating CA key and certificate..."
openssl genrsa -out "${OUTPUT_DIR}/ca.key" 4096
openssl req -new -x509 \
  -key "${OUTPUT_DIR}/ca.key" \
  -out "${OUTPUT_DIR}/ca.pem" \
  -days "${DAYS}" \
  -subj "/CN=${CA_CN}/O=LegionIO/OU=Dev"

echo "Generating server key and CSR..."
openssl genrsa -out "${OUTPUT_DIR}/server.key" 2048
openssl req -new \
  -key "${OUTPUT_DIR}/server.key" \
  -out "${OUTPUT_DIR}/server.csr" \
  -subj "/CN=${SERVER_CN}/O=LegionIO/OU=Dev"

echo "Signing server certificate with CA..."
openssl x509 -req \
  -in "${OUTPUT_DIR}/server.csr" \
  -CA "${OUTPUT_DIR}/ca.pem" \
  -CAkey "${OUTPUT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${OUTPUT_DIR}/server.crt" \
  -days "${DAYS}" \
  -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1")

echo "Generating client key and CSR..."
openssl genrsa -out "${OUTPUT_DIR}/client.key" 2048
openssl req -new \
  -key "${OUTPUT_DIR}/client.key" \
  -out "${OUTPUT_DIR}/client.csr" \
  -subj "/CN=${CLIENT_CN}/O=LegionIO/OU=Dev"

echo "Signing client certificate with CA..."
openssl x509 -req \
  -in "${OUTPUT_DIR}/client.csr" \
  -CA "${OUTPUT_DIR}/ca.pem" \
  -CAkey "${OUTPUT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${OUTPUT_DIR}/client.crt" \
  -days "${DAYS}"

chmod 600 "${OUTPUT_DIR}"/*.key
rm -f "${OUTPUT_DIR}"/*.csr "${OUTPUT_DIR}"/*.srl

echo ""
echo "Certificates written to ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}"
echo ""
echo "Reference these paths in settings-tls.json or your legionio settings JSON."
