"""大六壬排盘：天地盘、四课、三传（九宗门）、天将、遁干、六亲、空亡、年命。

依据《大六壬心镜》释课元微门、《大六壬指南·心印赋》，取舍已和用户逐条确认，
并用《大六壬断案》《大六壬指南》卷四的课例核对过（见 tests/test_liuren.py）：
- 月将按中气换（雨水亥将 … 大寒子将），占时子时换日（日界 23:00，同八字）。
- 贵人：甲戊庚牛羊，乙己鼠猴乡，丙丁猪鸡位，壬癸蛇兔藏，六辛逢马虎（先昼后夜）；
  两种起法（排盘时选）：std 甲戊庚牛羊（每句都先昼后夜，默认）；
  alt 甲(戊)庚牛羊（每句第二个干反过来：庚昼未夜丑、己昼申夜子、丁昼酉夜亥、癸昼卯夜巳）；
  卯时至申时为昼，酉时至寅时为夜；贵人临地盘亥子丑寅卯辰顺布，巳午未申酉戌逆布。
- 涉害两种取法（排盘时选）：
    depth 深浅法：从上神所临地盘起，顺数回本家，逐位数克（地盘支一次，寄宫天干各一次）。
                  上克下的课数「上神克别人」几次，下贼上的课数「上神受克」几次。
                  深浅相同再用孟仲季，仍相同则刚日取干上神、柔日取支上神。
    mzj   孟仲季法：先取临孟的，再取临仲的，仍相同则刚日取干上、柔日取支上。
- 返吟无克（丁己辛日配丑未，井栏射）：丑日取地盘巳上神、未日取地盘亥上神为初，中传支上神，末传干上神。
"""
from divination.shensha.data import ZHI, GAN

WX_ZHI = "水土木木土火火土金金土水"          # 子丑寅卯辰巳午未申酉戌亥
WX_GAN = "木木火火土土金金水水"
KE = {"木": "土", "土": "水", "水": "火", "火": "金", "金": "木"}     # 甲克乙：KE[甲] == 乙
SHENG = {"木": "火", "火": "土", "土": "金", "金": "水", "水": "木"}

# 日干寄宫
JIGONG = {"甲": "寅", "乙": "辰", "丙": "巳", "丁": "未", "戊": "巳",
          "己": "未", "庚": "申", "辛": "戌", "壬": "亥", "癸": "丑"}
# 地盘某支上寄着哪些天干（涉害数克用）
JI_GAN = {}
for _g, _z in JIGONG.items():
    JI_GAN.setdefault(_z, []).append(_g)

# 中气 → 月将
QI_JIANG = {"雨水": "亥", "春分": "戌", "谷雨": "酉", "小满": "申", "夏至": "未", "大暑": "午",
            "处暑": "巳", "秋分": "辰", "霜降": "卯", "小雪": "寅", "冬至": "丑", "大寒": "子"}

TIAN_JIANG = ["贵人", "螣蛇", "朱雀", "六合", "勾陈", "青龙", "天空", "白虎", "太常", "玄武", "太阴", "天后"]
GUI_DAY = {"甲": "丑", "戊": "丑", "庚": "丑", "乙": "子", "己": "子", "丙": "亥", "丁": "亥",
           "辛": "午", "壬": "巳", "癸": "巳"}
GUI_NIGHT = {"甲": "未", "戊": "未", "庚": "未", "乙": "申", "己": "申", "丙": "酉", "丁": "酉",
             "辛": "寅", "壬": "卯", "癸": "卯"}
GUIREN_FLIP = {"庚", "己", "丁", "癸"}      # 甲(戊)庚牛羊：口诀里每句的第二个干昼夜对调
GUIREN_METHODS = ("std", "alt")

XING = {"子": "卯", "卯": "子", "寅": "巳", "巳": "申", "申": "寅",
        "丑": "戌", "戌": "未", "未": "丑", "辰": "辰", "午": "午", "酉": "酉", "亥": "亥"}
SANHE = ["申子辰", "亥卯未", "寅午戌", "巳酉丑"]


def zi(z: str) -> int:
    return ZHI.index(z)


