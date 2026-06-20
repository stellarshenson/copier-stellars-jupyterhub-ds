"""Integration tests for a rendered copier overlay.

Each scenario renders the template with a set of copier answers and asserts on
the rendered files: structure, branding, compose override (routing, ports,
http-redirect), CIFS conditional, env values, and the generated self-signed
cert (subject, SANs, key match). The cert is parsed with `cryptography` rather
than scraping openssl text.
"""

import os

import pytest
import yaml
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from cryptography.x509.oid import ExtensionOID, NameOID

SCENARIOS = {
    "defaults": dict(
        data={},
        project_name="My JupyterHub", project_slug="my-jupyterhub",
        branding_prefix="my_jupyterhub", base_hostname="localhost",
        network_addressing="dns", admin_username="admin", signup_enabled="0",
        cifs=False, cert_cn="MY JUPYTERHUB Certificate",
        sans=["hub.localhost", "localhost", "traefik.localhost"],
        cert_prefix="hub.localhost", subdomains=["hub"],
        https_port="443", http_redirect=True,
    ),
    "multi-subdomain-port": dict(
        data={"project_name": "ACME AI Lab", "base_hostname": "lab.acme.example",
              "jupyterhub_subdomain": "hub, JupyterHub , hub",
              "traefik_https_port": "8443"},
        project_name="ACME AI Lab", project_slug="acme-ai-lab",
        branding_prefix="acme_ai_lab", base_hostname="lab.acme.example",
        network_addressing="dns", admin_username="admin", signup_enabled="0",
        cifs=False, cert_cn="ACME AI LAB Certificate",
        sans=["hub.lab.acme.example", "jupyterhub.lab.acme.example",
              "lab.acme.example", "traefik.lab.acme.example", "hub.localhost",
              "jupyterhub.localhost", "localhost", "traefik.localhost"],
        cert_prefix="hub.lab.acme.example", subdomains=["hub", "jupyterhub"],
        https_port="8443", http_redirect=True,
    ),
    "ip-list": dict(
        data={"network_addressing": "ip", "base_hostname": "192.168.1.50",
              "jupyterhub_subdomain": "hub, jupyterhub"},
        project_name="My JupyterHub", project_slug="my-jupyterhub",
        branding_prefix="my_jupyterhub", base_hostname="192.168.1.50",
        network_addressing="ip", admin_username="admin", signup_enabled="0",
        cifs=False, cert_cn="MY JUPYTERHUB Certificate",
        sans=["192.168.1.50", "hub.localhost", "jupyterhub.localhost",
              "localhost", "traefik.localhost"],
        cert_prefix="192.168.1.50", subdomains=["hub", "jupyterhub"],
        https_port="443", http_redirect=True,
    ),
    "with-cifs": dict(
        data={"cifs_shared_mount": "true"},
        project_name="My JupyterHub", project_slug="my-jupyterhub",
        branding_prefix="my_jupyterhub", base_hostname="localhost",
        network_addressing="dns", admin_username="admin", signup_enabled="0",
        cifs=True, cert_cn="MY JUPYTERHUB Certificate",
        sans=["hub.localhost", "localhost", "traefik.localhost"],
        cert_prefix="hub.localhost", subdomains=["hub"],
        https_port="443", http_redirect=True,
    ),
    "root-no-subdomain": dict(
        data={"base_hostname": "lab.acme.example", "jupyterhub_subdomain": ""},
        project_name="My JupyterHub", project_slug="my-jupyterhub",
        branding_prefix="my_jupyterhub", base_hostname="lab.acme.example",
        network_addressing="dns", admin_username="admin", signup_enabled="0",
        cifs=False, cert_cn="MY JUPYTERHUB Certificate",
        sans=["lab.acme.example", "traefik.lab.acme.example", "localhost",
              "traefik.localhost"],
        cert_prefix="lab.acme.example", subdomains=[],
        https_port="443", http_redirect=True,
    ),
    "no-http-redirect": dict(
        data={"http_redirect": "false"},
        project_name="My JupyterHub", project_slug="my-jupyterhub",
        branding_prefix="my_jupyterhub", base_hostname="localhost",
        network_addressing="dns", admin_username="admin", signup_enabled="0",
        cifs=False, cert_cn="MY JUPYTERHUB Certificate",
        sans=["hub.localhost", "localhost", "traefik.localhost"],
        cert_prefix="hub.localhost", subdomains=["hub"],
        https_port="443", http_redirect=False,
    ),
}


