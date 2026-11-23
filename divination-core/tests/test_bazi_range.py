"""八字支持公元 1–2200 年；1582 年以前按儒略历（同史书、万年历）。"""
import json
import random

import pytest

from divination.api import handle
from divination.bazi import service as b
from divination.ganzhi.repository import sizhu_of


def call(cmd, **p):
    return json.loads(handle(json.dumps({"cmd": cmd, **p}, ensure_ascii=False)))


@pytest.mark.parametrize("y", [1, 2, 618, 1000, 1581, 1582, 1583, 2100, 2199, 2200])
def test_extreme_years_work(y):
    for m, d, h in [(1, 1, 0), (2, 4, 12), (12, 31, 23)]:
        for male in (True, False):
            c = b.bazi_chart(b.moment(y, m, d, h, 0), male)
            assert len(c["dayun"]) >= 10
        assert len(b.liuyue(b.moment(y, m, d, h, 0), y)["months"]) == 12


def test_julian_dates_before_1582():
    c = b.bazi_chart(b.moment(1000, 2, 29, 8, 0), True)      # 儒略历才有的 2 月 29 日
    assert c["input_time"] == "1000-02-29 08:00"
    with pytest.raises(ValueError, match="不存在"):
        b.moment(1582, 10, 10)                               # 改历跳过的 10 天
    with pytest.raises(ValueError, match="没有 29 日"):
        b.moment(1900, 2, 29)                                # 格里历 1900 不闰
    with pytest.raises(ValueError, match="超出范围"):
        b.moment(2201, 1, 1)
    assert "error" in call("bazi_chart", year=0, month=1, day=1, hour=0, minute=0, is_male=True)


def test_day_ganzhi_continuous_across_calendar_change():
    a, c = sizhu_of(b.moment(1582, 10, 4, 12)).day, sizhu_of(b.moment(1582, 10, 15, 12)).day
    assert (c.index - a.index) % 60 == 1                     # 10-04 的下一天就是 10-15


def test_day_ganzhi_follows_julian_day_number():
    random.seed(1)
    refs = set()
    for _ in range(500):
        y, m, d = random.randint(1, 2200), random.randint(1, 12), random.randint(1, 28)
        if (y, m) == (1582, 10) and 5 <= d <= 14:
            continue
        s = b.moment(y, m, d, 12, 0)
        refs.add((int(s.getJulianDay()) - sizhu_of(s).day.index) % 60)
    assert len(refs) == 1


def test_casebook_bazi_chart_ancient(tmp_path):
    call("casebook_open", path=str(tmp_path / "t.db"))
    n = call("note_create", title="古人")
    c = call("chart_create", note_id=n["id"], type="bazi",
             params={"year": 1000, "month": 2, "day": 29, "hour": 8, "minute": 0, "is_male": True, "name": "某"})
    assert c["snapshot"]["chart"]["input_time"] == "1000-02-29 08:00"
