#!/bin/bash
# Integration test for a rendered Copier overlay.
#
# Usage: tests/test_render.sh <render_dir>
#
# Expected values for the assertions are read from these environment
# variables (set by the caller / CI matrix). Anything not set is skipped
# unless it has a deterministic default the template always emits.
#
#   EXPECTED_PROJECT_NAME         e.g. "My JupyterHub"
#   EXPECTED_PROJECT_SLUG         e.g. "my-jupyterhub"
#   EXPECTED_BRANDING_PREFIX      e.g. "my_jupyterhub"
#   EXPECTED_BASE_HOSTNAME        e.g. "localhost"
#   EXPECTED_NETWORK_ADDRESSING   "dns" or "ip"
#   EXPECTED_ADMIN_USERNAME       e.g. "admin"
#   EXPECTED_SIGNUP_ENABLED       "0" or "1"
#   EXPECTED_CIFS_ENABLED         "true" or "false"
#   EXPECTED_CERT_CN              e.g. "MY JUPYTERHUB Certificate"
#   EXPECTED_CERT_SANS            comma-separated, e.g. "*.localhost,localhost"
#   EXPECTED_CERT_PREFIX          e.g. "_.localhost" (first SAN with * -> _)

set -e

RENDER="${1:?usage: $0 <render_dir>}"
cd "$RENDER"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

fail() { echo "${RED}FAIL${NC}: $*" >&2; exit 1; }
ok()   { echo "${GREEN}OK${NC}: $*"; }
skip() { echo "${YELLOW}SKIP${NC}: $*"; }

# ---------------------------------------------------------------------------
# 1. Static file structure
# ---------------------------------------------------------------------------
for f in start.sh stop.sh compose_override.yml env.default .env README.md \
         certs/certs.params certs/certs_generate.sh certs/certs.yml \
         certs/certs_install.sh certs/certs_install.bat certs/README.md \
         .copier-answers.yml; do
    test -f "$f" || fail "$f missing"
done
test -x certs/certs_install.sh || fail "certs/certs_install.sh not executable"
test -d branding || fail "branding/ missing"
ok "static structure present"

# ---------------------------------------------------------------------------
# 1a. .copier-answers.yml records the answers we provided
# ---------------------------------------------------------------------------
ans=.copier-answers.yml
# Check each expected value is recorded in the answers file. The file is
# written as YAML with `key: value` lines (or quoted values for strings
# containing special chars), so a flexible grep pattern works.
check_answer() {
    local key="$1" expected="$2"
    [[ -z "$expected" ]] && return 0
    grep -E "^${key}:[[:space:]]+['\"]?${expected}['\"]?$" "$ans" >/dev/null \
        || fail "$ans: '$key' != '$expected' (got: $(grep "^${key}:" "$ans" || echo missing))"
}
check_answer project_name        "${EXPECTED_PROJECT_NAME:-}"
check_answer project_slug        "${EXPECTED_PROJECT_SLUG:-}"
check_answer branding_prefix     "${EXPECTED_BRANDING_PREFIX:-}"
check_answer base_hostname       "${EXPECTED_BASE_HOSTNAME:-}"
check_answer network_addressing  "${EXPECTED_NETWORK_ADDRESSING:-}"
check_answer admin_username      "${EXPECTED_ADMIN_USERNAME:-}"
# bool answers in YAML are unquoted true/false
[[ -n "${EXPECTED_CIFS_ENABLED:-}" ]] \
    && (grep -E "^cifs_shared_mount:[[:space:]]+${EXPECTED_CIFS_ENABLED}$" "$ans" >/dev/null \
        || fail "$ans cifs_shared_mount != $EXPECTED_CIFS_ENABLED")
ok ".copier-answers.yml records the rendered answers"

# ---------------------------------------------------------------------------
# 2. Branding files use the rendered prefix
# ---------------------------------------------------------------------------
if [[ -n "${EXPECTED_BRANDING_PREFIX:-}" ]]; then
    test -f "branding/${EXPECTED_BRANDING_PREFIX}_jh_logo.png" \
        || fail "branding/${EXPECTED_BRANDING_PREFIX}_jh_logo.png missing"
    test -f "branding/${EXPECTED_BRANDING_PREFIX}_jl_logo.svg" \
        || fail "branding/${EXPECTED_BRANDING_PREFIX}_jl_logo.svg missing"
    test -f "branding/${EXPECTED_BRANDING_PREFIX}_favicon.ico" \
        || fail "branding/${EXPECTED_BRANDING_PREFIX}_favicon.ico missing"
    ok "branding files use prefix '${EXPECTED_BRANDING_PREFIX}'"
else
    skip "EXPECTED_BRANDING_PREFIX unset; not asserting branding filenames"
fi