@pytest.fixture(scope="session", params=list(SCENARIOS), ids=list(SCENARIOS))
def rendered(request, template_src, do_render, tmp_path_factory):
    """Render one scenario once per session; shared across the assertions."""
    sc = SCENARIOS[request.param]
    dst = tmp_path_factory.mktemp("r_" + request.param.replace("-", "_"))
    do_render(template_src, dst, sc["data"])
    return dst, sc


# --- helpers ---------------------------------------------------------------

def read_params(render_dir):
    params = {}
    for line in (render_dir / "certs" / "certs.params").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        params[key.strip()] = val.strip().strip('"')
    return params


def override(render_dir):
    return (render_dir / "compose_override.yml").read_text()


def hub_rule(render_dir):
    for line in override(render_dir).splitlines():
        if "duoptimum-hub-rtr.rule=" in line:
            return line
    raise AssertionError("hub router rule not found in compose_override.yml")


def _pub(key):
    return key.public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


# --- tests -----------------------------------------------------------------

REQUIRED = [
    "start.sh", "stop.sh", "compose_override.yml", "env.default", ".env",
    "README.md", "certs/certs.params", "certs/certs_generate.sh",
    "certs/certs.yml", "certs/certs_install.sh", "certs/certs_install.bat",
    "certs/README.md", ".copier-answers.yml",
]


def test_structure(rendered):
    d, _ = rendered
    for f in REQUIRED:
        assert (d / f).is_file(), f"{f} missing"
    assert (d / "branding").is_dir()
    assert os.access(d / "certs" / "certs_install.sh", os.X_OK)


def test_answers_recorded(rendered):
    d, sc = rendered
    ans = yaml.safe_load((d / ".copier-answers.yml").read_text())
    assert ans["project_slug"] == sc["project_slug"]
    assert ans["base_hostname"] == sc["base_hostname"]
    assert ans["network_addressing"] == sc["network_addressing"]
    assert ans["cifs_shared_mount"] is sc["cifs"]
    assert str(ans["traefik_https_port"]) == sc["https_port"]
    assert ans["http_redirect"] is sc["http_redirect"]


def test_branding(rendered):
    d, sc = rendered
    p = sc["branding_prefix"]
    for fn in (f"{p}_jh_logo.png", f"{p}_jl_logo.svg", f"{p}_favicon.ico"):
        assert (d / "branding" / fn).is_file()
    text = override(d)
    for fn in (f"{p}_jh_logo.png", f"{p}_favicon.ico", f"{p}_jl_logo.svg"):
        assert f"file:///srv/branding/{fn}" in text


def test_compose_identity(rendered):
    d, sc = rendered
    text = override(d)
    assert f"JUPYTERLAB_SYSTEM_NAME={sc['project_name']}" in text
    assert f"JUPYTERHUB_ADMIN={sc['admin_username']}" in text
    assert "JUPYTERHUB_ADMIN_PASSWORD=${JUPYTERHUB_ADMIN_PASSWORD:-}" in text
    assert f"JUPYTERHUB_SIGNUP_ENABLED={sc['signup_enabled']}" in text
    assert "JUPYTERHUB_IDLE_CULLER_MAX_EXTENSION_MINUTES=2880" in text


def test_cert_mount_model(rendered):
    d, _ = rendered
    text = override(d)
    assert "./branding:/srv/branding:ro" in text
    # v2.0: the hub provisions certs into hub_certs; traefik must not bind ./certs
    assert "./certs:/certs" not in text


