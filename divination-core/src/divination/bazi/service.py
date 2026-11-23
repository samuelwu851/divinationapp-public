"""bazi/service —— 八字组装层：调 repository 取历法数据，调 core 算八字。

时刻统一用 lunar_python 的 Solar（也接受 datetime）：支持公元 1–2200 年，
1582 年以前按儒略历（同史书、万年历），见 ganzhi/repository 开头的说明。
"""
from datetime import datetime, timedelta

from lunar_python import Solar

from divination.ganzhi.repository import (
    get_pre_and_next_jie, sizhu_of, jie_before, lunar_info,
    seconds_between, solar_moment, to_solar, ymdhm,
)
from divination.ganzhi.model import GanZhi, TianGan
from divination.bazi.core import (
    is_dayun_clockwise, qiyun_age, dayun_ganzhi, add_ymd, shishen, canggan_shishen,
    liunian_ganzhi, liuyue_ganzhi,
)
import json


def gz_detail(me: TianGan, gz: GanZhi, is_day: bool = False) -> dict:
    """一个干支的通用信息：干支 + 天干十神 + 藏干十神 + 纳音。

    四柱 / 大运 / 流年 / 流月共用同一套结构，前端只需一个解码类型。
      me     —— 日主(日干)，十神都相对它而言
      is_day —— 日柱本身，天干十神写「日主」而不是拿自己比自己
    """
    return {
        "ganzhi": gz.name,
        "gan_shishen": "日主" if is_day else shishen(me, gz.gan),
        "canggan": [{"gan": g.hanzi, "shishen": s} for g, s in canggan_shishen(me, gz.zhi)],
        "nayin": gz.nayin,
    }


# 八字支持的年份范围（前端滚轮 / 输入框同此范围）
YEAR_MIN, YEAR_MAX = 1, 2200