def shift(z: str, n: int) -> str:
    return ZHI[(zi(z) + n) % 12]


def wx(c: str) -> str:
    return WX_GAN[GAN.index(c)] if c in GAN else WX_ZHI[zi(c)]


def is_yang(c: str) -> bool:
    return (GAN.index(c) if c in GAN else zi(c)) % 2 == 0


def ke(a: str, b: str) -> bool:
    """a 克 b（天干地支都可以）。"""
    return KE[wx(a)] == wx(b)


def mzj(z: str) -> int:
    """孟 0、仲 1、季 2。"""
    return {0: 1, 1: 2, 2: 0}[zi(z) % 3]


# ---------- 天地盘 ----------

class Pan:
    """天地盘：地盘固定，月将加占时。up(地盘支) = 天盘支；down(天盘支) = 所临地盘支。"""

    def __init__(self, yuejiang: str, shi: str):
        self.off = (zi(yuejiang) - zi(shi)) % 12

    def up(self, z: str) -> str:
        return shift(z, self.off)

    def down(self, z: str) -> str:
        return shift(z, -self.off)


def sike(pan: Pan, gan: str, zhi: str) -> list[dict]:
    """四课：[{up, down}]，第一课 down 是日干本身（判断克时用日干五行）。"""
    j = JIGONG[gan]
    u1 = pan.up(j)
    u2 = pan.up(u1)
    u3 = pan.up(zhi)
    u4 = pan.up(u3)
    return [{"up": u1, "down": gan, "pos": j}, {"up": u2, "down": u1, "pos": u1},
            {"up": u3, "down": zhi, "pos": zhi}, {"up": u4, "down": u3, "pos": u3}]


def _unique(ke4: list[dict]) -> list[dict]:
    """去掉重复的课（第一课按寄宫比）：四课不备、八专就是这样少了课的。"""
    seen, out = set(), []
    for k in ke4:
        key = (k["up"], k["pos"])
        if key not in seen:
            seen.add(key)
            out.append(k)
    return out


# ---------- 三传 ----------

def _shehai_depth(k: dict, kind: str) -> int:
    """深浅：从上神所临地盘 pos 起顺数，直到回到上神本家（不含本家），逐位数克。
    kind = "ke"（上克下：数上神克别人）或 "zei"（下贼上：数上神受克）。"""
    up = k["up"]
    n, p = 0, k["pos"]
    while p != up:
        for c in [p] + JI_GAN.get(p, []):
            if (kind == "ke" and ke(up, c)) or (kind == "zei" and ke(c, up)):
                n += 1
        p = shift(p, 1)
    return n


def _fu_deng(gan: str, ke4: list[dict]) -> str:
    """复等：刚日取干上神，柔日取支上神。"""
    return ke4[0]["up"] if is_yang(gan) else ke4[2]["up"]


def _by_mzj(cands: list[dict], gan: str, ke4: list[dict]) -> tuple[str, str]:
    for level in (0, 1):
        hit = [k for k in cands if mzj(k["pos"]) == level]
        if len(hit) == 1:
            return hit[0]["up"], ("见机" if level == 0 else "察微")
        if len(hit) > 1:
            return _fu_deng(gan, ke4), "复等"
    return _fu_deng(gan, ke4), "复等"


def _pick(cands: list[dict], gan: str, ke4: list[dict], kind: str, method: str) -> tuple[str, str]:
    """从同一种克（全是上克下或全是下贼上）里取一个：一个就用；多个先比用，再涉害。
    返回 (初传, 取法)。"""
    # 同一个上神出现在两课里，只算一个
    uniq, seen = [], set()
    for k in cands:
        if k["up"] not in seen:
            seen.add(k["up"])
            uniq.append(k)
    if len(uniq) == 1:
        return uniq[0]["up"], ("重审" if kind == "zei" else "元首")
    bi = [k for k in uniq if is_yang(k["up"]) == is_yang(gan)]
    if len(bi) == 1:
        return bi[0]["up"], "比用"
    pool = bi or uniq
    if method == "depth":
        depths = {k["up"]: _shehai_depth(k, kind) for k in pool}
        top = max(depths.values())
        deepest = [k for k in pool if depths[k["up"]] == top]
        if len(deepest) == 1:
            return deepest[0]["up"], "涉害"
        up, how = _by_mzj(deepest, gan, ke4)
        return up, "涉害"
    up, how = _by_mzj(pool, gan, ke4)
    return up, "涉害"


