"""神煞命令。

{"cmd": "shensha", "year": "甲辰", "month": "丙寅", "day": "庚午"}           直接给干支（月可以只给地支）
{"cmd": "shensha", "date": {"year": 2024, "month": 2, "day": 10, "hour": 12, "minute": 0}}
                                                                        给公历时刻，按八字的年月日柱算（立春换年、节气换月）
"""
import json

from divination.shensha import core


def from_date(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> dict:
    from divination.bazi.service import moment
    from divination.ganzhi.repository import sizhu_of
    s = sizhu_of(moment(year, month, day, hour, minute))
    return core.compute(s.year.name, s.month.name, s.day.name)


def _shensha_cmd(req: dict) -> str:
    d = req.get("date")
    if d:
        res = from_date(d["year"], d["month"], d["day"], d.get("hour", 0), d.get("minute", 0))
    else:
        res = core.compute(req["year"], req["month"], req["day"])
    return json.dumps(res, ensure_ascii=False)


COMMANDS = {"shensha": _shensha_cmd}
