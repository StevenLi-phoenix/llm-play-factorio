"""Agent._trim cuts long tool results on line boundaries and says how much is missing."""
from types import SimpleNamespace

from agent import Agent


def trim(text: str, n: int) -> str:
    return Agent._trim(SimpleNamespace(cfg=SimpleNamespace(max_result_chars=n)), text)


def test_short_text_untouched():
    assert trim("abc\ndef", 100) == "abc\ndef"


def test_cut_keeps_whole_lines_and_counts_omitted():
    rows = [f"row{i:03d}:" + "#" * 20 for i in range(100)]
    text = "\n".join(rows)
    out = trim(text, 500)
    assert len(out) < len(text)
    body = [ln for ln in out.split("\n") if not ln.startswith("...[")]
    assert all(ln in rows for ln in body)        # no half rows
    marker = next(ln for ln in out.split("\n") if ln.startswith("...["))
    omitted = int(marker.split("[")[1].split(" ")[0])
    kept = len("\n".join(body))
    assert omitted >= len(text) - kept - 2 and omitted <= len(text) - kept + 2


def test_single_long_line_still_cut():
    out = trim("x" * 1000, 200)
    assert len(out) < 400 and "chars cut" in out
