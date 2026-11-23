"""
本层通过具体时刻返回干支历
用lunar_python拿到干支，并且转换成干支编码

关于「时刻」：可以传 Python 的 datetime，也可以传 lunar_python 的 Solar。
- 两者的区别在 1582 年以前：lunar_python 按历史惯例，1582-10-15 之前的公历日期是**儒略历**
  （和史书、万年历一致；1582-10-05 到 10-14 这 10 天不存在），而 Python 的 datetime 永远是格里历。
- 所以八字这种要支持古代日期的地方，统一用 Solar 表示时刻，算「差几天」用儒略日（天文学上连续计数的天数，
  不分历法），不用 datetime 相减——否则 1000-02-29 这种儒略历才有的日子会直接报错。
"""
import math
from datetime import datetime

from lunar_python import Lunar, LunarYear, Solar
from lunar_python.util import SolarUtil

from divination.ganzhi.model import DiZhi, GanZhi, SiZhu, TianGan

_GAN = "甲乙丙丁戊己庚辛壬癸"
_ZHI = "子丑寅卯辰巳午未申酉戌亥"

def _parse_ganzhi(text: str) -> GanZhi:
    """把库给的两字干支串(如 "甲辰")转成 GanZhi。"""
    gan = TianGan(_GAN.index(text[0]))
    zhi = DiZhi(_ZHI.index(text[1]))
    return GanZhi(gan, zhi)


def to_solar(moment: "datetime | Solar") -> Solar:
    """datetime 或 Solar → Solar（datetime 的年月日按「历史公历」理解，见文件开头）。"""
    if isinstance(moment, Solar):
        return moment
    return Solar.fromYmdHms(moment.year, moment.month, moment.day,
                            moment.hour, moment.minute, moment.second)


def days_in_month(year: int, month: int) -> int:
    """历史公历某月的最后一天是几号（1582 年以前按儒略历：每 4 年一闰）。
    1582 年 10 月特殊：5–14 日不存在，但最后一天仍是 31 日。"""
    return 31 if (year, month) == (1582, 10) else SolarUtil.getDaysOfMonth(year, month)


def solar_moment(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> Solar:
    """前端给的年月日时分 → Solar；日期不存在就抛 ValueError（中文说明）。"""
    if not 1 <= month <= 12:
        raise ValueError(f"月份不对：{month}")
    if year == 1582 and month == 10 and 5 <= day <= 14:
        raise ValueError("1582 年 10 月 5 日到 14 日在历史上不存在（儒略历改格里历时跳过了这 10 天）")
    if not 1 <= day <= days_in_month(year, month):
        raise ValueError(f"日期不存在：{year} 年 {month} 月没有 {day} 日")
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"时间不对：{hour}:{minute:02d}")
    return Solar.fromYmdHms(year, month, day, hour, minute, 0)


def seconds_between(a: "datetime | Solar", b: "datetime | Solar") -> int:
    """b − a 相隔多少秒（用儒略日算，跨历法、公元前都没问题）。"""
    return round((to_solar(b).getJulianDay() - to_solar(a).getJulianDay()) * 86400)


def ymdhm(moment: "datetime | Solar") -> str:
    """'YYYY-MM-DD HH:MM'（公元 1000 年以前年份补足 4 位，如 0618）。"""
    return to_solar(moment).toYmdHms()[:16]


def _lunar(moment: "datetime | Solar"):
    """把一个时刻交给 lunar_python，拿到它的 Lunar 对象。"""
    return to_solar(moment).getLunar()


def sizhu_of(jieqi_moment: datetime, local_moment: datetime | None = None) -> SiZhu:
    """返回四柱。年/月 与 日/时 可用不同时刻算：

      jieqi_moment —— 定年、月(节气锚定北京时间的那个时刻)
      local_moment —— 定日、时(当地真太阳时)；省略时四柱都用 jieqi_moment

    用 lunar_python 的 Exact 取法：
      年——按立春精确时刻翻
      月——按节(节令)精确时刻翻
      日——日界在23:00，不分早晚子
      时——子时按新一天的日干起
    """
    if local_moment is None:
        local_moment = jieqi_moment
    ym = _lunar(jieqi_moment)
    dh = _lunar(local_moment)
    return SiZhu(
        year=_parse_ganzhi(ym.getYearInGanZhiExact()),
        month=_parse_ganzhi(ym.getMonthInGanZhiExact()),
        day=_parse_ganzhi(dh.getDayInGanZhiExact()),
        hour=_parse_ganzhi(dh.getTimeInGanZhi()),
    )


def lunar_info(moment: datetime) -> dict:
    """农历日期 + 前后最近两个节气(按传入的北京时间算，全球统一)。"""
    lunar = _lunar(moment)
    prev = lunar.getPrevJieQi()
    nxt = lunar.getNextJieQi()
    return {
        "lunar_date": lunar.toString(),
        "month": abs(lunar.getMonth()),   # 农历月数字；闰月库返回负数，取绝对值(闰二月→2)
        "day": lunar.getDay(),            # 农历日数字
        "prev_jieqi": {"name": prev.getName(), "time": prev.getSolar().toYmdHms()},
        "next_jieqi": {"name": nxt.getName(), "time": nxt.getSolar().toYmdHms()},
    }


