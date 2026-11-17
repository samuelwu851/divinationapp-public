"""bazi/service —— 八字组装层：调 repository 取历法数据，调 core 算八字。"""
from datetime import datetime

from divination.ganzhi.repository import get_pre_and_next_jie, sizhu_of, jie_before, lunar_info
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


def qiyun(birth: datetime, is_male: bool) -> tuple[int, int, int]:
    """起运(岁, 月, 日)：顺排数到下一个节，逆排数到上一个节。"""
    year_gan = sizhu_of(birth).year.gan
    pre, nxt = get_pre_and_next_jie(birth)
    delta = (nxt - birth) if is_dayun_clockwise(year_gan, is_male) else (birth - pre)
    return qiyun_age(delta)


def dayun(birth: datetime, is_male: bool, count: int = 11) -> dict:
    """大运排盘 + 交运时刻：十年一换，交运落在某个「节」后第几天。"""
    sizhu = sizhu_of(birth)
    year_gan, month_gz = sizhu.year.gan, sizhu.month
    me = sizhu.day.gan

    pre, nxt = get_pre_and_next_jie(birth)
    delta = (nxt - birth) if is_dayun_clockwise(year_gan, is_male) else (birth - pre)
    y, m, d = qiyun_age(delta)
    start = add_ymd(birth, y, m, d)  # 起运精确时刻 = 出生 + 起运岁月日

    ganzhis = dayun_ganzhi(year_gan, month_gz, is_male, count + 1)   # 取 count 步
    steps = []
    for i, gz in enumerate(ganzhis):
        t = add_ymd(start, 10 * i, 0, 0)  # 第 i 步每隔十年交运
        jie_name, offset = jie_before(t)
        steps.append({
            **gz_detail(me, gz),
            "start_year": t.year,
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
        "start_solar": start.strftime("%Y-%m-%d %H:%M"),
        "jiaoyun": {
            "year_gan": jiaoyun_gan.hanzi,
            "jie": head["jie"],
            "offset_days": head["offset_days"],
            "text": f"逢{jiaoyun_gan.hanzi}年{when}换大运",
        },
        "steps": steps,
    }

def bazi_chart(birth: datetime, is_male: bool) -> dict:
    sizhu = sizhu_of(birth)
    # 日主
    me = sizhu.day.gan

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
        "input_time": birth.strftime("%Y-%m-%d %H:%M"),
        "lunar_time": lunar_info(birth)["lunar_date"],
        "pillars":{
            "year":  gz_detail(me, sizhu.year),
            "month": gz_detail(me, sizhu.month),
            "day":   gz_detail(me, sizhu.day, is_day=True),
            "hour":  gz_detail(me, sizhu.hour),
        },
        "qiyun": dy["qiyun"],
        "start_solar": dy["start_solar"],
        "jiaoyun": dy["jiaoyun"],
        "dayun": dy["steps"]
    }
    return res

    
def liuyue(birth: datetime, target_year: int) -> dict:
    """某流年的 12 流月：月柱 + 天干十神 + 藏干十神(都相对命主日主)。
    日主只看日干，与性别无关，故 liuyue 不需要 is_male。"""
    me = sizhu_of(birth).day.gan
    months = []
    for i, gz in enumerate(liuyue_ganzhi(target_year)):
        # month: 1=正月(寅)…12=腊月(丑)
        months.append({"month": i + 1, **gz_detail(me, gz)})
    return {"year": target_year, "months": months}


def _chart_cmd(req: dict) -> str:
    birth = datetime(req["year"], req["month"], req["day"], req.get("hour", 0), req.get("minute", 0))
    return json.dumps(bazi_chart(birth, req["is_male"]), ensure_ascii=False)

def _liuyue_cmd(req: dict) -> str:
    birth = datetime(req["year"], req["month"], req["day"], req.get("hour", 0), req.get("minute", 0))
    return json.dumps(liuyue(birth, req["target_year"]), ensure_ascii=False)

COMMANDS = {"bazi_chart": _chart_cmd, "liuyue": _liuyue_cmd}