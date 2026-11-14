import json

import pytest

from agent import parse_tool_args


def test_plain_object():
    assert parse_tool_args('{"a": 1}') == {"a": 1}


def test_empty_defaults_to_object():
    assert parse_tool_args("") == {}
    assert parse_tool_args(None) == {}


def test_extra_data_keeps_first_object():
    assert parse_tool_args('{"steps": [1, 2]}\n{"steps": [3]}') == {"steps": [1, 2]}
    assert parse_tool_args('{"a": 1} trailing words') == {"a": 1}


def test_truncated_json_still_fails():
    with pytest.raises(json.JSONDecodeError):
        parse_tool_args('{"steps": [{"type": "walk_to", "x": ')
