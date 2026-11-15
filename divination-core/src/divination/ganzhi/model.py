"""model —— 干支历的数据类型层：只定义"是什么"，不写任何算法。

天干(10) + 地支(12) 两两同步前进，组成六十甲子(0–59)。
四柱(年月日时)各是一个干支，合称八字。
风格对齐 iching/model：IntEnum 存序号，frozen dataclass 存不可变的柱。
"""
from dataclasses import dataclass
from enum import Enum, IntEnum


class WuXing(IntEnum):
    mu = 0
    huo = 1
    tu = 2
    jin = 3
    shui = 4

    @property
    def hanzi(self) -> str:
        return "木火土金水"[self.value]

class YinYang(IntEnum):
    yin = 1
    yang = 0

    @property
    def hanzi(self) -> str:
        return "阳阴"[self.value]


class TianGan(IntEnum):
    """天干，0–9。序号即六十甲子里天干的推进序。"""
    jia = 0   # 甲
    yi = 1    # 乙
    bing = 2  # 丙
    ding = 3  # 丁
    wu = 4    # 戊
    ji = 5    # 己
    geng = 6  # 庚
    xin = 7   # 辛
    ren = 8   # 壬
    gui = 9   # 癸

    @property
    def hanzi(self) -> str:
        """给 UI 显示用的汉字。"""
        return "甲乙丙丁戊己庚辛壬癸"[self.value]
    @property
    def wuxing(self) -> WuXing:
        return WuXing(self.value // 2)

    @property
    def yinyang(self) -> YinYang:
        """天干阴阳：偶数位(甲丙戊庚壬)为阳，奇数位为阴。"""
        return YinYang(self.value % 2)


# 地支五行查表
_DIZHI_WUXING = (
    WuXing.shui,  # 子
    WuXing.tu,    # 丑
    WuXing.mu,    # 寅
    WuXing.mu,    # 卯
    WuXing.tu,    # 辰
    WuXing.huo,   # 巳
    WuXing.huo,   # 午
    WuXing.tu,    # 未
    WuXing.jin,   # 申
    WuXing.jin,   # 酉
    WuXing.tu,    # 戌
    WuXing.shui,  # 亥
)

class DiZhi(IntEnum):
    """地支，0–11。子=0，也对应时辰（子时=0）。"""
    zi = 0    # 子
    chou = 1  # 丑
    yin = 2   # 寅
    mao = 3   # 卯
    chen = 4  # 辰
    si = 5    # 巳
    wu = 6    # 午
    wei = 7   # 未
    shen = 8  # 申
    you = 9   # 酉
    xu = 10   # 戌
    hai = 11  # 亥

    @property
    def hanzi(self) -> str:
        return "子丑寅卯辰巳午未申酉戌亥"[self.value]

    @property
    def wuxing(self) -> WuXing:
        """地支五行：无干净公式，查表。"""
        return _DIZHI_WUXING[self.value]

    @property
    def yinyang(self) -> YinYang:
        """地支阴阳：偶数位(子寅辰午申戌)为阳，奇数位为阴。"""
        return YinYang(self.value % 2)
    
    @property
    def canggan(self) -> tuple[TianGan, ...]:
        return _CANGGAN[self.value]


@dataclass(frozen=True)
class GanZhi:
    """干支：一个天干配一个地支，六十甲子之一"""
    gan: TianGan
    zhi: DiZhi

    def __post_init__(self) -> None:
        if (self.gan - self.zhi) % 2 != 0:
            raise ValueError(f"非法干支组合：{self.gan.hanzi}{self.zhi.hanzi}")

    @property
    def index(self) -> int:
        """六十甲子序号 0–59（甲子=0）。

        要找同时满足 n%10==gan、n%12==zhi 的 n，
        闭式解就是下面这行（6、5 是推出来的系数）。
        """
        return (6 * self.gan - 5 * self.zhi) % 60

    @property
    def name(self) -> str:
        return f"{self.gan.hanzi}{self.zhi.hanzi}"

    @classmethod
    def from_index(cls, n: int) -> "GanZhi":
        """由六十甲子序号反推干支（日柱循环会用到）。"""
        return cls(TianGan(n % 10), DiZhi(n % 12))

    @property
    def nayin(self) -> str:
        return _NAYIN[self.index // 2]


@dataclass(frozen=True)
class SiZhu:
    """四柱：年、月、日、时各一个干支，即生辰八字。"""
    year: GanZhi
    month: GanZhi
    day: GanZhi
    hour: GanZhi


class JieQi(Enum):
    """二十四节气，按立春起序。值用简体，和 lunar_python 输出一致。

    12 个"节"是干支月的分界（立春、惊蛰、清明…），
    另外 12 个"中气"（雨水、春分…）给农历定闰月用。
    """
    li_chun = "立春"
    yu_shui = "雨水"
    jing_zhe = "惊蛰"
    chun_fen = "春分"
    qing_ming = "清明"
    gu_yu = "谷雨"
    li_xia = "立夏"
    xiao_man = "小满"
    mang_zhong = "芒种"
    xia_zhi = "夏至"
    xiao_shu = "小暑"
    da_shu = "大暑"
    li_qiu = "立秋"
    chu_shu = "处暑"
    bai_lu = "白露"
    qiu_fen = "秋分"
    han_lu = "寒露"
    shuang_jiang = "霜降"
    li_dong = "立冬"
    xiao_xue = "小雪"
    da_xue = "大雪"
    dong_zhi = "冬至"
    xiao_han = "小寒"
    da_han = "大寒"

    @property
    def is_jie(self) -> bool:
        """是否为"节"（干支月的分界）。"""
        return self in _JIE


# 12 个"节"：干支月由它们分界（对应寅月…丑月的起点）
_JIE = frozenset({
    JieQi.li_chun, JieQi.jing_zhe, JieQi.qing_ming, JieQi.li_xia,
    JieQi.mang_zhong, JieQi.xiao_shu, JieQi.li_qiu, JieQi.bai_lu,
    JieQi.han_lu, JieQi.li_dong, JieQi.da_xue, JieQi.xiao_han,
})

# 地支藏干(子…亥序)，每格按「本气→中气→余气」排，1~3 个不等。
_CANGGAN = (
    (TianGan.gui,),                             # 子: 癸
    (TianGan.ji, TianGan.gui, TianGan.xin),     # 丑: 己癸辛
    (TianGan.jia, TianGan.bing, TianGan.wu),    # 寅: 甲丙戊
    (TianGan.yi,),                              # 卯: 乙
    (TianGan.wu, TianGan.yi, TianGan.gui),      # 辰: 戊乙癸
    (TianGan.bing, TianGan.geng, TianGan.wu),   # 巳: 丙庚戊
    (TianGan.ding, TianGan.ji),                 # 午: 丁己
    (TianGan.ji, TianGan.ding, TianGan.yi),     # 未: 己丁乙
    (TianGan.geng, TianGan.ren, TianGan.wu),    # 申: 庚壬戊
    (TianGan.xin,),                             # 酉: 辛
    (TianGan.wu, TianGan.xin, TianGan.ding),    # 戌: 戊辛丁
    (TianGan.ren, TianGan.jia),                 # 亥: 壬甲
)

_NAYIN = (
    "海中金", "炉中火", "大林木", "路旁土", "剑锋金",
    "山头火", "涧下水", "城头土", "白蜡金", "杨柳木",
    "泉中水", "屋上土", "霹雳火", "松柏木", "长流水",
    "砂中金", "山下火", "平地木", "壁上土", "金箔金",
    "覆灯火", "天河水", "大驿土", "钗钏金", "桑柘木",
    "大溪水", "沙中土", "天上火", "石榴木", "大海水",
)