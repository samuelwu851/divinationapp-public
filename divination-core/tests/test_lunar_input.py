"""农历选时间：lunar_to_solar / solar_to_lunar 互转（含闰月、古代）。"""
import json
import random

import pytest

from divination.api import handle


def call(cmd, **p):
    return json.loads(handle(json.dumps({"cmd": cmd, **p}, ensure_ascii=False)))


def test_known_dates():
    r = call("lunar_to_solar", year=2026, month=10, day=15, hour=14, minute=30)
    assert r == {"year": 2026, "month": 11, "day": 23, "hour": 14, "minute": 30}
    r = call("lunar_to_solar", year=2023, month=2, day=1, is_leap=True)       # 2023 闰二月初一
    assert (r["year"], r["month"], r["day"]) == (2023, 3, 22)


def test_round_trip_including_ancient():
    random.seed(3)
    for _ in range(300):
        y = random.randint(2, 2199)
        months = call("lunar_months", year=y)["months"]
        mon = random.choice(months)
        d = random.randint(1, mon["days"])
        s = call("lunar_to_solar", year=y, month=mon["month"], day=d, is_leap=mon["is_leap"], hour=8)
        back = call("solar_to_lunar", year=s["year"], month=s["month"], day=s["day"], hour=8)
        assert (back["lunar_year"], back["lunar_month"], back["is_leap"], back["lunar_day"]) == \
               (y, mon["month"], mon["is_leap"], d)


def test_ancient_solar_to_lunar_julian_day():
    assert "error" not in call("solar_to_lunar", year=1000, month=2, day=29)   # 儒略历才有的日子


@pytest.mark.parametrize("bad", [
    dict(year=2026, month=2, day=1, is_leap=True),      # 2026 没有闰二月
    dict(year=2026, month=1, day=31),                   # 农历月最多 30 天
])
def test_invalid(bad):
    assert "error" in call("lunar_to_solar", **bad)