# ---------------------------------------------------------------------------
# 3. Compose URIs reference the rendered branding files (consistency)
# ---------------------------------------------------------------------------
for var in JUPYTERHUB_LOGO_URI JUPYTERHUB_FAVICON_URI JUPYTERHUB_LAB_MAIN_ICON_URI; do
    line=$(grep -E "^[[:space:]]*-[[:space:]]*${var}=" compose_override.yml) \
        || fail "compose missing $var"
    uri=$(echo "$line" | sed -E "s/^[[:space:]]*-[[:space:]]*${var}=//")
    uri=$(echo "$uri" | awk '{print $1}')
    filename=${uri#file:///srv/branding/}
    test -f "branding/$filename" \
        || fail "$var=$uri but branding/$filename does not exist"
    if [[ -n "${EXPECTED_BRANDING_PREFIX:-}" ]]; then
        case "$var" in
            JUPYTERHUB_LOGO_URI)
                [[ "$filename" = "${EXPECTED_BRANDING_PREFIX}_jh_logo.png" ]] \
                    || fail "$var filename '$filename' != '${EXPECTED_BRANDING_PREFIX}_jh_logo.png'"
                ;;
            JUPYTERHUB_LAB_MAIN_ICON_URI)
                [[ "$filename" = "${EXPECTED_BRANDING_PREFIX}_jl_logo.svg" ]] \
                    || fail "$var filename '$filename' != '${EXPECTED_BRANDING_PREFIX}_jl_logo.svg'"
                ;;
            JUPYTERHUB_FAVICON_URI)
                [[ "$filename" = "${EXPECTED_BRANDING_PREFIX}_favicon.ico" ]] \
                    || fail "$var filename '$filename' != '${EXPECTED_BRANDING_PREFIX}_favicon.ico'"
                ;;
        esac
    fi
done
ok "compose branding URIs reference correct files"

# ---------------------------------------------------------------------------
# 4. JupyterLab system name and admin
# ---------------------------------------------------------------------------
if [[ -n "${EXPECTED_PROJECT_NAME:-}" ]]; then
    grep -F "JUPYTERLAB_SYSTEM_NAME=$EXPECTED_PROJECT_NAME" compose_override.yml \
        >/dev/null \
        || fail "JUPYTERLAB_SYSTEM_NAME != '$EXPECTED_PROJECT_NAME'"
    ok "JUPYTERLAB_SYSTEM_NAME = $EXPECTED_PROJECT_NAME"
fi
if [[ -n "${EXPECTED_ADMIN_USERNAME:-}" ]]; then
    grep -F "JUPYTERHUB_ADMIN=$EXPECTED_ADMIN_USERNAME" compose_override.yml \
        >/dev/null \
        || fail "JUPYTERHUB_ADMIN != '$EXPECTED_ADMIN_USERNAME'"
    ok "JUPYTERHUB_ADMIN = $EXPECTED_ADMIN_USERNAME"
fi

# ---------------------------------------------------------------------------
# 5. Admin password pass-through
# ---------------------------------------------------------------------------
grep -F 'JUPYTERHUB_ADMIN_PASSWORD=${JUPYTERHUB_ADMIN_PASSWORD:-}' \
    compose_override.yml >/dev/null \
    || fail "JUPYTERHUB_ADMIN_PASSWORD pass-through missing"
ok "admin password pass-through present"

# ---------------------------------------------------------------------------
# 6. Signup toggle reflects copier answer
# ---------------------------------------------------------------------------
if [[ -n "${EXPECTED_SIGNUP_ENABLED:-}" ]]; then
    grep -F "JUPYTERHUB_SIGNUP_ENABLED=$EXPECTED_SIGNUP_ENABLED" \
        compose_override.yml >/dev/null \
        || fail "JUPYTERHUB_SIGNUP_ENABLED != '$EXPECTED_SIGNUP_ENABLED'"
    ok "JUPYTERHUB_SIGNUP_ENABLED = $EXPECTED_SIGNUP_ENABLED"
fi

# ---------------------------------------------------------------------------
# 7. CIFS conditional rendering
# ---------------------------------------------------------------------------
if [[ -n "${EXPECTED_CIFS_ENABLED:-}" ]]; then
    if [[ "$EXPECTED_CIFS_ENABLED" = "true" ]]; then
        test -f compose_cifs.yml \
            || fail "EXPECTED_CIFS_ENABLED=true but compose_cifs.yml missing"
    else
        test ! -f compose_cifs.yml \
            || fail "EXPECTED_CIFS_ENABLED=false but compose_cifs.yml exists"
    fi
    ok "CIFS conditional matches EXPECTED_CIFS_ENABLED=$EXPECTED_CIFS_ENABLED"
fi

# ---------------------------------------------------------------------------
# 8. Volume mounts
# ---------------------------------------------------------------------------
grep -F "./certs:/certs:ro" compose_override.yml >/dev/null \
    || fail "compose missing certs volume mount"
grep -F "./branding:/srv/branding:ro" compose_override.yml >/dev/null \
    || fail "compose missing branding volume mount"
ok "both volume mounts present"

