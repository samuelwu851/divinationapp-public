"""八字反推时间：给四柱（年月日时的干支），找出公元 1–2200 年里所有对得上的出生时刻。

思路（不是一天一天全找，而是一层层缩小范围）：
1. 先检查这个八字存不存在：月干要符合「五虎遁」（年干定正月的天干），时干要符合「五鼠遁」（日干定子时的天干）；
2. 年柱每 60 年轮一次 → 只看年干支对得上的那些年；
3. 月支定在哪个「节」之后（寅月从立春起、卯月从惊蛰起…），只在那一个多月里找；
4. 日柱每 60 天轮一次（跟着儒略日走）→ 那一个多月里最多一两天对得上；
5. 时支定是哪个时辰（子时 = 前一天 23:00 到 00:59，日界在 23 点）；
6. 最后每 15 分钟用排盘本身（sizhu_of）核对一遍，正好碰上交节、换年的时辰也不会错。
"""
from lunar_python import Solar

from divination.bazi.core import liunian_ganzhi
from divination.bazi.service import YEAR_MIN, YEAR_MAX
from divination.ganzhi.model import DiZhi, GanZhi, TianGan
from divination.ganzhi.repository import lunar_info, sizhu_of, ymdhm

_GAN = "甲乙丙丁戊己庚辛壬癸"
_ZHI = "子丑寅卯辰巳午未申酉戌亥"

# 月支 → 这个月从哪个「节」开始，大约是公历几月几号（只用来定搜索范围，前后会多找一些）
# 子、丑两个月跨到下一个公历年：子月从大雪（12 月）起，丑月从小寒（下一年 1 月）起
_MONTH_START = {2: (0, 2, 4), 3: (0, 3, 6), 4: (0, 4, 5), 5: (0, 5, 6), 6: (0, 6, 6), 7: (0, 7, 7),
                8: (0, 8, 8), 9: (0, 9, 8), 10: (0, 10, 8), 11: (0, 11, 7), 0: (0, 12, 7), 1: (1, 1, 6)}


def _parse(text: str, what: str) -> GanZhi:
    text = (text or "").strip()
    if len(text) != 2 or text[0] not in _GAN or text[1] not in _ZHI:
        raise ValueError(f"{what}要是两个字的干支，如「甲子」")
    gan, zhi = _GAN.index(text[0]), _ZHI.index(text[1])
    if gan % 2 != zhi % 2:
        raise ValueError(f"{what}「{text}」不存在（阳干配阳支、阴干配阴支）")
    return GanZhi(TianGan(gan), DiZhi(zhi))


def check(year: str, month: str, day: str, hour: str) -> tuple[GanZhi, GanZhi, GanZhi, GanZhi]:
    """解析并检查四柱；对不上的抛 ValueError（中文说明哪里不对、应该是什么）。"""
    y, m, d, h = _parse(year, "年柱"), _parse(month, "月柱"), _parse(day, "日柱"), _parse(hour, "时柱")
    # 五虎遁：正月（寅月）天干 = (年干 % 5) * 2 + 2
    month_gan = ((y.gan % 5) * 2 + 2 + (m.zhi - 2) % 12) % 10
    if m.gan != month_gan:
        right = _GAN[month_gan] + _ZHI[m.zhi]
        raise ValueError(f"月柱和年柱对不上：{y.name}年的{_ZHI[m.zhi]}月应该是「{right}」")
    # 五鼠遁：子时天干 = (日干 % 5) * 2
    hour_gan = ((d.gan % 5) * 2 + h.zhi) % 10
    if h.gan != hour_gan:
        right = _GAN[hour_gan] + _ZHI[h.zhi]
        raise ValueError(f"时柱和日柱对不上：{d.name}日的{_ZHI[h.zhi]}时应该是「{right}」")
    return y, m, d, h


_DAY_OFFSET = None


def _day_index(jd_day: int) -> int:
    """某一天（儒略日的整数部分，取正午）的日柱序号（0–59）：日柱每天 +1，跟着儒略日走。"""
    global _DAY_OFFSET
    if _DAY_OFFSET is None:
        ref = Solar.fromYmdHms(2000, 1, 1, 12, 0, 0)
        _DAY_OFFSET = (int(ref.getJulianDay()) - sizhu_of(ref).day.index) % 60
    return (jd_day - _DAY_OFFSET) % 60


def find_times(year: str, month: str, day: str, hour: str,
               start: int = YEAR_MIN, end: int = YEAR_MAX) -> list[dict]:
    """所有对得上的时刻（按时间先后）：[{start, end, pick, lunar}]。
    start / end 是这个时辰里四柱都对得上的第一分钟 / 最后一分钟；pick 是中间那一刻（拿去排盘用）。"""
    y, m, d, h = check(year, month, day, hour)
    want = (y.index, m.index, d.index, h.index)
    results = []
    first = start + ((y.index - liunian_ganzhi(start).index) % 60)          # 第一个年干支对得上的年
    for yr in range(first, end + 1, 60):
        dy, mo, da = _MONTH_START[m.zhi]
        try:
            approx = Solar.fromYmd(yr + dy, mo, da)
        except Exception:
            continue
        base = int(approx.getJulianDay() + 0.5)
        for jd_day in range(base - 30, base + 45):                            # 节前后多找一些（儒略历年份节会早十来天）
            if _day_index(jd_day) != d.index:
                continue
            # 这一天（正午）→ 时辰窗口：子时从前一天 23:00 起，其他时辰从 (2×支−1) 点起，各两小时
            noon = Solar.fromJulianDay(jd_day)
            begin_hour = -1 if h.zhi == 0 else 2 * h.zhi - 1
            begin = Solar.fromJulianDay(Solar.fromYmdHms(noon.getYear(), noon.getMonth(), noon.getDay(), 0, 0, 0)
                                        .getJulianDay() + begin_hour / 24)
            ok = []
            for k in range(8):                                                # 每 15 分钟核对一次
                t = Solar.fromJulianDay(begin.getJulianDay() + k / 96 + 1 / 86400)   # +1 秒，避开浮点误差落到前一分钟
                t = Solar.fromYmdHms(t.getYear(), t.getMonth(), t.getDay(), t.getHour(), t.getMinute(), 0)
                s = sizhu_of(t)
                if (s.year.index, s.month.index, s.day.index, s.hour.index) == want:
                    ok.append(t)
            if not ok or not (start <= ok[0].getYear() <= end):
                continue
            last = Solar.fromJulianDay(ok[-1].getJulianDay() + 14 / 1440 + 1 / 86400)
            pick = ok[len(ok) // 2]
            results.append({
                "start": ymdhm(ok[0]),
                "end": ymdhm(Solar.fromYmdHms(last.getYear(), last.getMonth(), last.getDay(), last.getHour(), last.getMinute(), 0)),
                "pick": ymdhm(pick),
                "pick_parts": {"year": pick.getYear(), "month": pick.getMonth(), "day": pick.getDay(),
                               "hour": pick.getHour(), "minute": pick.getMinute()},
                "lunar": lunar_info(pick)["lunar_date"],
            })
    results.sort(key=lambda r: r["start"].zfill(20))
    return results
