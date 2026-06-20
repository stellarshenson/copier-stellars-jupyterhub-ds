"""Shared pytest fixtures for the copier-template integration tests.

Copier renders from the latest git tag, not the dirty worktree, so to exercise
uncommitted template changes we render from a fresh non-git snapshot of the
working tree. The snapshot is built once per session and reused.
"""

import pathlib
import subprocess

import pytest

REPO = pathlib.Path(__file__).resolve().parent.parent


def copier_render(src, dst, data=None, overwrite=False):
    """Render the template at `src` into `dst` with `--defaults --trust`.

    `data` is a dict of copier answers passed as `--data key=value`. Raises with
    the captured copier output on failure so test reports are actionable.
    """
    cmd = ["copier", "copy", "--defaults", "--trust"]
    if overwrite:
        cmd.append("--overwrite")
    for key, value in (data or {}).items():
        cmd += ["--data", f"{key}={value}"]
    cmd += [str(src), str(dst)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"copier render failed: {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
        )
    return pathlib.Path(dst)


@pytest.fixture(scope="session")
def template_src(tmp_path_factory):
    """Non-git snapshot of the working tree, committed to a throwaway repo."""
    src = tmp_path_factory.mktemp("template_src")
    subprocess.run(
        ["rsync", "-a", "--exclude=.git", "--exclude=__pycache__",
         "--exclude=.venv", "--exclude=*.pyc", f"{REPO}/", f"{src}/"],
        check=True,
    )
    subprocess.run(["git", "init", "-q"], cwd=src, check=True)
    subprocess.run(["git", "add", "-A"], cwd=src, check=True)
    subprocess.run(
        ["git", "-c", "user.email=test@test.dev", "-c", "user.name=test",
         "commit", "-qm", "test snapshot"],
        cwd=src, check=True,
    )
    return src


@pytest.fixture(scope="session")
def do_render():
    """The render helper, exposed as a fixture so test modules need no import."""
    return copier_render


@pytest.fixture
def render(template_src, tmp_path):
    """Ad-hoc render into tmp_path/<name>. Call again with overwrite=True to
    re-render the same dir (re-runs the copier _tasks - cert gen, branding
    cleanup)."""
    def _render(data=None, name="render", overwrite=False):
        return copier_render(template_src, tmp_path / name, data, overwrite)
    return _render