def _ke_groups(ke4: list[dict]) -> tuple[list[dict], list[dict]]:
    zei = [k for k in ke4 if ke(k["down"], k["up"])]
    shang = [k for k in ke4 if ke(k["up"], k["down"])]
    return zei, shang


def _fu_yin(pan, gan, zhi, ke4) -> tuple[list[str], str]:
    zei, shang = _ke_groups(ke4[:1])
    gan_up, zhi_up = ke4[0]["up"], ke4[2]["up"]
    if zei or shang:
        first, from_gan = gan_up, True
    elif is_yang(gan):
        first, from_gan = gan_up, True
    else:
        first, from_gan = zhi_up, False
    if XING[first] == first:                      # 初传自刑：中传取另一头（干上 ↔ 支上）
        mid = zhi_up if from_gan else gan_up
    else:
        mid = XING[first]
    last = XING[mid] if XING[mid] != mid else shift(mid, 6)
    return [first, mid, last], "伏吟"


def _fan_yin(pan, gan, zhi, ke4, method) -> tuple[list[str], str]:
    zei, shang = _ke_groups(_unique(ke4))
    if zei or shang:
        first, _ = _pick(zei or shang, gan, ke4, "zei" if zei else "ke", method)
        return [first, pan.up(first), pan.up(pan.up(first))], "返吟"
    # 无克：井栏射（丑日看巳、未日看亥），中传支上，末传干上
    first = pan.up("巳" if zhi == "丑" else "亥")
    return [first, ke4[2]["up"], ke4[0]["up"]], "返吟"


def _ba_zhuan(pan, gan, zhi, ke4, method) -> tuple[list[str], str] | None:
    zei, shang = _ke_groups(_unique(ke4))
    if zei or shang:
        first, how = _pick(zei or shang, gan, ke4, "zei" if zei else "ke", method)
        return [first, pan.up(first), pan.up(pan.up(first))], "八专"
    first = shift(ke4[0]["up"], 2) if is_yang(gan) else shift(ke4[1]["up"], -2)
    return [first, ke4[0]["up"], ke4[0]["up"]], "八专"


def sanchuan(pan: Pan, gan: str, zhi: str, method: str = "mzj") -> dict:
    """返回 {"chuan": [初, 中, 末], "ke_ti": 九宗门名, "how": 取法细节}。"""
    ke4 = sike(pan, gan, zhi)
    if pan.off == 0:
        ch, name = _fu_yin(pan, gan, zhi, ke4)
        return {"chuan": ch, "ke_ti": name}
    if pan.off == 6:
        ch, name = _fan_yin(pan, gan, zhi, ke4, method)
        return {"chuan": ch, "ke_ti": name}
    if JIGONG[gan] == zhi:
        ch, name = _ba_zhuan(pan, gan, zhi, ke4, method)
        return {"chuan": ch, "ke_ti": name}

    uniq = _unique(ke4)
    zei, shang = _ke_groups(uniq)
    if zei or shang:
        first, how = _pick(zei or shang, gan, ke4, "zei" if zei else "ke", method)
        return {"chuan": [first, pan.up(first), pan.up(pan.up(first))], "ke_ti": how}

    # 遥克：先神克日（蒿矢），再日克神（弹射）；上神只看第二、三、四课
    others = [k for k in uniq[1:]]
    shen_ke = [k for k in others if ke(k["up"], gan)]
    ri_ke = [k for k in others if ke(gan, k["up"])]
    if shen_ke or ri_ke:
        group = shen_ke or ri_ke
        first, _ = _pick(group, gan, ke4, "yao", "mzj") if len({k["up"] for k in group}) > 1 \
            else (group[0]["up"], "")
        return {"chuan": [first, pan.up(first), pan.up(pan.up(first))],
                "ke_ti": "蒿矢" if shen_ke else "弹射"}

    if len(uniq) == 3:                            # 别责
        if is_yang(gan):
            he_gan = GAN[(GAN.index(gan) + 5) % 10]
            first = pan.up(JIGONG[he_gan])
        else:
            tri = next(t for t in SANHE if zhi in t)
            first = tri[(tri.index(zhi) + 1) % 3]
        return {"chuan": [first, ke4[0]["up"], ke4[0]["up"]], "ke_ti": "别责"}

    # 昴星
    if is_yang(gan):
        return {"chuan": [pan.up("酉"), ke4[2]["up"], ke4[0]["up"]], "ke_ti": "昴星"}
    return {"chuan": [pan.down("酉"), ke4[0]["up"], ke4[2]["up"]], "ke_ti": "昴星"}


