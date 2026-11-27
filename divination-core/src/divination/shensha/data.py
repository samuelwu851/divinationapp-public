"""神煞数据：出自《大六壬指南》卷五（庄广之《神煞指南》）。

第一版只收「落在地支上、书里前后没有矛盾」的神煞；有冲突或要看天将 / 三传的，见文末 DEFERRED。

两种写法：
- S(名字, 类别, 按什么起, 起点, 步长)：位置 = 起点 + 步长 × 序号（地支循环）。
  序号：年支 / 日支从子起 0；年干 / 日干从甲起 0；月从寅月起 0（立春起寅月，书里的「正月」就是寅月）；
       季节春 0、夏 1、秋 2、冬 3。
  起点就是序号为 0 时的位置（子年、甲日、寅月、春季）。
  步长：顺行十二 +1、逆行十二 -1、逆四孟 / 四仲 / 四季 -3、顺 +3、六个月一轮 +2。
- T(名字, 类别, 按什么起, 值)：不规律的直接列表，按序号一一对应；一格可以有几个地支（如日鬼壬日「辰戌」）。

少数要另外算的（旬煞、瓦煞、天转地转）在 core.py 里。
"""
from typing import NamedTuple

ZHI = "子丑寅卯辰巳午未申酉戌亥"
GAN = "甲乙丙丁戊己庚辛壬癸"

# 类别（显示顺序）
SUI = "岁煞"
JI = "季煞"
YUE = "月煞"
XUN = "旬煞"
RIGAN = "日干煞"
RIZHI = "日支煞"
DANGRI = "当日神煞"
CATEGORIES = [SUI, JI, YUE, XUN, RIGAN, RIZHI, DANGRI]

# 按什么起
YEAR_ZHI = "year_zhi"
YEAR_GAN = "year_gan"
MONTH = "month"
SEASON = "season"
DAY_GAN = "day_gan"
DAY_ZHI = "day_zhi"


class Rule(NamedTuple):
    name: str
    category: str
    key: str
    start: str | None = None        # S：序号为 0 时的地支
    step: int = 0                   # S：每过一个序号走几步
    values: tuple = ()              # T：每个序号对应的地支（字符串，可含多个地支）
    alias: str = ""                 # 别名（如 太阳「青龙、赶煞」）


def S(name, category, key, start, step, alias=""):
    return Rule(name, category, key, start=start, step=step, alias=alias)


def T(name, category, key, values, alias=""):
    return Rule(name, category, key, values=tuple(values), alias=alias)   # 字符串 "子丑…" 每个字一格


