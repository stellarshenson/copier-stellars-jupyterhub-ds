#!/bin/bash
# =============================================================================
# Generate self-signed certificate with custom CN and SAN entries
# =============================================================================
#
# Usage:
#   ./certs_generate.sh                                       # use certs.params (sibling file)
#   ./certs_generate.sh --cn <name> --dns-altnames <domains>  # explicit CLI args
#
# When invoked with NO arguments, sources certs.params from the same
# directory and uses CERTS_CN / CERTS_ORG / CERTS_DNS_ALTNAMES / CERTS_OUTPUT_PREFIX.
# CLI args take precedence and DISABLE the params-file fallback.
#
# Options:
#   --cn <name>                Certificate Common Name (CN)
#   --org <organization>       Certificate Organization (O). Subject is always
#                              "/O=<org>/CN=<cn>"; when --org is omitted (or
#                              CERTS_ORG is empty) ORG defaults to CN so both
#                              fields are populated and trust stores never
#                              fall back to a SAN-derived label like
#                              "localhost"
#   --dns-altnames <domains>   Comma-separated DNS SANs
#   --output-prefix <prefix>   Prefix for the cert/key output folder
#                              (default: CN lowercase, spaces to hyphens)
#   -h, --help                 Show this help message
#
# Creates:
#   <prefix>/cert.pem   - Certificate
#   <prefix>/key.pem    - Private key
#   certs.yml             - Traefik TLS configuration (fixed name; overwritten on regen)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << 'EOF'
Generate self-signed certificate with custom CN and SAN entries

Usage:
  certs_generate.sh                                       # use certs.params (sibling file)
  certs_generate.sh --cn <name> --dns-altnames <domains>  # explicit CLI args

When invoked with NO arguments, sources certs.params from the same
directory and uses CERTS_CN / CERTS_ORG / CERTS_DNS_ALTNAMES / CERTS_OUTPUT_PREFIX.
CLI args take precedence and DISABLE the params-file fallback.

Options:
  --cn <name>                Certificate Common Name (CN)
  --org <organization>       Certificate Organization (O). Subject is always
                             "/O=<org>/CN=<cn>"; if omitted, ORG defaults to CN.
  --dns-altnames <domains>   Comma-separated DNS SANs
  --output-prefix <prefix>   Prefix for the cert/key output folder
                             (default: CN lowercase, spaces to hyphens)
  -h, --help                 Show this help message

Creates:
  <script-dir>/<prefix>/cert.pem   - Certificate
  <script-dir>/<prefix>/key.pem    - Private key
  <script-dir>/certs.yml             - Traefik TLS configuration (fixed name)

Examples:
  ./certs_generate.sh
  ./certs_generate.sh --cn "DEV Certificate" --dns-altnames "*.example.com,example.com"
  ./certs_generate.sh --cn "My Cert" --dns-altnames "*.lab.local,lab.local" --output-prefix my-certs
EOF
    exit 0
}

CN=""
ORG=""
DNS_ALTNAMES=""
OUTPUT_PREFIX=""

# Show help BEFORE sourcing certs.params (so --help works even if params is malformed/missing).
for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
    esac
done

# If no CLI args at all, source certs.params (rendered by copier) for CN + altnames.
if [ $# -eq 0 ] && [ -f "$SCRIPT_DIR/certs.params" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/certs.params"
    CN="${CERTS_CN:-}"
    ORG="${CERTS_ORG:-}"
    DNS_ALTNAMES="${CERTS_DNS_ALTNAMES:-}"
    OUTPUT_PREFIX="${CERTS_OUTPUT_PREFIX:-}"
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --cn)
            CN="$2"
            shift 2
            ;;
        --org)
            ORG="$2"
            shift 2
            ;;
        --dns-altnames)
            DNS_ALTNAMES="$2"
            shift 2
            ;;
        --output-prefix)
            OUTPUT_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

if [ -z "$CN" ]; then
    echo "Error: CN is required (provide via --cn or set CERTS_CN in certs.params)"
    echo "Use --help for usage information."
    exit 1
fi

if [ -z "$DNS_ALTNAMES" ]; then
    echo "Error: DNS altnames are required (provide via --dns-altnames or set CERTS_DNS_ALTNAMES in certs.params)"
    echo "Use --help for usage information."
    exit 1
fi

# Default prefix: derived from the first DNS altname with `*` -> `_`
# (e.g. "*.localhost" -> "_.localhost", "*.lab.example.com" -> "_.lab.example.com").
# Matches the parent stellars-tech.eu pattern.
if [ -z "$OUTPUT_PREFIX" ]; then
    first_dns=$(echo "$DNS_ALTNAMES" | cut -d',' -f1 | xargs)
    OUTPUT_PREFIX="${first_dns//\*/_}"
fi

CERT_DIR="$SCRIPT_DIR/${OUTPUT_PREFIX}"
TLS_CONFIG="$SCRIPT_DIR/certs.yml"

# Build SAN string with DNS: prefixes
SAN_STRING=""
IFS=',' read -ra DOMAINS <<< "$DNS_ALTNAMES"
for domain in "${DOMAINS[@]}"; do
    domain=$(echo "$domain" | xargs)  # trim whitespace
    if [ -n "$SAN_STRING" ]; then
        SAN_STRING="${SAN_STRING},"
    fi
    SAN_STRING="${SAN_STRING}DNS:${domain}"
done

mkdir -p "$CERT_DIR"

# Build subject DN. ORG defaults to CN when empty so the subject is always
# "/O=.../CN=..." - both fields populated, so whichever one the trust store
# picks for display, it shows a meaningful name (never a SAN-derived "localhost").
if [ -z "$ORG" ]; then
    ORG="$CN"
fi
SUBJECT="/O=$ORG/CN=$CN"

echo "Generating certificate:"
echo "  Subject: $SUBJECT"
echo "  SANs:    $DNS_ALTNAMES"
echo "  Certs:   $CERT_DIR"
echo "  TLS:     $TLS_CONFIG"
echo ""

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_DIR/key.pem" \
    -out "$CERT_DIR/cert.pem" \
    -subj "$SUBJECT" \
    -addext "subjectAltName=$SAN_STRING"

# Generate Traefik TLS configuration
cat > "$TLS_CONFIG" << EOF
# TLS Configuration for: $CN
# Import cert.pem to browser for trusted HTTPS

tls:
  certificates:
    - certFile: /certs/${OUTPUT_PREFIX}/cert.pem
      keyFile: /certs/${OUTPUT_PREFIX}/key.pem

  stores:
    default:
      defaultCertificate:
        certFile: /certs/${OUTPUT_PREFIX}/cert.pem
        keyFile: /certs/${OUTPUT_PREFIX}/key.pem
EOF

echo "Certificate generated:"
openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject -dates -ext subjectAltName

echo ""
echo "Key verified:"
openssl rsa -in "$CERT_DIR/key.pem" -check -noout
