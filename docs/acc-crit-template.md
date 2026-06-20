# Acceptance Criteria - Template (copier-stellars-jupyterhub-ds)

Copier template that scaffolds a thin deployment overlay for the upstream stellars-jupyterhub-ds hub. Criteria cover the copier interview, the rendered overlay (compose_override, env, start/stop, CIFS, certs) and the merge against the downloaded upstream compose.yml. The pytest suite under `tests/` checks most of these against fresh renders - run `pytest`. Renders use a non-git copy of the working tree because copier renders from the latest git tag, not the dirty tree.

## Interview (copier.yml)

- [x] **Single hostname question** - one `base_hostname` prompt; no second competing hostname question
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Addressing** - `network_addressing` offers dns|ip; ip mode adds an IPv4 validator on `base_hostname`
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Subdomain default** - `jupyterhub_subdomain` default is `hub`
  - log: 2026-06-20 changed jupyterhub -> hub (v2.0.0)
- [x] **Slug/prefix validators** - `project_slug` allows lowercase/digit/_/- only; `branding_prefix` lowercase/digit/_ only
  - log: 2026-06-20 confirmed (v2.0.0)

## Subdomain as single value or list

- [x] **List input** - `jupyterhub_subdomain` accepts a single subdomain or a comma-separated list; help text states a list is valid
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Normalize** - each list item is whitespace-stripped and lowercased before use
  - log: 2026-06-20 implemented via split/trim/lower (v2.0.0)
- [x] **Drop empties** - blank items (trailing comma, double comma) are dropped
  - log: 2026-06-20 implemented via `select` filter (v2.0.0)
- [x] **Dedupe** - repeated subdomains collapse to a single matcher
  - log: 2026-06-20 implemented via `unique` filter (v2.0.0)
- [x] **Primary** - first list item is primary: drives `JUPYTERHUB_HOSTNAME_PREFIX`, the canonical access URL and the post-copy banner
  - log: 2026-06-20 implemented (v2.0.0)
- [x] **Traefik per-subdomain** - hub router rule emits one `Host()` matcher per configured subdomain (dns: `<sub>.<base>` plus `<sub>.localhost` when base != localhost)
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **No fixed aliases** - rule routes only the configured subdomains; no hardcoded hub/jupyterhub/duoptimum-hub aliases (host or localhost regex)
  - log: 2026-06-20 implemented; retired the v2.0.0 fixed alias set (v2.0.0)
- [x] **Cert covers every subdomain** - each `<sub>.<base>` and `<sub>.localhost` is a SAN, via `cert_dns_altnames` -> certs.params -> generated cert
  - log: 2026-06-20 implemented + pytest asserts SANs (v2.0.0)
- [x] **Edge: empty subdomain** - blank value serves at the root host; no subdomain matcher, `JUPYTERHUB_HOSTNAME_PREFIX` empty
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Edge: single value** - one subdomain, no comma, behaves as a one-subdomain deployment
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Edge: ip mode + list** - subdomains apply only to the localhost side; the bare IP stays the network root URL
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Edge: list all-blank** - value of only commas/whitespace collapses to empty -> root host
  - log: 2026-06-20 implemented (v2.0.0)

## Compose override (compose_override.yml.jinja)

- [x] **Deltas only** - override repeats only changed keys; base image/ports/volumes/healthcheck/networks inherited
  - log: 2026-06-20 reworked to new hub model (v2.0.0)
- [x] **Traefik slim** - traefik carries `command` + `labels` only; no image/ports/volumes/networks/restart
  - log: 2026-06-20 (v2.0.0)
- [x] **No cert bind** - traefik does NOT bind-mount `./certs`; inherits base `hub_certs:/certs` (hub-provisioned)
  - log: 2026-06-20 dropped ./certs:/certs:ro double-mount (v2.0.0)
- [x] **Hub network** - hub inherits base `hub_network`; no `jupyterhub_network`, no `ports: []` no-op
  - log: 2026-06-20 (v2.0.0)
- [x] **Idle culler** - when enabled, `JUPYTERHUB_IDLE_CULLER_MAX_EXTENSION_MINUTES=2880` (48h)
  - log: 2026-06-20 renamed from _EXTENSION hours (v2.0.0)
- [x] **Hub schema** - hub service block is `hub:`; router/service/middleware are `hub-rtr`/`hub-svc`/`hub-ratelimit` (matches upstream rename); override replaces base `hub-rtr` rule + middleware in place by key
  - log: 2026-06-20 (v2.0.0)
  - log: 2026-06-21 renamed `duoptimum-hub` -> `hub` to track upstream new schema; key match is what lets the override replace the base Path rule with the Host rule
- [x] **Middlewares** - hub router middleware chain is `hub-ratelimit` only; hub-alias-redirect dropped (base_url=/)
  - log: 2026-06-20 (v2.0.0)
  - log: 2026-06-21 renamed `duoptimum-hub-ratelimit` -> `hub-ratelimit`
