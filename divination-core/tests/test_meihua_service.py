from datetime import datetime

from divination.iching import core as iching_core
from divination.iching.model import Hexagram
from divination.meihua import service


def test_qigua_known_case():
    """2024-10-21 14:00 无地区：手算 年5 月9 日19 时8。

    上卦=(5+9+19)%8=1→乾，下卦=(5+9+19+8)%8=1→乾 → 本卦 63(乾為天)；
    动爻=41%6=5；变卦=flip(63,5)=61(火天大有)。
    """
    result = service.qigua(datetime(2024, 10, 21, 14, 0))
    assert result["numbers"] == {"year": 5, "month": 9, "day": 19, "hour": 8}
    assert result["ben_gua"]["value"] == 63
    assert result["ben_gua"]["name"] == "乾為天"
    assert result["moving_line"] == 5
    assert result["bian_gua"]["value"] == 61
    assert result["bian_gua"]["name"] == "火天大有"


def test_bian_is_ben_flipped_at_moving():
    """变卦必须等于本卦在动爻处翻一爻（和易经 core.flip 对齐）。"""
    result = service.qigua(datetime(2024, 6, 21, 12, 0), longitude=-118.24, tz_offset_hours=-8)
    ben = Hexagram(result["ben_gua"]["value"])
    expected_bian = iching_core.flip(ben, result["moving_line"])
    assert result["bian_gua"]["value"] == expected_bian.value


def test_result_ranges():
    """任意输入：卦值 0–63、动爻 1–6。"""
    for month in range(1, 13):
        for hour in (0, 6, 12, 18, 23):
            result = service.qigua(datetime(2024, month, 15, hour, 30))
            assert 0 <= result["ben_gua"]["value"] <= 63
            assert 0 <= result["bian_gua"]["value"] <= 63
            assert 1 <= result["moving_line"] <= 6


def test_number_method():
    """数字起卦：3、5、10 → 上卦 3 离、下卦 5 巽，动爻 10%6=4。"""
    r = service.qigua_numbers(3, 5, 10)
    assert r["method"] == "number" and r["numbers"] == [3, 5, 10]
    assert r["ben_gua"]["name"] == "火風鼎" and r["moving_line"] == 4
    assert service.qigua_numbers(8, 16, 12)["ben_gua"]["name"] == "坤為地"   # 余 0 当 8（坤），12%6=0 → 上爻
    assert service.qigua_numbers(8, 16, 12)["moving_line"] == 6
    assert service.qigua_numbers(9, 1, 1)["ben_gua"]["name"] == "乾為天"      # 9%8=1 → 乾


def test_specified_method():
    r = service.qigua_specified(6, 1, 3)        # 上坎 下乾，三爻动
    assert r["ben_gua"]["name"] == "水天需" and r["moving_line"] == 3
    ben = Hexagram(r["ben_gua"]["value"])
    assert r["bian_gua"]["value"] == iching_core.flip(ben, 3).value


def test_bad_inputs():
    import pytest
    for args in [(0, 1, 1), (-3, 1, 1), ("a", 1, 1)]:
        with pytest.raises(ValueError, match="正整数"):
            service.qigua_numbers(*args)
    with pytest.raises(ValueError):
        service.qigua_specified(9, 1, 1)
    with pytest.raises(ValueError):
        service.qigua_specified(1, 1, 7)
    assert service.qigua_request({"method": "number", "numbers": [3, 5, 10]})["moving_line"] == 4