def ke_ge(chuan: list[str]) -> list[str]:
    """三传的课格：连茹、间传，三合局（润下、炎上、曲直、从革），三传全是四季为稼穑。"""
    out = []
    d1, d2 = (zi(chuan[1]) - zi(chuan[0])) % 12, (zi(chuan[2]) - zi(chuan[1])) % 12
    if d1 == d2:
        out += {1: ["进连茹"], 11: ["退连茹"], 2: ["进间传"], 10: ["退间传"]}.get(d1, [])
    names = {"申子辰": "润下", "寅午戌": "炎上", "亥卯未": "曲直", "巳酉丑": "从革"}
    for t, n in names.items():
        if set(chuan) == set(t):
            out.append(n)
    if len(set(chuan)) == 3 and all(c in "辰戌丑未" for c in chuan):
        out.append("稼穑")
    return out


# ---------- 天将 ----------

def is_day(shi: str) -> bool:
    """卯时至申时为昼。"""
    return 3 <= zi(shi) <= 8


def gui_ren(gan: str, day: bool, guiren: str = "std") -> str:
    """贵人所在的天盘支。guiren="alt"（甲(戊)庚牛羊）时庚己丁癸昼夜对调。"""
    if guiren == "alt" and gan in GUIREN_FLIP:
        day = not day
    return (GUI_DAY if day else GUI_NIGHT)[gan]


def tian_jiang(pan: Pan, gan: str, shi: str, day: bool | None = None, guiren: str = "std") -> dict:
    """天盘每个支上的天将：{天盘支: 天将}。
    贵人临地盘亥子丑寅卯辰顺布，临巳午未申酉戌逆布。day 不给就按占时分昼夜。"""
    if day is None:
        day = is_day(shi)
    gui = gui_ren(gan, day, guiren)
    step = 1 if pan.down(gui) in "亥子丑寅卯辰" else -1
    return {shift(gui, i * step): TIAN_JIANG[i] for i in range(12)}


# ---------- 旬、遁干、空亡、六亲 ----------

def xun_start(gan: str, zhi: str) -> str:
    """日所在旬的旬首地支（甲子旬返回子）。"""
    return shift(zhi, -GAN.index(gan))


def kong_wang(gan: str, zhi: str) -> list[str]:
    s = xun_start(gan, zhi)
    return [shift(s, 10), shift(s, 11)]


def dun_gan(gan: str, zhi: str, z: str) -> str | None:
    """旬遁天干：地支 z 在本旬配的天干，空亡的两个支没有。"""
    n = (zi(z) - zi(xun_start(gan, zhi))) % 12
    return GAN[n] if n < 10 else None


def liu_qin(gan: str, z: str) -> str:
    """以日干为我：同我兄弟，生我父母，我生子孙，我克妻财，克我官鬼。"""
    me, it = wx(gan), wx(z)
    if me == it:
        return "兄弟"
    if SHENG[it] == me:
        return "父母"
    if SHENG[me] == it:
        return "子孙"
    if KE[me] == it:
        return "妻财"
    return "官鬼"


# ---------- 行年 ----------

GZ60 = [GAN[i % 10] + ZHI[i % 12] for i in range(60)]