# ---------------------------------------------------------------------------
# 9. Cert content matches certs.params
# ---------------------------------------------------------------------------
# shellcheck disable=SC1091
source certs/certs.params
test -n "$CERTS_CN"          || fail "certs.params: CERTS_CN empty"
test -n "$CERTS_DNS_ALTNAMES" || fail "certs.params: CERTS_DNS_ALTNAMES empty"

if [[ -n "${EXPECTED_CERT_CN:-}" ]]; then
    test "$CERTS_CN" = "$EXPECTED_CERT_CN" \
        || fail "certs.params CERTS_CN '$CERTS_CN' != expected '$EXPECTED_CERT_CN'"
fi
if [[ -n "${EXPECTED_CERT_SANS:-}" ]]; then
    test "$CERTS_DNS_ALTNAMES" = "$EXPECTED_CERT_SANS" \
        || fail "certs.params CERTS_DNS_ALTNAMES '$CERTS_DNS_ALTNAMES' != expected '$EXPECTED_CERT_SANS'"
fi

cert_file=$(ls certs/*/cert.pem)
key_file=$(ls certs/*/key.pem)

subject=$(openssl x509 -in "$cert_file" -noout -subject)
echo "$subject" | grep -F "CN = $CERTS_CN" >/dev/null \
    || fail "cert subject != CERTS_CN ($subject)"

sans=$(openssl x509 -in "$cert_file" -noout -ext subjectAltName)
IFS=',' read -ra altnames <<< "$CERTS_DNS_ALTNAMES"
for san in "${altnames[@]}"; do
    san_trimmed=$(echo "$san" | xargs)
    echo "$sans" | grep -F "DNS:$san_trimmed" >/dev/null \
        || fail "cert SANs missing '$san_trimmed' (got: $sans)"
done
ok "cert subject + every SAN match certs.params"

# ---------------------------------------------------------------------------
# 10. Cert prefix folder derivation
# ---------------------------------------------------------------------------
first_dns=$(echo "$CERTS_DNS_ALTNAMES" | cut -d',' -f1 | xargs)
expected_prefix="${first_dns//\*/_}"
prefix_dir=$(basename "$(dirname "$cert_file")")
test "$prefix_dir" = "$expected_prefix" \
    || fail "cert prefix '$prefix_dir' != derived '$expected_prefix' (first altname '$first_dns')"
if [[ -n "${EXPECTED_CERT_PREFIX:-}" ]]; then
    test "$prefix_dir" = "$EXPECTED_CERT_PREFIX" \
        || fail "cert prefix '$prefix_dir' != EXPECTED_CERT_PREFIX '$EXPECTED_CERT_PREFIX'"
fi
ok "cert folder prefix '$prefix_dir' derived from first altname"

# ---------------------------------------------------------------------------
# 11. certs.yml internal references resolve
# ---------------------------------------------------------------------------
grep -F "/certs/$prefix_dir/cert.pem" certs/certs.yml >/dev/null \
    || fail "certs.yml missing /certs/$prefix_dir/cert.pem"
grep -F "/certs/$prefix_dir/key.pem" certs/certs.yml >/dev/null \
    || fail "certs.yml missing /certs/$prefix_dir/key.pem"
test -f "certs/$prefix_dir/cert.pem" || fail "certs.yml cert path not on disk"
test -f "certs/$prefix_dir/key.pem"  || fail "certs.yml key path not on disk"
ok "certs.yml paths resolve to real files"

# ---------------------------------------------------------------------------
# 12. cert/key pair match
# ---------------------------------------------------------------------------
cert_mod=$(openssl x509 -in "$cert_file" -noout -modulus | openssl md5)
key_mod=$(openssl rsa -in "$key_file" -noout -modulus 2>/dev/null | openssl md5)
test "$cert_mod" = "$key_mod" || fail "cert/key modulus mismatch"
ok "cert/key pair modulus match"

# ---------------------------------------------------------------------------
# 13. env.default values match copier answers
# ---------------------------------------------------------------------------
if [[ -n "${EXPECTED_PROJECT_SLUG:-}" ]]; then
    grep -F "COMPOSE_PROJECT_NAME=$EXPECTED_PROJECT_SLUG" env.default >/dev/null \
        || fail "env.default COMPOSE_PROJECT_NAME != '$EXPECTED_PROJECT_SLUG'"
    ok "env.default COMPOSE_PROJECT_NAME = $EXPECTED_PROJECT_SLUG"
fi
if [[ -n "${EXPECTED_BASE_HOSTNAME:-}" ]]; then
    grep -F "BASE_HOSTNAME=$EXPECTED_BASE_HOSTNAME" env.default >/dev/null \
        || fail "env.default BASE_HOSTNAME != '$EXPECTED_BASE_HOSTNAME'"
    ok "env.default BASE_HOSTNAME = $EXPECTED_BASE_HOSTNAME"
fi

echo ""
echo "${GREEN}===== all integration assertions passed =====${NC}"