RULES: list[Rule] = [
    # ======== 岁煞 ========
    # 太岁一圈：从年支顺排（第 4 位「六合」、第 8 位「岁墓」有疑问，暂缓）
    S("太岁", SUI, YEAR_ZHI, "子", +1),
    S("太阳", SUI, YEAR_ZHI, "丑", +1, alias="青龙、赶煞"),
    S("丧门", SUI, YEAR_ZHI, "寅", +1),
    S("年官符", SUI, YEAR_ZHI, "辰", +1),
    S("小耗", SUI, YEAR_ZHI, "巳", +1, alias="岁宅"),
    S("岁破", SUI, YEAR_ZHI, "午", +1, alias="大耗、迫煞"),
    S("白虎", SUI, YEAR_ZHI, "申", +1),
    S("福德", SUI, YEAR_ZHI, "酉", +1),
    S("吊客", SUI, YEAR_ZHI, "戌", +1, alias="太阴"),
    S("病符", SUI, YEAR_ZHI, "亥", +1),
    # 岁驿一圈：从年支三合的驿马起顺排（子年驿马寅；申子辰 → 寅，亥卯未 → 巳 … 即起寅、逆四孟）
    S("驿马", SUI, YEAR_ZHI, "寅", -3),
    S("六害", SUI, YEAR_ZHI, "卯", -3),
    S("华盖", SUI, YEAR_ZHI, "辰", -3, alias="黄幡"),
    S("劫煞", SUI, YEAR_ZHI, "巳", -3),
    S("灾煞", SUI, YEAR_ZHI, "午", -3),
    S("天煞", SUI, YEAR_ZHI, "未", -3),
    S("地煞", SUI, YEAR_ZHI, "申", -3),
    S("年桃花", SUI, YEAR_ZHI, "酉", -3),
    S("豹尾", SUI, YEAR_ZHI, "戌", -3),
    S("亡神", SUI, YEAR_ZHI, "亥", -3),
    S("将星", SUI, YEAR_ZHI, "子", -3),
    S("攀鞍", SUI, YEAR_ZHI, "丑", -3),
    # 直图
    T("天庭", SUI, YEAR_GAN, "丑寅辰巳辰巳未申戌亥"),        # 岁干禄后
    T("死符", SUI, YEAR_GAN, "申申亥亥寅寅巳巳辰辰"),
    T("岁刑", SUI, YEAR_ZHI, "卯戌巳子辰申午丑寅酉未亥"),
    T("大将军", SUI, YEAR_ZHI, "酉酉子子子卯卯卯午午午酉"),

    # ======== 季煞（春夏秋冬，每季走三步） ========
    S("天喜", JI, SEASON, "戌", +3),
    S("天耳", JI, SEASON, "戌", +3),
    S("寡宿", JI, SEASON, "丑", +3),
    S("三丘", JI, SEASON, "丑", +3),
    S("关神", JI, SEASON, "丑", +3),
    S("管神", JI, SEASON, "丑", +3),
    S("皇书", JI, SEASON, "寅", +3),
    S("战雄", JI, SEASON, "寅", +3),
    S("吏神", JI, SEASON, "寅", +3),
    S("贼神", JI, SEASON, "卯", +3),
    S("奸盗", JI, SEASON, "卯", +3),
    S("转煞", JI, SEASON, "卯", +3),
    S("丝麻", JI, SEASON, "卯", +3),
    S("浴盆", JI, SEASON, "辰", +3),
    S("龙神", JI, SEASON, "辰", +3),
    S("喝散", JI, SEASON, "巳", +3),
    S("孤辰", JI, SEASON, "巳", +3),
    S("梁神", JI, SEASON, "巳", +3),
    S("钥神", JI, SEASON, "巳", +3),
    S("火鬼", JI, SEASON, "午", +3),
    S("哭神", JI, SEASON, "未", +3),
    S("五墓", JI, SEASON, "未", +3),
    S("地狱", JI, SEASON, "未", +3),
    S("煞神", JI, SEASON, "申", +3),
    S("绝气", JI, SEASON, "申", +3),
    S("战雌", JI, SEASON, "申", +3),
    S("四废", JI, SEASON, "酉", +3),
    S("丧车", JI, SEASON, "酉", +3),
    # 方图里按四时起的
    T("大德", JI, SEASON, "午辰子寅"),
    T("戏神", JI, SEASON, "巳子酉辰"),
    T("天车", JI, SEASON, "巳辰未酉"),
    T("死别", JI, SEASON, "戌未辰丑"),
    T("奸神", JI, SEASON, "寅亥申巳"),
    T("飞祸", JI, SEASON, "申寅巳亥"),
    T("时盗", JI, SEASON, "巳卯酉子"),

    # ======== 月煞 ========
    # 正起顺行（寅月在此，按月顺行十二）
    S("月建", YUE, MONTH, "寅", +1),
    S("小时", YUE, MONTH, "寅", +1),
    S("天虎", YUE, MONTH, "寅", +1),
    S("木煞", YUE, MONTH, "寅", +1),
    S("天龙", YUE, MONTH, "卯", +1),
    S("天医", YUE, MONTH, "辰", +1),
    S("雌虎", YUE, MONTH, "辰", +1),
    S("瘟煞", YUE, MONTH, "辰", +1),
    S("天巫", YUE, MONTH, "辰", +1),
    S("厄煞", YUE, MONTH, "巳", +1),
    S("孝杖", YUE, MONTH, "巳", +1),
    S("死神", YUE, MONTH, "巳", +1),
    S("电煞", YUE, MONTH, "巳", +1),
    S("火烛", YUE, MONTH, "巳", +1),
    S("死气", YUE, MONTH, "午", +1),
    S("月官符", YUE, MONTH, "午", +1),
    S("孝服", YUE, MONTH, "午", +1),
    S("谩语", YUE, MONTH, "午", +1),
    S("井煞", YUE, MONTH, "未", +1),
    S("枯骨", YUE, MONTH, "未", +1),
    S("小耗", YUE, MONTH, "未", +1),
    S("天印", YUE, MONTH, "未", +1),
    S("天羊", YUE, MONTH, "未", +1),
    S("福神", YUE, MONTH, "未", +1),
    S("月破", YUE, MONTH, "申", +1),
    S("兵煞", YUE, MONTH, "申", +1),
    S("大耗", YUE, MONTH, "申", +1),
    S("道路神", YUE, MONTH, "申", +1),
    S("书信", YUE, MONTH, "酉", +1),
    S("天机", YUE, MONTH, "酉", +1),
    S("天钱", YUE, MONTH, "酉", +1),
    S("天书", YUE, MONTH, "戌", +1),
    S("愿神", YUE, MONTH, "戌", +1),
    S("地医", YUE, MONTH, "戌", +1),
    S("飞魂", YUE, MONTH, "亥", +1),
    S("伏连", YUE, MONTH, "亥", +1),
    S("天诏", YUE, MONTH, "亥", +1),
    S("病煞", YUE, MONTH, "亥", +1),
    S("儿煞", YUE, MONTH, "亥", +1),
    S("哭忌", YUE, MONTH, "亥", +1),
    S("生气", YUE, MONTH, "子", +1),
    S("雨煞", YUE, MONTH, "子", +1),
    S("血支", YUE, MONTH, "丑", +1),
    S("天坑", YUE, MONTH, "丑", +1),
    S("佛煞", YUE, MONTH, "丑", +1),
    S("天牛", YUE, MONTH, "丑", +1),
    S("坟墓", YUE, MONTH, "丑", +1),
    # 正起逆行（寅月在此，按月逆行十二）
    S("神煞", YUE, MONTH, "亥", -1),
    S("天猪", YUE, MONTH, "亥", -1),
    S("天鼠", YUE, MONTH, "子", -1),
    S("天视", YUE, MONTH, "子", -1),
    S("天怪", YUE, MONTH, "丑", -1),
    S("风煞", YUE, MONTH, "寅", -1),
    S("烛命", YUE, MONTH, "卯", -1),
    S("厌对", YUE, MONTH, "辰", -1),
    S("血光", YUE, MONTH, "辰", -1),
    S("月害", YUE, MONTH, "巳", -1),
    S("阴煞", YUE, MONTH, "巳", -1),
    S("破器", YUE, MONTH, "午", -1),
    S("化神", YUE, MONTH, "午", -1),
    S("地咒", YUE, MONTH, "午", -1),
    S("阴奸", YUE, MONTH, "未", -1),
    S("邪神", YUE, MONTH, "未", -1),
    S("天猴", YUE, MONTH, "申", -1),
    S("风伯", YUE, MONTH, "申", -1),
    S("天解", YUE, MONTH, "申", -1),
    S("轩辕", YUE, MONTH, "酉", -1),
    S("天鸡", YUE, MONTH, "酉", -1),
    S("折伤", YUE, MONTH, "酉", -1),
    S("天狗", YUE, MONTH, "戌", -1),
    S("四足", YUE, MONTH, "戌", -1),
    S("月厌", YUE, MONTH, "戌", -1),
    S("石煞", YUE, MONTH, "戌", -1),
    S("火光", YUE, MONTH, "戌", -1),
    # 正五九 / 二六十 / 三七冬 / 四八腊 四个月一轮：逆行（如 申巳寅亥）
    S("驿马", YUE, MONTH, "申", -3),
    S("天鬼", YUE, MONTH, "酉", -3),
    S("天吏", YUE, MONTH, "酉", -3),
    S("长绳", YUE, MONTH, "酉", -3),
    S("天咒", YUE, MONTH, "酉", -3),
    S("光影", YUE, MONTH, "戌", -3),
    S("火怪", YUE, MONTH, "戌", -3),
    S("黄幡", YUE, MONTH, "戌", -3),
    S("天狱", YUE, MONTH, "亥", -3),
    S("墓门", YUE, MONTH, "亥", -3),
    S("天网", YUE, MONTH, "亥", -3),
    S("女灾", YUE, MONTH, "亥", -3),
    S("雷煞", YUE, MONTH, "亥", -3),
    S("劫煞", YUE, MONTH, "亥", -3),
    S("坑坎", YUE, MONTH, "子", -3),
    S("山魈", YUE, MONTH, "子", -3),
    S("灾煞", YUE, MONTH, "子", -3),
    S("镜煞", YUE, MONTH, "子", -3),
    S("披麻", YUE, MONTH, "子", -3),
    S("五盗", YUE, MONTH, "丑", -3),
    S("小煞", YUE, MONTH, "丑", -3),
    S("天煞", YUE, MONTH, "丑", -3),
    S("迷惑", YUE, MONTH, "丑", -3),
    S("月煞", YUE, MONTH, "丑", -3),
    S("天盗", YUE, MONTH, "寅", -3),
    S("雷公", YUE, MONTH, "寅", -3),
    S("月桃花", YUE, MONTH, "卯", -3, alias="桃花咸池"),
    S("悬索", YUE, MONTH, "卯", -3),
    S("大时", YUE, MONTH, "卯", -3),
    S("邪鬼", YUE, MONTH, "辰", -3),
    S("亡神", YUE, MONTH, "巳", -3),
    S("游祸", YUE, MONTH, "巳", -3),
    S("大煞", YUE, MONTH, "午", -3),
    S("伏骨", YUE, MONTH, "午", -3),
    S("下丧", YUE, MONTH, "未", -3),
    S("月鬼", YUE, MONTH, "未", -3),
    S("秽煞", YUE, MONTH, "未", -3),
    S("丧魄", YUE, MONTH, "未", -3),
    # 四个月一轮：顺行（如 巳申亥寅）
    S("天旺", YUE, MONTH, "巳", +3),
    S("成神", YUE, MONTH, "巳", +3),
    S("天破", YUE, MONTH, "午", +3),
    S("香炉", YUE, MONTH, "未", +3),
    S("丧门", YUE, MONTH, "未", +3),
    S("狱神", YUE, MONTH, "未", +3),
    S("奸门", YUE, MONTH, "申", +3),
    S("天信", YUE, MONTH, "酉", +3),
    S("反激", YUE, MONTH, "戌", +3),
    S("阳煞", YUE, MONTH, "亥", +3),
    S("邪督", YUE, MONTH, "子", +3),
    S("天火", YUE, MONTH, "子", +3),
    S("雨师", YUE, MONTH, "子", +3),
    S("月奸", YUE, MONTH, "丑", +3),
    S("釜神", YUE, MONTH, "寅", +3),
    S("产煞", YUE, MONTH, "寅", +3),
    S("天厕", YUE, MONTH, "寅", +3),
    S("奸私", YUE, MONTH, "寅", +3),
    S("盗神", YUE, MONTH, "卯", +3),
    S("天械", YUE, MONTH, "辰", +3),
    S("上丧", YUE, MONTH, "辰", +3),
    # 六个月一轮（正七同、二八同……）
    S("天马", YUE, MONTH, "午", +2),
    S("天财", YUE, MONTH, "辰", +2),
    S("天刑", YUE, MONTH, "寅", +2),
    S("怪煞", YUE, MONTH, "卯", +2),
    S("兽煞", YUE, MONTH, "戌", +2),
    # 单月顺行、双月取冲
    T("圣心", YUE, MONTH, "亥巳子午丑未寅申卯酉辰戌"),
    T("玉宇", YUE, MONTH, "卯酉辰戌巳亥午子未丑申寅"),
    T("金堂", YUE, MONTH, "辰戌巳亥午子未丑申寅酉卯"),
    T("受死", YUE, MONTH, "戌辰亥巳子午丑未寅申卯酉"),
    T("罪至", YUE, MONTH, "午子未丑申寅酉卯戌辰亥巳"),
    T("血忌", YUE, MONTH, "丑未寅申卯酉辰戌巳亥午子"),
    # 方图里的月表
    T("地解", YUE, MONTH, "申申酉酉戌戌亥亥午午未未"),
    T("解神", YUE, MONTH, "申申戌戌子子寅寅辰辰午午"),
    T("会神", YUE, MONTH, "未戌寅亥酉子丑午巳卯申辰"),
    T("月破碎", YUE, MONTH, "酉巳丑酉巳丑酉巳丑酉巳丑", alias="金神破碎"),
    T("归忌", YUE, MONTH, "丑寅子丑寅子丑寅子丑寅子"),
    T("往亡", YUE, MONTH, "寅巳申亥卯午酉子辰未戌丑"),
    T("月刑", YUE, MONTH, "巳子辰申午丑寅酉未亥卯戌"),
    T("天贼", YUE, MONTH, "辰酉寅未子巳戌卯申丑午亥"),
    T("五鬼", YUE, MONTH, "午辰寅酉卯申丑巳子亥未戌"),
    T("相负", YUE, MONTH, "亥亥丑丑卯卯巳巳未未酉酉"),
    T("枉屈", YUE, MONTH, "巳巳未未酉酉亥亥丑丑卯卯"),
    # 瓦煞：要看日干阴阳，在 core.py 里算

    # ======== 日干煞 ========
    T("日德", RIGAN, DAY_GAN, "寅申巳亥巳寅申巳亥巳"),
    T("日合", RIGAN, DAY_GAN, "未申戌亥丑寅辰巳未巳"),
    T("日禄", RIGAN, DAY_GAN, "寅卯巳午巳午申酉亥子"),
    T("长生", RIGAN, DAY_GAN, "亥亥寅寅申申巳巳申申"),
    T("学堂", RIGAN, DAY_GAN, "亥亥寅寅申申巳巳申申"),
    T("恩赦", RIGAN, DAY_GAN, "寅辰巳未巳未申戌亥丑"),
    T("干奇", RIGAN, DAY_GAN, "午巳辰卯寅丑未申酉戌"),
    T("日解", RIGAN, DAY_GAN, "亥申未丑酉亥申未丑酉"),
    T("日医", RIGAN, DAY_GAN, "卯亥丑未巳卯亥丑未巳"),
    T("贤贵", RIGAN, DAY_GAN, "丑申寅寅午丑申寅寅午"),
    T("福星", RIGAN, DAY_GAN, "子丑子子未未丑丑巳巳"),
    #T("文星", RIGAN, DAY_GAN, "亥亥寅寅申申巳巳申申"),
    T("进神", RIGAN, DAY_GAN, ["子午"] * 5 + ["卯酉"] * 5),
    T("退神", RIGAN, DAY_GAN, ["丑未"] * 5 + ["辰戌"] * 5),
    T("日鬼", RIGAN, DAY_GAN, ["申", "酉", "亥", "子", "寅", "卯", "巳", "午", "辰戌", "丑未"]),
    T("飞符", RIGAN, DAY_GAN, "巳辰卯寅丑午未申酉戌"),
    T("羊刃", RIGAN, DAY_GAN, "卯辰午未午未酉戌子丑"),
    T("飞刃", RIGAN, DAY_GAN, "酉戌子丑子丑卯辰午未"),     # 羊刃的冲位
    T("游都", RIGAN, DAY_GAN, "丑子寅巳申丑子寅巳申"),
    T("鲁都", RIGAN, DAY_GAN, "未午申亥寅未午申亥寅"),
    T("日贼", RIGAN, DAY_GAN, "辰午申亥寅辰午申亥寅"),
    T("日盗", RIGAN, DAY_GAN, "子亥卯申巳子亥卯申巳"),
    T("日奸", RIGAN, DAY_GAN, "亥酉辰申巳亥酉辰申巳"),
    T("日淫", RIGAN, DAY_GAN, "午午未未戌戌寅寅巳巳"),
    T("大煞", RIGAN, DAY_GAN, "亥亥未未戌戌寅寅巳巳"),     # 歌诀「大煞亥未戌寅巳」，甲乙同例
    # 干马（大六壬用，书里没有）：日干寄宫的驿马。寄宫 甲寅 乙辰 丙巳 丁未 戊巳 己未 庚申 辛戌 壬亥 癸丑，
    # 再按寄宫的三合取驿马（申子辰马寅、寅午戌马申、巳酉丑马亥、亥卯未马巳）。如丁寄未 → 亥卯未 → 巳。
    T("干马", RIGAN, DAY_GAN, "申寅亥巳亥巳寅申巳亥"),

    # ======== 日支煞 ========
    T("支德", RIZHI, DAY_ZHI, "巳午未申酉戌亥子丑寅卯辰"),
    T("三合", RIZHI, DAY_ZHI, ["申辰", "巳酉", "午戌", "亥未", "申子", "酉丑",
                               "寅戌", "卯亥", "子辰", "巳丑", "寅午", "卯未"]),
    T("六合", RIZHI, DAY_ZHI, "丑子亥戌酉申未午巳辰卯寅"),
    T("支仪", RIZHI, DAY_ZHI, "午巳辰卯寅丑未申酉戌亥子"),
    T("支破", RIZHI, DAY_ZHI, "酉辰亥午丑申卯戌巳子未寅"),
    T("日破碎", RIZHI, DAY_ZHI, "巳丑酉巳丑酉巳丑酉巳丑酉"),
    T("三刑", RIZHI, DAY_ZHI, "卯戌巳子辰申午丑寅酉未亥"),
    T("支冲", RIZHI, DAY_ZHI, "午未申酉戌亥子丑寅卯辰巳"),
    T("支墓", RIZHI, DAY_ZHI, "辰辰未未辰戌戌辰丑丑辰辰"),   # 戌火丑金木墓未，辰坟水土
    T("死神", RIZHI, DAY_ZHI, "卯辰巳午未申酉戌亥子丑寅"),
    T("病符", RIZHI, DAY_ZHI, "亥子丑寅卯辰巳午未申酉戌"),
    T("勾神", RIZHI, DAY_ZHI, "卯戌巳子未寅酉辰亥午丑申"),
    T("绞神", RIZHI, DAY_ZHI, "酉辰亥午丑申卯戌巳子未寅"),
    T("驿马", RIZHI, DAY_ZHI, "寅亥申巳寅亥申巳寅亥申巳"),
    T("华盖", RIZHI, DAY_ZHI, "辰丑戌未辰丑戌未辰丑戌未"),
    T("劫煞", RIZHI, DAY_ZHI, "巳寅亥申巳寅亥申巳寅亥申"),
    T("灾煞", RIZHI, DAY_ZHI, "午卯子酉午卯子酉午卯子酉"),
    T("日桃花", RIZHI, DAY_ZHI, "酉午卯子酉午卯子酉午卯子", alias="咸池"),
    T("四煞", RIZHI, DAY_ZHI, "未辰丑戌未辰丑戌未辰丑戌"),
    T("支亡", RIZHI, DAY_ZHI, "亥申巳寅亥申巳寅亥申巳寅"),
    T("雷电", RIZHI, DAY_ZHI, "辰辰未未戌戌丑丑寅寅卯卯"),
    T("雨师", RIZHI, DAY_ZHI, "申酉戌亥子丑寅卯辰巳午未"),
    T("晴朗", RIZHI, DAY_ZHI, "午未申酉戌亥子丑寅卯辰巳"),
    T("白衣翰林", RIZHI, DAY_ZHI, "酉未巳卯丑亥酉未巳卯丑亥"),
]

# 第一版不做的（有冲突、或要看天将 / 地盘 / 三传 / 年份阴阳），以后一个个讨论
DEFERRED = {
    "冲突": ["天德", "天合", "月德", "月合", "皇恩", "飞廉", "门煞", "信神", "忧神", "泰神", "游神", "游煞",
             "白衣煞/日表", "天赦", "天目", "返魂", "刀砧", "梦神", "太岁圈第4位六合", "岁墓（龙德）",
             "支鬼", "福星的刑冲举", "日支六害（表与注解不符）"],
    "看天将或地盘": ["青龙煞", "草煞", "鸟煞", "花煞", "白虎煞", "竹煞", "床煞", "酒煞", "梯煞"],
    "看三传": ["遁奇"],
    "看年份阴阳": ["缠绕"],
    "算法不明确": ["日官", "日墓"],
}
