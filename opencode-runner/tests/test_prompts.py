"""Prompt templates must render: WORKER_SYSTEM and START_MSG go through str.format."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import prompts  # noqa: E402


def test_templates_render():
    prompts.check_templates()
    text = prompts.WORKER_SYSTEM.format(character="w2")
    assert "w2" in text and '{"type":"walk_to"' in text


def test_start_message_shows_the_task_list():
    text = prompts.START_MSG.format(character="w1", notes="n", tasks="T1 [doing] fuel boilers", summary="s", board="b")
    assert "Your task list" in text and "T1 [doing] fuel boilers" in text
