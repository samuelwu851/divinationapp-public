"""八字反推时间。"""
import json
import random

import pytest

from divination.api import handle
from divination.bazi import reverse, service as b
from divination.ganzhi.repository import sizhu_of


def test_known_case():
    r = reverse.find_times("庚午", "庚辰", "丙寅", "壬辰")
    hit = [x for x in r if x["start"].startswith("1990")]
    assert hit and hit[0]["start"] == "1990-05-01 07:00" and hit[0]["end"] == "1990-05-01 08:59"
    p = hit[0]["pick_parts"]
    s = sizhu_of(b.moment(p["year"], p["month"], p["day"], p["hour"], p["minute"]))
    assert [s.year.name, s.month.name, s.day.name, s.hour.name] == ["庚午", "庚辰", "丙寅", "壬辰"]


def test_random_moments_are_found():
    random.seed(7)
    for _ in range(12):
        y, mo, d = random.randint(2, 2199), random.randint(1, 12), random.randint(1, 28)
        h, mi = random.randint(0, 23), random.choice([0, 30])
        if (y, mo) == (1582, 10):
            continue
        s = sizhu_of(b.moment(y, mo, d, h, mi))
        key = f"{y:04d}-{mo:02d}-{d:02d} {h:02d}:{mi:02d}"
        res = reverse.find_times(s.year.name, s.month.name, s.day.name, s.hour.name)
        assert any(x["start"] <= key <= x["end"] for x in res), key


@pytest.mark.parametrize("pillars,msg", [
    (("庚午", "甲辰", "丙寅", "壬辰"), "应该是「庚辰」"),     # 五虎遁
    (("庚午", "庚辰", "丙寅", "甲辰"), "应该是「壬辰」"),     # 五鼠遁
    (("庚丑", "庚辰", "丙寅", "壬辰"), "不存在"),
    (("庚", "庚辰", "丙寅", "壬辰"), "两个字"),
])
def test_invalid(pillars, msg):
    with pytest.raises(ValueError, match=msg):
        reverse.find_times(*pillars)


def test_command():
    r = json.loads(handle(json.dumps({"cmd": "bazi_reverse", "year": "庚午", "month": "庚辰", "day": "丙寅", "hour": "壬辰"})))
    assert any(x["start"].startswith("1990-05-01") for x in r["results"])
    e = json.loads(handle(json.dumps({"cmd": "bazi_reverse", "year": "庚午", "month": "甲辰", "day": "丙寅", "hour": "壬辰"})))
    assert "庚辰" in e["error"]