- [x] **Dashboard route** - traefik dashboard routes `traefik.<base>` plus `traefik.localhost`
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Namespace constraint** - traefik docker provider scoped to `Label(com.docker.compose.project, ${COMPOSE_PROJECT_NAME:-duoptimum-hub})`; foreign stacks' routers don't leak in (matches base compose default)
  - log: 2026-06-20 back-ported from live deployment (v2.0.0)
- [x] **Dashboard toggle** - `--api.dashboard=${TRAEFIK_DASHBOARD_ENABLED:-true}`; host-routed (no basePath) so `false` 404s both UI and API; open by default
  - log: 2026-06-20 back-ported from live deployment (v2.0.0)
- [x] **Hub name** - `JUPYTERHUB_BRANDING_HUB_NAME={{ project_name }}` sets the portal brand-icon tooltip + login/signup text (else upstream default)
  - log: 2026-06-20 back-ported from live deployment (v2.0.0)
  - log: 2026-06-21 fixed `JUPYTERHUB_HUB_NAME` -> `JUPYTERHUB_BRANDING_HUB_NAME`; upstream `jupyterhub_config.py` reads only the `BRANDING_` key, so the old name silently fell back to the default (adversarial sweep)
- [x] **Splash icon** - `JUPYTERHUB_BRANDING_LAB_SPLASH_ICON_URI` set to `{{ branding_prefix }}_jl_logo.svg` (matches main lab icon)
  - log: 2026-06-21 added to track upstream new branding key
- [x] **No watchtower/networks block** - override declares no watchtower service and no top-level networks block
  - log: 2026-06-20 (v2.0.0)

## Traefik port and HTTP redirect

- [x] **HTTPS port question** - `traefik_https_port` (int, default 443, 1-65535 validator); help notes 8443 as the common alternative
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Port wiring** - env.default sets `TRAEFIK_HTTPS_PORT`; override publishes `${TRAEFIK_HTTPS_PORT:-443}:443` via `ports: !override` (replaces the base ports list)
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Redirect option** - `http_redirect` (bool, default true); port 80 fixed, not re-portable
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Redirect on** - publishes `80:80`, keeps the web entrypoint + http-catchall redirect; redirect targets the configured HTTPS port when non-443
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Redirect off** - only the HTTPS port published; no port 80, no web entrypoint, no redirect middleware
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **URL display** - post-copy banner + README URLs carry `:<port>` when non-443
  - log: 2026-06-20 implemented (v2.0.0)

## CIFS overlay (conditional)

- [x] **Conditional file** - compose_cifs.yml rendered only when `cifs_shared_mount`
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Overrides hub_shared** - CIFS volume key is `hub_shared` so the driver override lands on the base shared volume
  - log: 2026-06-20 fixed from jupyterhub_shared no-op (v2.0.0)
- [x] **Start/stop wiring** - start.sh and stop.sh add `-f compose_cifs.yml` only when ENABLE_CIFS=1
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Edge: cifs off** - no compose_cifs.yml, no ENABLE_CIFS line in env.default
  - log: 2026-06-20 confirmed (v2.0.0)

## TLS / certs

- [x] **Self-signed bootstrap** - start.sh generates certs/certs.yml on first run when missing; cert gen also runs as a copier _task on copy
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Subject** - cert subject is `/O=<org>/CN=<cn>`; ORG defaults to CN when empty
  - log: 2026-06-20 confirmed (v1.1.3)
- [x] **SAN enumeration** - no single-label wildcards; SANs enumerate the configured names plus localhost-side equivalents
  - log: 2026-06-20 confirmed (v1.0.22)
- [x] **Params channel** - subdomains/base flow `cert_dns_altnames` -> `certs/certs.params` (CERTS_DNS_ALTNAMES) -> certs_generate.sh -> openssl SANs
  - log: 2026-06-20 confirmed (v2.0.0)
- [x] **Cert content matches** - generated cert subject CN == CERTS_CN, carries an Organization, and DNS SANs == CERTS_DNS_ALTNAMES exactly
  - log: 2026-06-20 pytest parses the cert with `cryptography` (v2.0.0)
- [x] **Cert files + folder** - certs.yml references `/certs/<first-san>/cert.pem` + key.pem; both exist on disk; cert/key public keys match
  - log: 2026-06-20 pytest (v2.0.0)
- [x] **Idempotent** - re-render does not regenerate (re-key) an existing cert
  - log: 2026-06-20 pytest checks certs.yml mtime unchanged (v2.0.0)

## Env files

- [x] **Prefix var** - env.default and start.sh use `JUPYTERHUB_HOSTNAME_PREFIX`
  - log: 2026-06-20 renamed from JUPYTERHUB_PREFIX (v2.0.0)