def test_cifs(rendered):
    d, sc = rendered
    cifs = d / "compose_cifs.yml"
    env = (d / "env.default").read_text()
    if sc["cifs"]:
        assert cifs.is_file()
        text = cifs.read_text()
        assert "hub_shared:" in text
        assert "jupyterhub_shared:" not in text
        assert "ENABLE_CIFS=0" in env
    else:
        assert not cifs.exists()
        assert "ENABLE_CIFS" not in env


def test_env(rendered):
    d, sc = rendered
    lines = (d / "env.default").read_text().splitlines()
    assert f"COMPOSE_PROJECT_NAME={sc['project_slug']}" in lines
    assert f"BASE_HOSTNAME={sc['base_hostname']}" in lines
    prefix = f"{sc['subdomains'][0]}." if sc["subdomains"] else ""
    assert f"JUPYTERHUB_HOSTNAME_PREFIX={prefix}" in lines
    assert f"TRAEFIK_HTTPS_PORT={sc['https_port']}" in lines


def test_ports_and_redirect(rendered):
    d, sc = rendered
    text = override(d)
    assert "ports: !override" in text
    assert "${TRAEFIK_HTTPS_PORT:-443}:443" in text
    if sc["http_redirect"]:
        assert '"80:80"' in text
        assert "--entrypoints.web.address=:80" in text
        assert "redirect-to-https.redirectscheme.scheme=https" in text
        if sc["https_port"] != "443":
            assert f"redirect-to-https.redirectscheme.port={sc['https_port']}" in text
    else:
        assert '"80:80"' not in text
        assert "redirect-to-https" not in text
        assert "--entrypoints.web.address=:80" not in text


def test_subdomain_routing(rendered):
    d, sc = rendered
    rule = hub_rule(d)
    assert "(hub|jupyterhub|duoptimum-hub)" not in rule
    assert "duoptimum-hub.${BASE_HOSTNAME}" not in rule
    for s in sc["subdomains"]:
        assert f"Host(`{s}." in rule, f"missing Host() matcher for '{s}'"
    if not sc["subdomains"]:
        assert "Host(`${BASE_HOSTNAME}`)" in rule


def test_certs(rendered):
    d, sc = rendered
    params = read_params(d)
    assert params["CERTS_CN"] == sc["cert_cn"]
    assert params["CERTS_DNS_ALTNAMES"] == ",".join(sc["sans"])

    cert_paths = list((d / "certs").glob("*/cert.pem"))
    assert len(cert_paths) == 1, f"expected one cert dir, found {cert_paths}"
    cert_dir = cert_paths[0].parent
    assert cert_dir.name == sc["cert_prefix"]

    cert = x509.load_pem_x509_certificate(cert_paths[0].read_bytes())
    key = load_pem_private_key((cert_dir / "key.pem").read_bytes(), password=None)

    cn = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    assert cn == sc["cert_cn"]
    org = cert.subject.get_attributes_for_oid(NameOID.ORGANIZATION_NAME)
    assert org and org[0].value, "cert subject missing Organization (O=)"

    dns = cert.extensions.get_extension_for_oid(
        ExtensionOID.SUBJECT_ALTERNATIVE_NAME
    ).value.get_values_for_type(x509.DNSName)
    assert sorted(dns) == sorted(sc["sans"])

    certs_yml = (d / "certs" / "certs.yml").read_text()
    assert f"/certs/{sc['cert_prefix']}/cert.pem" in certs_yml
    assert f"/certs/{sc['cert_prefix']}/key.pem" in certs_yml

    assert _pub(cert.public_key()) == _pub(key.public_key())


def test_idempotent_rerender(render):
    """Re-rendering must not regenerate (and re-key) an existing cert."""
    d = render(name="idem")
    cert_yml = d / "certs" / "certs.yml"
    first = cert_yml.stat().st_mtime
    render(name="idem", overwrite=True)
    assert cert_yml.stat().st_mtime == first, "cert regenerated on re-render"
