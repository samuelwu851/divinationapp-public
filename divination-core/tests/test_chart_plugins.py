"""插件注册排盘类型 + bazi_pillars 命令。"""
import json

import pytest

from divination import api
from divination.casebook import charts


def test_register_builder_and_build():
    def fake(p):
        return "测试", {"card": {"title": "测试术数", "guas": []}, "x": p["x"]}
    charts.register_builders({"_fake": fake})
    try:
        title, snap = charts.build("_fake", {"x": 1})
        assert title == "测试" and snap["x"] == 1 and snap["card"]["title"] == "测试术数"
    finally:
        charts.BUILDERS.pop("_fake")


def test_register_cannot_override_builtin():
    with pytest.raises(ValueError):
        charts.register_builders({"bazi": lambda p: ("", {})})
    assert charts.BUILDERS["bazi"] is charts._bazi


def test_bazi_pillars_command():
    r = json.loads(api.handle(json.dumps(
        {"cmd": "bazi_pillars", "year": 2026, "month": 11, "day": 23, "hour": 14, "minute": 30})))
    assert r["input_time"] == "2026-11-23 14:30"
    assert [r["pillars"][k]["ganzhi"] for k in ("year", "month", "day", "hour")][:2] == ["丙午", "己亥"]
    assert r["pillars"]["day"]["gan_shishen"] == "日主"
