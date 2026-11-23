"""service —— 梅花易数起卦的门面层。三种起卦法：

- 时间起卦：时间地点 → (复用 ganzhi.resolve 拿四柱+农历) → 四个数 → core.qigua
- 数字起卦：三个正整数，前两个除以 8 取余定上卦、下卦，第三个除以 6 取余定动爻（余 0 = 上爻）
- 指定起卦：直接选上卦、下卦（先天数 1–8：乾兑离震巽坎艮坤）和一个动爻（1–6）

本卦+动爻 → (复用 iching.core.flip) → 变卦 → JSON。
"""
import json
from datetime import datetime

from divination.ganzhi import service as ganzhi_service
from divination.iching import core as iching_core
from divination.iching import repository as iching_repo
from divination.meihua import core


def qigua(
    moment: datetime,
    longitude: float | None = None,
    tz_offset_hours: float = 8,
) -> dict:
    """时间起卦：返回本卦、动爻、变卦。"""
    r = ganzhi_service.resolve(moment, longitude, tz_offset_hours)
    sizhu = r["sizhu"]
    lunar = r["lunar"]

    year = sizhu.year.zhi + 1      # 地支 子=0 → 梅花数 子=1
    hour = sizhu.hour.zhi + 1
    month = lunar["month"]
    day = lunar["day"]

    ben, moving = core.qigua(year, month, day, hour)
    return {"method": "time", "numbers": {"year": year, "month": month, "day": day, "hour": hour},
            **_result(ben, moving)}


def _result(ben, moving: int) -> dict:
    bian = iching_core.flip(ben, moving)    # 变卦 = 本卦动爻变，复用易经
    return {
        "ben_gua": {"value": ben.value, "name": iching_repo.name_of(ben)},
        "moving_line": moving,
        "bian_gua": {"value": bian.value, "name": iching_repo.name_of(bian)},
    }


def _positive(n, what: str) -> int:
    try:
        v = int(n)
    except (TypeError, ValueError):
        raise ValueError(f"{what}要填正整数") from None
    if v <= 0:
        raise ValueError(f"{what}要填正整数")
    return v


def qigua_numbers(a, b, c) -> dict:
    """数字起卦：三个正整数。"""
    a, b, c = (_positive(x, f"第{i}个数") for i, x in enumerate((a, b, c), 1))
    ben, moving = core.qigua_numbers(a, b, c)
    return {"method": "number", "numbers": [a, b, c], **_result(ben, moving)}


def qigua_specified(upper, lower, moving) -> dict:
    """指定起卦：上卦、下卦（先天数 1–8），动爻（1–6）。"""
    upper, lower, moving = int(upper), int(lower), int(moving)
    if not (1 <= upper <= 8 and 1 <= lower <= 8):
        raise ValueError("上卦、下卦要在乾、兑、离、震、巽、坎、艮、坤里选")
    if not 1 <= moving <= 6:
        raise ValueError("动爻要选第 1–6 爻")
    ben, mv = core.qigua_specified(upper, lower, moving)
    return {"method": "specified", "upper": upper, "lower": lower, **_result(ben, mv)}


def qigua_request(req: dict) -> dict:
    """按请求里的 method 起卦（不写 = 时间起卦）。命令和笔记排盘共用。"""
    method = req.get("method", "time")
    if method == "number":
        nums = req.get("numbers") or []
        if len(nums) != 3:
            raise ValueError("数字起卦要三个数")
        return qigua_numbers(*nums)
    if method == "specified":
        return qigua_specified(req["upper"], req["lower"], req["moving"])
    if method != "time":
        raise ValueError(f"不认识的起卦法：{method}")
    moment = datetime(req["year"], req["month"], req["day"], req["hour"], req["minute"])
    return qigua(moment, req.get("longitude"), req.get("tz_offset_hours", 8))


def qigua_json(
    year: int, month: int, day: int, hour: int, minute: int,
    longitude: float | None = None,
    tz_offset_hours: float = 8,
) -> str:
    """平台层边界：基本类型进，JSON 串出。"""
    moment = datetime(year, month, day, hour, minute)
    return json.dumps(
        qigua(moment, longitude, tz_offset_hours),
        ensure_ascii=False,
    )


COMMANDS = {
    # method: "time"（默认，带 year/month/day/hour/minute）/ "number"（numbers: [a, b, c]）
    #         / "specified"（upper, lower: 先天数 1–8；moving: 1–6）
    "meihua": lambda req: json.dumps(qigua_request(req), ensure_ascii=False),
}
