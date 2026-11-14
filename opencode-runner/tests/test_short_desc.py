import asyncio

from agent import _short_desc

LONG = ("Machines of your force in an area grouped by problem - no power, low power, no fuel, missing ingredients "
        "(with which ingredient when detectable), output full, depleted ore, idle - plus power summary. "
        "Centred on your character; the only argument is radius (no x/y).")


def test_short_text_untouched():
    assert _short_desc("Walk to a tile.") == "Walk to a tile."


def test_truncation_keeps_final_caveat():
    out = _short_desc(LONG)
    assert "(no x/y)" in out
    assert out.endswith("(tool_help for more)")


def test_truncation_stays_bounded():
    out = _short_desc(LONG + " " + "filler sentence. " * 40)
    assert len(out) < 260 + 160


def test_real_analyze_factory_keeps_no_xy():
    """Agents kept passing x/y to analyze_factory because the visible description cut the 'no x/y' note."""
    from factorio_mcp.game import Config as GameConfig
    from factorio_mcp.server import build_app

    app = build_app(GameConfig(host="127.0.0.1", port=1, password="x", character="w0"))
    tools = asyncio.run(app.list_tools())
    desc = next(t.description for t in tools if t.name == "analyze_factory")
    assert "no x/y" in _short_desc(desc)