def xing_nian(birth: str, year: str, male: bool) -> str:
    """行年：男一岁起丙寅顺行，女一岁起壬申逆行，每年一位。
    六十年一轮，只要生年干支和占年干支就够了，不用算岁数。"""
    for name, gz in (("生年", birth), ("占年", year)):
        if gz not in GZ60:
            raise ValueError(f"{name}不是六十甲子：{gz}")
    n = (GZ60.index(year) - GZ60.index(birth)) % 60      # 虚岁减一（模 60）
    if male:
        return GZ60[(GZ60.index("丙寅") + n) % 60]
    return GZ60[(GZ60.index("壬申") - n) % 60]


# ---------- 整盘 ----------

def paipan(gan: str, zhi: str, yuejiang: str, shi: str, method: str = "mzj",
           day: bool | None = None, nianming: list[dict] | None = None, year: str | None = None,
           guiren: str = "std") -> dict:
    """排一盘。
    nianming = [{"name": "本人", "birth": "庚午", "gender": "男"}]：
      birth 是出生年干支（只给地支也行，那就只有本命没有行年）；
      gender 和占年 year 都有才排行年。"""
    if gan not in GAN or zhi not in ZHI or GAN.index(gan) % 2 != zi(zhi) % 2:
        raise ValueError(f"日干支不对：{gan}{zhi}")
    for name, z in (("月将", yuejiang), ("占时", shi)):
        if z not in ZHI:
            raise ValueError(f"{name}不是地支：{z}")
    if method not in ("depth", "mzj"):
        raise ValueError(f"涉害取法只能是 depth（深浅）或 mzj（孟仲季）：{method}")
    if guiren not in GUIREN_METHODS:
        raise ValueError(f"贵人起法只能是 std（甲戊庚牛羊）或 alt（甲(戊)庚牛羊）：{guiren}")
    if day is None:
        day = is_day(shi)

    pan = Pan(yuejiang, shi)
    jiang = tian_jiang(pan, gan, shi, day, guiren)
    kong = kong_wang(gan, zhi)

    def info(z: str) -> dict:
        """一个天盘支的全部附带信息。"""
        return {"zhi": z, "jiang": jiang[z], "dun": dun_gan(gan, zhi, z),
                "qin": liu_qin(gan, z), "kong": z in kong}

    sc = sanchuan(pan, gan, zhi, method)
    return {
        "day": gan + zhi,
        "yuejiang": yuejiang,
        "shi": shi,
        "day_night": "昼" if day else "夜",
        "method": method,
        "guiren": guiren,
        "xun": "甲" + xun_start(gan, zhi),
        "kong": kong,
        # 地盘子到亥，每格上面的天盘支和天将
        "pan": [{"di": d, **info(pan.up(d))} for d in ZHI],
        # 第一课到第四课；第一课的 down 是日干
        "sike": [{"down": k["down"], **info(k["up"])} for k in sike(pan, gan, zhi)],
        "sanchuan": {"ke_ti": sc["ke_ti"], "ke_ge": ke_ge(sc["chuan"]), "chuan": [info(z) for z in sc["chuan"]]},
        "nianming": [_nianming(p, pan, info, year) for p in (nianming or [])],
    }


def _nianming(p: dict, pan: Pan, info, year: str | None) -> dict:
    """一个人的本命、行年：各给地盘位置（di）和上面的天盘神、天将等。"""
    birth = p.get("birth", "")
    if not birth or birth[-1] not in ZHI:
        raise ValueError(f"年命要给出生年干支或年支：{birth!r}")
    out = {"name": p.get("name", ""), "birth": birth,
           "benming": {"di": birth[-1], **info(pan.up(birth[-1]))}, "xingnian": None}
    gender = p.get("gender")
    if gender not in (None, "男", "女"):
        raise ValueError(f"性别只能是 男 或 女：{gender}")
    out["gender"] = gender or ""
    if gender and year and len(birth) == 2:
        xn = xing_nian(birth, year, gender == "男")
        out["xingnian"] = {"ganzhi": xn, "di": xn[1], **info(pan.up(xn[1]))}
    return out
