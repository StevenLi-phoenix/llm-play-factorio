"""The /mods download: strict file names, only regular files of the mods folder."""
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import dashboard  # noqa: E402
import pack_mod  # noqa: E402


def test_mod_file_accepts_only_plain_zip_names(tmp_path):
    (tmp_path / "factorio-mcp_0.3.13.zip").write_bytes(b"x")
    (tmp_path / "notes.txt").write_text("x")
    (tmp_path / "sub").mkdir()
    ok = dashboard.mod_file("factorio-mcp_0.3.13.zip", tmp_path)
    assert ok == tmp_path / "factorio-mcp_0.3.13.zip"
    for bad in ["../x.zip", "..%2fx.zip", "sub/x.zip", "notes.txt", "missing.zip", "", ".zip", "a b.zip", "sub.zip", "a/../b.zip"]:
        assert dashboard.mod_file(bad, tmp_path) is None, bad


def test_mods_page_lists_zips(tmp_path):
    (tmp_path / "m_1.0.0.zip").write_bytes(b"x" * 2048)
    page = dashboard.mods_page(tmp_path).decode()
    assert 'href="/mods/m_1.0.0.zip"' in page and "2 KB" in page
    assert "no mod zips yet" in dashboard.mods_page(tmp_path / "nope").decode()


def test_pack_mod_layout(tmp_path):
    mod = tmp_path / "src" / "my-mod"
    (mod / "scripts").mkdir(parents=True)
    (mod / "info.json").write_text('{"name": "my-mod", "version": "1.2.3"}')
    (mod / "control.lua").write_text("-- x")
    (mod / "scripts" / "a.lua").write_text("-- a")
    (mod / "__pycache__").mkdir()
    (mod / "__pycache__" / "junk.pyc").write_bytes(b"1")
    (mod / ".hidden").write_text("h")
    out = pack_mod.pack(mod, tmp_path / "out")
    assert out.name == "my-mod_1.2.3.zip"
    names = sorted(zipfile.ZipFile(out).namelist())
    assert names == ["my-mod_1.2.3/control.lua", "my-mod_1.2.3/info.json", "my-mod_1.2.3/scripts/a.lua"]
