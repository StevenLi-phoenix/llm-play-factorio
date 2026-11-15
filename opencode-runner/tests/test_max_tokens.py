"""MAX_TOKENS env: a number caps the reply, "none"/"max" sends no max_tokens so the model's own maximum applies."""
import llm


def test_parse_max_tokens():
    assert llm.parse_max_tokens(None, 6000) == 6000
    assert llm.parse_max_tokens("", 6000) == 6000
    assert llm.parse_max_tokens("8000", 6000) == 8000
    assert llm.parse_max_tokens("none", 6000) is None
    assert llm.parse_max_tokens("MAX", 6000) is None


def test_request_body_omits_max_tokens_when_none():
    assert "max_tokens" not in llm.request_body("m", [], None, None, "auto", None)
    assert llm.request_body("m", [], None, 123, "auto", None)["max_tokens"] == 123