- [x] **Tracked vs override** - env.default tracked; .env gitignored and `_skip_if_exists`; .env wins at runtime
  - log: 2026-06-20 confirmed (v2.0.0)

## Merge validation

- [x] **Render from local folder** - validate against a non-git copy of the working tree (copier uses tags, not the dirty tree)
  - log: 2026-06-20 method confirmed (v2.0.0)
- [x] **compose config exit 0** - `docker compose -f compose.yml -f compose_override.yml [-f compose_cifs.yml] config` exits 0
  - log: 2026-06-20 default/dns+cifs/ip+cifs/live-answers all pass (v2.0.0)
- [x] **Network sanity** - merged config has hub_network, zero jupyterhub_network
  - log: 2026-06-20 (v2.0.0)
- [x] **Cert sanity** - merged traefik `/certs` source is the `hub_certs` volume, no `./certs` bind
  - log: 2026-06-20 (v2.0.0)
- [x] **CIFS sanity** - merged `hub_shared` carries the cifs driver_opts
  - log: 2026-06-20 (v2.0.0)

## Tests (pytest)

- [x] **Suite** - `pytest` renders the working tree (non-git snapshot) per scenario and asserts on the rendered overlay; config in pyproject.toml `[tool.pytest.ini_options]`
  - log: 2026-06-20 converted from bash to pytest (v2.0.0)
- [x] **Scenarios** - defaults, multi-subdomain+8443, ip+list, with-cifs, root-no-subdomain, no-http-redirect
  - log: 2026-06-20 (v2.0.0)
- [x] **Cert assertions** - SANs, subject CN+O, prefix folder, certs.yml refs, cert/key match parsed via `cryptography`
  - log: 2026-06-20 (v2.0.0)
- [x] **Branding cleanup** - operator-replacement task covered (per-extension, prefix-other-extension)
  - log: 2026-06-20 ported to pytest (v2.0.0)
- [x] **CI** - validate-template.yml installs `.[test]` and runs pytest on push/PR
  - log: 2026-06-20 simplified from the bash matrix (v2.0.0)
- [x] **Tools download** - asserts rendered `tools/docker-volume-toolkit/docker_volume_toolkit.py` exists + executable; skips when offline
  - log: 2026-06-20 added with the migrator extraction (v2.0.0)

## Tools download (docker-volume-toolkit)

The volume migrator is its own repo (`stellarshenson/docker-volume-toolkit`), tracked as a submodule under `extra/` in this template (not rendered) and downloaded fresh into a rendered deployment's `tools/` folder by a copier `_task`.

- [x] **Standalone repo** - migrator extracted to public `stellarshenson/docker-volume-toolkit` (docker_volume_toolkit.py + README + MIT LICENSE)
  - log: 2026-06-20 created via REST API, pushed (v2.0.0)
- [x] **Submodule in extra/** - tracked at `extra/docker-volume-toolkit`; outside `_subdirectory: template` so never rendered into a deployment
  - log: 2026-06-20 replaced the in-tree `extra/volumes-migrator/` dir (v2.0.0)
- [x] **Download task** - copier `_task` fetches the repo `main` tarball into `tools/docker-volume-toolkit` on every render (copy + update)
  - log: 2026-06-20 implemented + pytest (v2.0.0)
- [x] **Latest, not pinned** - rendered `tools/` comes from GitHub at render time, independent of the template tag and the submodule pin
  - log: 2026-06-20 (v2.0.0)
- [x] **Executable** - rendered `tools/docker-volume-toolkit/docker_volume_toolkit.py` keeps the executable bit
  - log: 2026-06-20 pytest asserts os.X_OK (v2.0.0)
- [x] **Gitignored** - rendered `.gitignore` ignores `/tools/` (downloaded, not edited locally)
  - log: 2026-06-20 (v2.0.0)
- [x] **Structure** - rendered README Structure block lists `tools/docker-volume-toolkit`
  - log: 2026-06-20 (v2.0.0)
- [x] **Edge: offline** - download failure logs a NOTE and leaves `tools/` as-is; render still exits 0
  - log: 2026-06-20 non-fatal else-branch; pytest skips when absent (v2.0.0)

## Versioning / release

- [x] **Version source** - pyproject.toml version bumped per change; major bump for breaking renames
  - log: 2026-06-20 bumped 1.1.3 -> 2.0.0 (v2.0.0)
- [x] **Existing answers honoured** - a prior deployment's answers (e.g. jupyterhub_subdomain: jupyterhub) still render cleanly on update
  - log: 2026-06-20 live-answers render verified (v2.0.0)
- [ ] **Tag to ship** - copier-update consumers pick up changes only from the latest git tag; a release needs an annotated tag
  - log: 2026-06-20 v2.0.0 committed, tag deferred until requested
