"""Tests for the branding-cleanup task in copier.yml.

The _tasks block drops a template's default branding asset when the operator
supplies a replacement, while leaving operator files untouched:
  *.png operator file -> removes <prefix>_jh_logo.png   (JupyterHub logo)
  *.svg operator file -> removes <prefix>_jl_logo.svg   (JupyterLab logo)
  *.ico operator file -> removes <prefix>_favicon.ico   (browser favicon)
"""

PREFIX = "my_jupyterhub"  # default branding_prefix for project "My JupyterHub"
SVG = '<svg xmlns="http://www.w3.org/2000/svg"/>'


def b(render_dir, name):
    return render_dir / "branding" / name


def test_operator_replacement_removes_matching_defaults(render):
    d = render(name="brand")
    for fn in (f"{PREFIX}_jh_logo.png", f"{PREFIX}_jl_logo.svg", f"{PREFIX}_favicon.ico"):
        assert b(d, fn).is_file()

    b(d, "operator_brand.png").write_text("png")
    b(d, "operator_brand.svg").write_text(SVG)
    b(d, "operator_brand.ico").write_bytes(b"\x00\x00\x01\x00")

    render(name="brand", overwrite=True)

    assert not b(d, f"{PREFIX}_jh_logo.png").exists()
    assert not b(d, f"{PREFIX}_jl_logo.svg").exists()
    assert not b(d, f"{PREFIX}_favicon.ico").exists()
    # operator files survive the re-render
    assert b(d, "operator_brand.png").is_file()
    assert b(d, "operator_brand.svg").is_file()
    assert b(d, "operator_brand.ico").is_file()


def test_cleanup_is_per_extension(render):
    d = render(name="brand_single")
    b(d, "single.png").write_text("png")
    render(name="brand_single", overwrite=True)
    assert not b(d, f"{PREFIX}_jh_logo.png").exists()
    assert b(d, f"{PREFIX}_jl_logo.svg").is_file()
    assert b(d, f"{PREFIX}_favicon.ico").is_file()


def test_prefix_named_other_extension_replacement(render):
    d = render(name="brand_prefix")
    b(d, f"{PREFIX}_jh_logo.png").unlink()
    b(d, f"{PREFIX}_jh_logo.svg").write_text(SVG)
    render(name="brand_prefix", overwrite=True)
    # the .png is re-rendered on update, then removed because the operator's
    # prefix-named .svg replacement is detected
    assert not b(d, f"{PREFIX}_jh_logo.png").exists()
    assert b(d, f"{PREFIX}_jh_logo.svg").is_file()
    assert b(d, f"{PREFIX}_jl_logo.svg").is_file()
    assert b(d, f"{PREFIX}_favicon.ico").is_file()