def moment(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> Solar:
    """前端给的年月日时分 → 八字用的时刻；超出范围或日期不存在抛 ValueError（中文说明）。"""
    if not YEAR_MIN <= year <= YEAR_MAX:
        raise ValueError(f"年份超出范围：{year}（支持公元 {YEAR_MIN}–{YEAR_MAX} 年）")
    return solar_moment(year, month, day, hour, minute)


def _jie_delta(birth: "datetime | Solar", is_male: bool) -> timedelta:
    """出生到起运所数的那个节之间的时间差：顺排数到下一个节，逆排数到上一个节。"""
    year_gan = sizhu_of(birth).year.gan
    pre, nxt = get_pre_and_next_jie(birth)
    if is_dayun_clockwise(year_gan, is_male):
        return timedelta(seconds=seconds_between(birth, nxt))
    return timedelta(seconds=seconds_between(pre, birth))


def qiyun(birth: "datetime | Solar", is_male: bool) -> tuple[int, int, int]:
    """起运(岁, 月, 日)。"""
    return qiyun_age(_jie_delta(birth, is_male))


def dayun(birth: "datetime | Solar", is_male: bool, count: int = 11) -> dict:
    """大运排盘 + 交运时刻：十年一换，交运落在某个「节」后第几天。"""
    birth = to_solar(birth)
    sizhu = sizhu_of(birth)
    year_gan, month_gz = sizhu.year.gan, sizhu.month
    me = sizhu.day.gan

    y, m, d = qiyun_age(_jie_delta(birth, is_male))
    start = add_ymd(birth, y, m, d)  # 起运精确时刻 = 出生 + 起运岁月日

    ganzhis = dayun_ganzhi(year_gan, month_gz, is_male, count + 1)   # 取 count 步
    steps = []
    for i, gz in enumerate(ganzhis):
        t = add_ymd(start, 10 * i, 0, 0)  # 第 i 步每隔十年交运
        jie_name, offset = jie_before(t)
        steps.append({
            **gz_detail(me, gz),
            "start_year": t.getYear(),
            "start_age": y + 10 * i,
            "jie": jie_name,
            "offset_days": offset,
        })

    # 交运口诀：大运十年一换，天干正好十个 —— 十年后年干回到原处，
    # 所以「逢某干之年换大运」对整个命盘是同一句话。
    # 节气时刻逐年游移(回归年 365.2422 天)，天数会有 ±1 天摆动，
    # 取首次交运(即起运)的实际值为准。
    jiaoyun_gan = sizhu_of(start).year.gan   # 用立春精确分界取干支年的年干
    head = steps[0]
    when = (f"{head['jie']}当天" if head["offset_days"] == 0
            else f"{head['jie']}后{head['offset_days']}天")

    return {
        "qiyun": {"years": y, "months": m, "days": d},
        "start_solar": ymdhm(start),
        "jiaoyun": {
            "year_gan": jiaoyun_gan.hanzi,
            "jie": head["jie"],
            "offset_days": head["offset_days"],
            "text": f"逢{jiaoyun_gan.hanzi}年{when}换大运",
        },
        "steps": steps,
    }

def pillars(birth: "datetime | Solar") -> dict:
    """只排四柱（不需要性别）：公历/农历 + 年月日时四柱的干支、十神、藏干、纳音。

    结构与 bazi_chart 里的同名字段一致；其他只需要四柱、不需要性别的地方直接用它。
    """
    sizhu = sizhu_of(birth)
    me = sizhu.day.gan                      # 日主
    return {
        "input_time": ymdhm(birth),
        "lunar_time": lunar_info(birth)["lunar_date"],
        "pillars": {
            "year":  gz_detail(me, sizhu.year),
            "month": gz_detail(me, sizhu.month),
            "day":   gz_detail(me, sizhu.day, is_day=True),
            "hour":  gz_detail(me, sizhu.hour),
        },
    }


def bazi_chart(birth: "datetime | Solar", is_male: bool) -> dict:
    base = pillars(birth)
    me = sizhu_of(birth).day.gan            # 日主

    dy = dayun(birth, is_male)

    # 以下是流年功能
    for step in dy["steps"]:
        y0 = step["start_year"]
        liunian = []
        for k in range(10):
            gz = liunian_ganzhi(y0 + k)
            liunian.append({"year": y0 + k, **gz_detail(me, gz)})
        step["liunian"] = liunian

    res = {
        "gender": "乾造" if is_male else "坤造",
        **base,
        "qiyun": dy["qiyun"],
        "start_solar": dy["start_solar"],
        "jiaoyun": dy["jiaoyun"],
        "dayun": dy["steps"]
    }
    return res

    
def liuyue(birth: "datetime | Solar", target_year: int) -> dict:
    """某流年的 12 流月：月柱 + 天干十神 + 藏干十神(都相对命主日主)。
    日主只看日干，与性别无关，故 liuyue 不需要 is_male。"""
    me = sizhu_of(birth).day.gan
    months = []
    for i, gz in enumerate(liuyue_ganzhi(target_year)):
        # month: 1=正月(寅)…12=腊月(丑)
        months.append({"month": i + 1, **gz_detail(me, gz)})
    return {"year": target_year, "months": months}


def _birth(req: dict) -> Solar:
    return moment(req["year"], req["month"], req["day"], req.get("hour", 0), req.get("minute", 0))

def _chart_cmd(req: dict) -> str:
    birth = _birth(req)
    return json.dumps(bazi_chart(birth, req["is_male"]), ensure_ascii=False)

def _pillars_cmd(req: dict) -> str:
    birth = _birth(req)
    return json.dumps(pillars(birth), ensure_ascii=False)

def _liuyue_cmd(req: dict) -> str:
    birth = _birth(req)
    return json.dumps(liuyue(birth, req["target_year"]), ensure_ascii=False)

def _reverse_cmd(req: dict) -> str:
    from divination.bazi import reverse                 # 放这里引入：reverse 又要引入本模块
    return json.dumps({"results": reverse.find_times(req["year"], req["month"], req["day"], req["hour"])},
                      ensure_ascii=False)

COMMANDS = {"bazi_chart": _chart_cmd, "bazi_pillars": _pillars_cmd, "liuyue": _liuyue_cmd,
            "bazi_reverse": _reverse_cmd}           # 八字反推时间：给四柱，找出公元 1–2200 年里对得上的时刻