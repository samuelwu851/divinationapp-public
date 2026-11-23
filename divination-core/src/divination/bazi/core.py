from datetime import timedelta

from lunar_python import Solar

from divination.ganzhi.model import DiZhi, GanZhi, TianGan, YinYang
from divination.ganzhi.repository import days_in_month

# (五行关系 delta, 是否同阴阳) → 十神名
# delta = (对方五行 − 日主五行) % 5：0 同我 / 1 我生 / 2 我克 / 3 克我 / 4 生我
_SHISHEN = {
    (0, True): "比肩", (0, False): "劫财",   # 同我
    (1, True): "食神", (1, False): "伤官",   # 我生
    (2, True): "偏财", (2, False): "正财",   # 我克
    (3, True): "七杀", (3, False): "正官",   # 克我
    (4, True): "偏印", (4, False): "正印",   # 生我
}

def shishen(day: TianGan, other: TianGan) -> str:
    delta = (other.wuxing - day.wuxing) % 5
    same_yinyang = day.yinyang == other.yinyang
    return _SHISHEN[(delta, same_yinyang)]

def canggan_shishen(tg: TianGan, dz:DiZhi) -> list[tuple[TianGan,str]]:
    """
    接收参数：
    tg：日主
    dz：地支

    for循环中定义的参数：
    gan：地支藏干
    """
    return [(gan, shishen(tg, gan)) for gan in dz.canggan]

def is_dayun_clockwise(year:TianGan, is_male:bool):
    clockwise = False # 大运逆排
    if (year.yinyang == YinYang.yang and is_male is True) or (year.yinyang == YinYang.yin and is_male is False):
        clockwise = True # 大运顺排
    return clockwise

def dayun_ganzhi(year:TianGan, month:GanZhi, is_male:bool, count: int = 11) -> list[GanZhi]:
    clockwise = is_dayun_clockwise(year, is_male)
    step = 1 if clockwise else -1
    return [GanZhi.from_index((month.index + step * i) % 60) for i in range(1, count)]

def qiyun_age(delta: timedelta) -> tuple[int, int, int]:
    """交节时间差 → 起运(岁, 月, 日)。古法口诀三条：
        三天折一岁、一天折四月、一时辰(2 小时)折十天。
    即 1 实际日 = 120 起运日(= 4 个月)、1 时辰 = 10 起运日；
    古法一年 360 日、一月 30 日。

    关键：按「整天 + 整时辰」离散取整，**不足一个时辰的零碎分秒舍去**。
    这是传统排盘的通行口径——若改成按秒连续换算，零碎会被放大 120 倍，
    一个多小时就能多算出 5 天起运。
    """
    days, rem = divmod(int(delta.total_seconds()), 86400)
    shichen = rem // 7200                             # 余下秒折整时辰，不足一辰舍去
    unit_days = days * 120 + shichen * 10             # 起运日总量
    years, rem_units = divmod(unit_days, 360)
    months, days_out = divmod(rem_units, 30)
    return years, months, days_out

def add_ymd(s: Solar, years: int, months: int, days: int) -> Solar:
    """在日期上加「年、月、日」：先把年月累加进位、按月末钳日，最后加天。
    用于「出生时刻 + 起运岁月日 = 交运时刻」、第 X 步大运的交接时刻。
    用 Solar（历史公历：1582 年以前是儒略历），所以古代日期的月长、闰年都按当时的历法算。
    """
    total = (s.getYear() * 12 + s.getMonth() - 1) + years * 12 + months  # 换算成「总月数」再进位
    year, month = divmod(total, 12)
    month += 1                                                   # 月份从 1 开始
    day = min(s.getDay(), days_in_month(year, month))            # 防止 1/31 + 1月 落到不存在的 2/31
    if (year, month) == (1582, 10) and 5 <= day <= 14:           # 历史上不存在的 10 天 → 落到 15 日
        day = 15
    base = Solar.fromYmdHms(year, month, day, s.getHour(), s.getMinute(), s.getSecond())
    return base.next(days) if days else base

def liunian_ganzhi(year: int) -> GanZhi:
    """某公历年的干支(立春后)。公元 4 年为甲子，故 (年 - 4) % 60。"""
    return GanZhi.from_index((year - 4) % 60)

def liuyue_ganzhi(year: int) -> list[GanZhi]:
    """某流年的 12 个月柱(正月=寅月起)。五虎遁定正月月干：
    「甲己之年丙作首」——正月月干 = ((年干 % 5) * 2 + 2) % 10。"""
    year_gan = liunian_ganzhi(year).gan                  # 复用:该年年干
    first_gan = ((year_gan % 5) * 2 + 2) % 10            # 正月(寅月)月干
    start = GanZhi(TianGan(first_gan), DiZhi.yin).index  # 正月 = 寅
    return [GanZhi.from_index((start + i) % 60) for i in range(12)]