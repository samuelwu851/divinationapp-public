"""bazi/service —— 八字组装层：调 repository 取历法数据，调 core 算八字。"""
from datetime import datetime

from divination.ganzhi.repository import get_pre_and_next_jie, sizhu_of, jie_before, lunar_info
from divination.bazi.core import (
    is_dayun_clockwise, qiyun_age, dayun_ganzhi, add_ymd, shishen, canggan_shishen,
    liunian_ganzhi, liuyue_ganzhi,
)
import json

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
            "ganzhi": gz.name,
            "gan_shishen":shishen(me, gz.gan),
            "zhi_shishen": [{"gan": g.hanzi, "shishen": s} for g, s in canggan_shishen(me, gz.zhi)],
            "start_year": t.year,
            "start_age": y + 10 * i,
            "jie": jie_name,
            "offset_days": offset,
        })

    return {
        "qiyun": {"years": y, "months": m, "days": d},
        "start_solar": start.strftime("%Y-%m-%d %H:%M"),
        "steps": steps,
    }

def bazi_chart(birth: datetime, is_male: bool) -> dict:
    sizhu = sizhu_of(birth)
    # 日主
    me = sizhu.day.gan

    def pillar(gz, is_day = False):
        return{
            "ganzhi": gz.name,
            "gan_shishen": "日主" if is_day else shishen(me, gz.gan),
            "nayin": gz.nayin,
            "canggan": [{"gan": g.hanzi, "shishen":s} for g, s in canggan_shishen(me, gz.zhi)]
        }
    
    dy = dayun(birth, is_male)

    # 以下是流年功能
    for step in dy["steps"]:
        y0 = step["start_year"]
        liunian = []
        for k in range(10):
            gz = liunian_ganzhi(y0 + k)
            liunian.append({
                "year": y0 + k,
                "ganzhi": gz.name,
                "gan_shishen": shishen(me, gz.gan),
                "zhi_shishen": [{"gan": g.hanzi, "shishen": s} for g, s in  canggan_shishen(me, gz.zhi)]
            })
        step["liunian"] = liunian

    res = {
        "gender": "乾造" if is_male else "坤造",
        "input_time": birth.strftime("%Y-%m-%d %H:%M"),
        "lunar_time": lunar_info(birth)["lunar_date"],
        "pillars":{
            "year": pillar(sizhu.year),
            "month": pillar(sizhu.month),
            "day":   pillar(sizhu.day, is_day=True),
            "hour":  pillar(sizhu.hour)
        },
        "qiyun": dy["qiyun"],
        "start_solar": dy["start_solar"],
        "dayun": dy["steps"]
    }
    return res

    
def liuyue(birth: datetime, target_year: int) -> dict:
    """某流年的 12 流月：月柱 + 天干十神 + 藏干十神(都相对命主日主)。
    日主只看日干，与性别无关，故 liuyue 不需要 is_male。"""
    me = sizhu_of(birth).day.gan
    months = []
    for i, gz in enumerate(liuyue_ganzhi(target_year)):
        months.append({
            "month": i + 1,                      # 1=正月(寅)…12=腊月(丑)
            "ganzhi": gz.name,
            "gan_shishen": shishen(me, gz.gan),
            "zhi_shishen": [{"gan": g.hanzi, "shishen": s}
                            for g, s in canggan_shishen(me, gz.zhi)],
        })
    return {"year": target_year, "months": months}


def _chart_cmd(req: dict) -> str:
    birth = datetime(req["year"], req["month"], req["day"], req.get("hour", 0), req.get("minute", 0))
    return json.dumps(bazi_chart(birth, req["is_male"]), ensure_ascii=False)

def _liuyue_cmd(req: dict) -> str:
    birth = datetime(req["year"], req["month"], req["day"], req.get("hour", 0), req.get("minute", 0))
    return json.dumps(liuyue(birth, req["target_year"]), ensure_ascii=False)

COMMANDS = {"bazi_chart": _chart_cmd, "liuyue": _liuyue_cmd}