def day_brief(moment: datetime) -> dict:
    """某日的历法简要（给日历格用）：农历月日中文标签 + 日干支 + 当天节气(无则 None)。"""
    lunar = _lunar(moment)
    m = lunar.getMonth()
    # getMonthInChinese() 对闰月已带"闰"(如"闰十")，不要再自己加前缀，否则成"闰闰十月"。
    label = lunar.getMonthInChinese() + "月" + lunar.getDayInChinese()
    return {
        "lunar_month": abs(m),
        "lunar_day": lunar.getDay(),
        "is_leap_month": m < 0,
        "lunar_label": label,                       # 如 "八月廿一"、"闰六月初三"
        "day_ganzhi": lunar.getDayInGanZhi(),       # 民用日干支，如 "戊申"
        "jieqi": lunar.getJieQi() or None,          # 当天恰为节气则给名，否则 None
    }


def lunar_to_solar(year: int, month: int, day: int,
                   hour: int = 0, minute: int = 0) -> datetime:
    """农历 → 公历 datetime。闰月用负数月份(lunar_python 约定，如闰二月 month=-2)。"""
    s = Lunar.fromYmdHms(year, month, day, hour, minute, 0).getSolar()
    return datetime(s.getYear(), s.getMonth(), s.getDay(),
                    s.getHour(), s.getMinute(), s.getSecond())


def lunar_to_solar_moment(year: int, month: int, day: int, hour: int = 0, minute: int = 0,
                          is_leap: bool = False) -> Solar:
    """农历 → 公历时刻（Solar，支持古代：1582 年以前的公历是儒略历）。
    month 填 1–12，闰月 is_leap=True；这个月不存在、或这天超过当月天数，抛 ValueError（中文说明）。"""
    want = -month if is_leap else month
    found = next((m for m in LunarYear.fromYear(year).getMonths()
                  if m.getYear() == year and m.getMonth() == want), None)
    if found is None:
        raise ValueError(f"农历 {year} 年没有{'闰' if is_leap else ''}{month} 月")
    if not 1 <= day <= found.getDayCount():
        raise ValueError(f"农历 {year} 年{'闰' if is_leap else ''}{month} 月只有 {found.getDayCount()} 天")
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"时间不对：{hour}:{minute:02d}")
    return Lunar.fromYmdHms(year, want, day, hour, minute, 0).getSolar()


def lichun_of(solar_year: int) -> datetime:
    """某公历年的立春时刻(北京时间)。"""
    lc = _lunar(datetime(solar_year, 6, 1)).getJieQiTable()["立春"]
    return datetime(lc.getYear(), lc.getMonth(), lc.getDay(),
                    lc.getHour(), lc.getMinute(), lc.getSecond())


def solar_to_lunar(year: int, month: int, day: int,
                   hour: int = 0, minute: int = 0) -> dict:
    """公历 → 农历：年 / 月(1-12) / 是否闰月 / 日。公历按历史公历（1582 年以前儒略历）。"""
    lunar = _lunar(solar_moment(year, month, day, hour, minute))
    m = lunar.getMonth()
    return {
        "lunar_year": lunar.getYear(),
        "lunar_month": abs(m),
        "is_leap": m < 0,
        "lunar_day": lunar.getDay(),
    }


_MONTH_LABELS = ("正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊")


def lunar_months(year: int) -> list[dict]:
    """某农历年的月份结构：[{month(1-12), is_leap, days, label}, ...]，闰月自然在列。"""
    result = []
    for m in LunarYear.fromYear(year).getMonths():
        if m.getYear() != year:
            continue
        mon = m.getMonth()
        leap = mon < 0
        number = abs(mon)
        label = ("闰" if leap else "") + _MONTH_LABELS[number - 1] + "月"
        result.append({"month": number, "is_leap": leap,
                       "days": m.getDayCount(), "label": label})
    return result

def _solar_to_datetime(s) -> datetime:
    """
        因为节气的时间在lunar_python中是solor
    """
    return datetime(s.getYear(), s.getMonth(), s.getDay(),
                s.getHour(), s.getMinute(), s.getSecond())

def get_pre_and_next_jie(time: "datetime | Solar") -> tuple[Solar, Solar]:
    """time 前后最近的两个「节」的时刻（Solar：公元 1 年初的前一个节在公元前，datetime 表示不了）。"""
    lunar = _lunar(time)
    return lunar.getPrevJie().getSolar(), lunar.getNextJie().getSolar()


def jie_before(time: "datetime | Solar") -> tuple[str, int]:
    """time 前面最近的「节」：返回 (节名, 相隔天数)。用于「某节后第几天交运」。"""
    jie = _lunar(time).getPrevJie()
    return jie.getName(), math.floor(seconds_between(jie.getSolar(), time) / 86400)
