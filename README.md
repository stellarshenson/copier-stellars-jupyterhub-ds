# stellars-jupyterhub-ds Deployment Template
![GitHub Actions](https://github.com/stellarshenson/copier-stellars-jupyterhub-ds/actions/workflows/validate-template.yml/badge.svg)
![JupyterLab 4](https://img.shields.io/badge/JupyterLab-%20%20%20%204%20%20%20%20-orange?style=flat)
[![Brought To You By KOLOMOLO](https://img.shields.io/badge/Brought%20To%20You%20By-KOLOMOLO-00ffff?style=flat)](https://kolomolo.com)
[![Donate PayPal](https://img.shields.io/badge/Donate-PayPal-blue?style=flat)](https://www.paypal.com/donate/?hosted_button_id=B4KPBJDLLXTSA)

[Copier](https://copier.readthedocs.io/) template that scaffolds a thin
deployment overlay for [stellars-jupyterhub-ds](https://github.com/stellarshenson/stellars-jupyterhub-ds)
(the upstream JupyterHub platform).

The generated overlay carries only what changes between deployments - branding,
hostname / TLS, admin user, optional CIFS. The upstream platform itself is
consumed as a single `compose.yml` file downloaded from the upstream repo on
first run (gitignored, refreshable via `start.sh --refresh`) plus the
`stellars/duoptimumhub:latest` image pulled from Docker Hub - no
git clone, no submodule, no Dockerfile build context required locally.

## Before you start

You need: Docker, Docker Compose v2, and Copier. (No system Python required — both Copier install paths below provide their own.) Plus optional NVIDIA driver + Container Toolkit if you want GPU-enabled JupyterLab.

### Linux checklist

Tick each item once the listed command works. Stop reading once everything passes.

- [ ] `docker ps` prints an empty (or non-empty) container list, no error
- [ ] `docker compose version` prints something like `Docker Compose version v2.x.y`
- [ ] `copier --version` prints `9.x` or higher
- [ ] (GPU only) `nvidia-smi` shows your NVIDIA GPU
- [ ] (GPU only) `docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi` shows the GPU from inside a container

For each unticked item, the matching install snippet:

#### `docker ps` fails or says "permission denied"

Pick **one** of these paths.

**A. Docker Desktop for Linux (GUI, easiest)** — bundles Engine, Compose v2, and Buildx; one installer, same product as Windows/Mac:

Download from <https://www.docker.com/products/docker-desktop/> and run the installer for your distro. Open it once and Docker is up.

**B. Stock Ubuntu / Debian apt** (no third-party repo needed, verified on Ubuntu 24.04):

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 containerd
sudo usermod -aG docker "$USER"
# Log out and back in (or run `newgrp docker`) for the group change to take effect
```

**C. Latest Docker CE via Docker's convenience script** (newer than what stock apt ships):

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
```

After installing, re-run `docker ps` and `docker compose version` — both should print without errors.

#### `copier --version` fails

On Ubuntu 24.04+ and Debian 12+, plain `pip install copier` is **blocked** with `error: externally-managed-environment` (PEP 668). The system Python ships with an `EXTERNALLY-MANAGED` marker that tells pip to refuse modifying it, so apt and pip don't fight over the same `site-packages`. Use **pipx** — it's in stock apt, pulls in `python3` as a dependency for you, and installs Copier into its own isolated venv:

```bash
sudo apt update
sudo apt install -y pipx
pipx ensurepath          # adds ~/.local/bin to PATH; restart your shell after this
pipx install copier
```

After restarting your shell, `copier --version` should print `9.x`.

Don't bother with `pip install --break-system-packages` — that "works" but defeats the protection PEP 668 exists for and may collide with apt.

#### `nvidia-smi` fails (you have an NVIDIA GPU and want GPU support)

Skip this section if you don't have an NVIDIA GPU or don't need GPU acceleration.

**Step 1 — install the proprietary driver** (auto-detects the right version for your card):

```bash
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall
sudo reboot
```

After reboot, `nvidia-smi` should print your GPU model and driver version.

**Step 2 — install NVIDIA Container Toolkit** so Docker can pass the GPU through (uses NVIDIA's apt repo because the toolkit isn't in stock Ubuntu):

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify with the second GPU check from the checklist:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

### Windows checklist

The template scaffolds Linux scripts and Linux containers, so on Windows you do everything inside WSL2.

- [ ] **Windows Subsystem for Linux** enabled in Control Panel → Programs → Turn Windows features on or off
- [ ] **Virtual Machine Platform** enabled in the same place
- [ ] Reboot after enabling those two features
- [ ] `wsl --install` run from an admin PowerShell, followed by another reboot — Ubuntu shows up in the Start menu
- [ ] Docker Desktop installed from <https://www.docker.com/products/docker-desktop/>, opened at least once
- [ ] In Docker Desktop: **Settings → Resources → WSL Integration** turned on for your Ubuntu distro
- [ ] Inside Ubuntu (WSL2), all three Linux checks pass: `docker ps`, `docker compose version`, `copier --version`
- [ ] (GPU only) Install NVIDIA's [GeForce / RTX driver for WSL](https://www.nvidia.com/en-us/drivers/) on Windows, then verify `nvidia-smi` works inside the WSL2 Ubuntu shell. NVIDIA Container Toolkit goes inside Ubuntu as in the Linux GPU step above.

If `docker ps` errors inside WSL2 with something about the daemon, confirm Docker Desktop is running on Windows and WSL Integration is on for your distro.

## Quickstart

```bash
pipx install copier        # see "Before you start" if pipx missing
copier copy --trust gh:stellarshenson/copier-stellars-jupyterhub-ds ./my-jupyterhub
cd my-jupyterhub
./start.sh
```

- `--trust` runs post-copy `_tasks` (chmod, cert gen). Without it copier refuses.
- ~15 questions. Defaults computed from earlier answers.

## Generated layout

```
my-jupyterhub/
  branding/                            # Logo, favicon, JupyterLab toolbar icon
  certs/                               # Self-signed TLS generator + rendered certs.params
  compose_override.yml                 # Branding env vars + Traefik wiring
  compose_cifs.yml                     # Optional CIFS NAS mount (only if cifs_shared_mount=true)
  env.default                          # Default env (tracked)
  .env                                 # Local overrides (gitignored; takes precedence over env.default)
  start.sh / stop.sh                   # First start.sh auto-generates a self-signed cert from certs/certs.params
  compose.yml                          # Upstream platform compose (downloaded by start.sh on first run; gitignored)
```

## Updating from this template

Pull newer revisions of this template into an existing overlay:

```bash
copier update --trust                  # re-render against the latest template at gh:stellarshenson/copier-stellars-jupyterhub-ds
```

`--trust` is required again because `copier update` re-runs the template's `_tasks`.

Copier persists answers in `.copier-answers.yml` so subsequent updates pick
up new template features without re-asking the same questions. Conflicting
edits surface as merge prompts.

This is independent from upstream platform updates: `copier update` refreshes
the overlay from this template repo, while `start.sh --refresh` (in the
generated overlay) re-downloads the upstream `compose.yml` and pulls the
latest `stellars/duoptimumhub:latest` image from Docker Hub.

## What stays in the upstream platform

Bug fixes and feature work for the platform itself live in the
[upstream repo](https://github.com/stellarshenson/stellars-jupyterhub-ds).
The deployment overlay only carries operator-specific configuration -
branding, hostnames, TLS, the optional CIFS overlay, and `compose_override.yml`
- and consumes everything else from upstream as a downloaded `compose.yml`
plus the published Docker Hub image. To customise platform behaviour, fork
upstream and have `start.sh` download from your fork (edit
`UPSTREAM_COMPOSE_URL` in `start.sh`).

## License

[MIT](LICENSE) - same as the upstream platform.
