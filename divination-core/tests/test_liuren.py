"""大六壬排盘：用《大六壬断案》《大六壬指南》卷四的课例核对三传。

断案：日干支 月将+占时 三传（39、43 两课书中文字的将时和盘式不符，按盘式）。
指南：日干支 干上神（第一课上神）三传；盘由干上神反推（干上神加日干寄宫）。

涉害默认用深浅法（顺数回本家，含寄宫天干），孟仲季法可选。两本书在涉害课上都和孟仲季一致，
深浅法有 7 课与书不合，列在 DEPTH_DIFF；三课两种方法都不合，列在 BOOK_DIFF（详见各自注释）。
"""
import json

import pytest

from divination.api import handle
from divination.liuren import core
from divination.liuren.core import Pan, JIGONG, sanchuan

DUANAN = """01 己卯 寅酉 巳戌卯
02 戊申 子申 辰申子
03 癸丑 辰辰 丑戌未
04 庚寅 辰未 巳寅亥
05 辛卯 子未 卯申丑
06 辛巳 辰亥 卯申丑
07 乙巳 戌亥 辰卯寅
08 庚辰 午寅 辰申子
09 壬寅 丑申 子巳戌
10 庚寅 寅酉 子巳戌
11 丁巳 未酉 丑亥酉
12 癸丑 巳丑 酉丑巳
13 壬子 卯卯 亥子卯
14 壬戌 未丑 巳亥巳
15 癸亥 未酉 未巳卯
16 戊申 未卯 辰申子
17 戊子 戌巳 巳戌卯
18 丙戌 子辰 酉巳丑
19 癸巳 戌未 申亥寅
20 癸巳 戌酉 未申酉
21 辛卯 午辰 巳未酉
22 乙酉 申卯 未子巳
23 戊辰 未酉 丑亥酉
24 乙未 戌丑 丑戌未
25 甲子 亥午 子巳戌
26 甲申 辰亥 子巳戌
27 丁亥 午申 酉未巳
28 壬午 子子 亥午子
29 丁酉 午辰 酉亥丑
30 丙戌 子未 申丑午
31 甲寅 未午 辰巳午
32 癸丑 亥午 午亥辰
33 戊申 巳卯 子寅辰
34 壬午 辰申 戌午寅
35 丙午 卯申 子未寅
36 丁卯 子卯 子酉午
37 庚戌 亥酉 子寅辰
38 癸酉 巳申 午卯子
39 己巳 申巳 申亥寅
40 壬寅 子寅 戌申午
41 癸亥 卯亥 酉丑巳
42 戊申 未酉 丑亥酉
43 甲寅 未寅 子巳戌
44 丁丑 午未 子亥戌
45 庚辰 子酉 寅巳申
46 庚辰 午卯 寅巳申
47 戊辰 未巳 申戌子
48 丙寅 亥申 申亥寅
49 庚戌 亥辰 戌巳子
50 己卯 午丑 巳戌卯
51 戊寅 申未 辰巳午
52 癸亥 未巳 丑卯巳
53 丁丑 午辰 酉亥丑
54 丙子 卯丑 辰午申
55 庚辰 子子 申寅巳
56 戊申 酉申 戌酉午
57 壬午 寅寅 亥午子
58 戊申 酉子 寅亥申
59 甲子 亥巳 寅申寅
60 甲子 卯寅 辰巳午
61 辛巳 子亥 午未申
62 辛巳 寅丑 午未申
63 癸丑 丑未 未丑未
64 甲申 辰亥 子巳戌
65 丙申 辰丑 申亥寅
66 壬寅 辰酉 午丑申
67 壬寅 辰未 巳寅亥
68 戊午 卯寅 寅午午
69 丙子 卯戌 巳戌卯
70 乙卯 卯未 未卯亥
71 乙卯 卯辰 丑子亥
72 辛酉 卯未 巳丑酉
73 丁巳 未未 巳申寅
74 庚辰 寅辰 午辰寅
75 壬辰 丑午 午丑申
76 庚辰 子巳 午丑申
77 辛巳 子酉 申亥寅
78 己亥 子未 巳戌卯
79 己卯 午戌 未卯亥
80 壬戌 亥申 辰未戌
81 丙戌 申未 亥子丑
82 乙未 戌巳 巳戌卯
83 壬子 未子 午丑申
84 戊寅 午子 寅申寅
85 戊寅 申辰 丑午酉
86 辛巳 申寅 巳亥巳
87 丁亥 申午 酉亥丑
88 甲寅 未戌 丑亥亥
89 辛巳 子辰 午寅戌
90 乙未 寅未 午丑申
91 庚辰 子亥 午未申
92 癸亥 未亥 未卯亥
93 丁未 午子 巳丑丑
94 丁未 卯寅 申酉戌
95 己酉 卯子 卯午酉
96 己卯 寅丑 辰巳午
97 辛亥 卯巳 午辰寅
98 壬辰 巳子 寅未子
99 甲子 子戌 辰午申
100 癸丑 未寅 午亥辰
101 甲午 子午 寅申寅
102 戊申 酉丑 子申辰
103 戊申 未寅 卯申丑
104 丙寅 未寅 子巳戌
105 戊戌 丑卯 丑亥酉
106 丁亥 子寅 酉未巳
107 壬子 卯丑 辰午申
108 丁亥 辰丑 午戌寅
109 辛卯 丑寅 丑子亥
110 甲午 子卯 申巳寅
111 甲申 申丑 戌巳子
113 己酉 卯丑 丑卯巳
114 己未 卯寅 未申申
115 丁巳 子申 酉丑巳
117 壬午 亥酉 申戌子
118 己卯 戌寅 未卯亥
119 壬戌 未巳 子寅辰
120 庚辰 子寅 午辰寅
122 己卯 戌辰 卯酉卯
123 癸巳 寅亥 申亥寅
124 庚子 寅未 戌巳子
125 庚申 卯寅 亥酉酉
126 丙申 戌亥 卯寅丑
127 己未 巳卯 酉酉酉
128 辛酉 卯午 午卯子
129 丁酉 寅子 酉亥丑
130 丙辰 午午 巳申寅
131 乙丑 午申 亥酉未
132 乙未 戌丑 丑戌未
133 己未 亥酉 酉酉酉
134 癸巳 寅丑 未申酉
135 乙亥 戌午 未亥卯
136 庚寅 辰丑 申亥寅
137 己亥 寅酉 巳戌卯
138 庚子 寅未 戌巳子
139 壬寅 寅申 寅申寅
140 戊寅 寅丑 辰巳午
141 丁酉 申未 亥子丑
142 甲寅 巳亥 寅申寅
143 丙戌 辰寅 子寅辰
144 甲申 申巳 申亥寅
146 癸未 午卯 辰未戌
148 丁酉 申辰 亥卯未
150 乙巳 亥巳 巳亥巳
151 癸卯 寅辰 丑亥酉
152 癸亥 卯酉 巳亥巳
153 庚辰 寅午 子申辰
154 甲午 寅戌 寅午戌
155 乙酉 酉辰 未子巳
156 丙辰 卯子 申亥寅
157 甲午 子午 寅申寅
158 戊辰 子酉 亥寅巳
159 丁巳 亥未 酉丑巳
160 甲申 子申 辰申子
161 乙亥 未巳 申戌子
162 甲戌 酉卯 寅申寅
163 辛亥 申巳 巳申亥
164 辛卯 亥寅 子未子
165 壬午 戌丑 巳寅亥
166 甲寅 未卯 申午午
167 癸巳 申卯 午亥辰
168 丙申 寅寅 巳申寅
170 辛卯 丑巳 未卯亥
171 甲子 卯申 寅酉辰
172 戊午 亥戌 寅午午
173 丁亥 辰亥 巳戌卯
174 壬辰 午巳 丑寅卯
175 己亥 午未 戌酉申
176 辛酉 巳寅 卯午酉
177 辛酉 巳申 午卯子
178 庚辰 亥辰 午丑申
179 丁巳 未寅 巳戌卯
180 丙午 子亥 申酉戌
181 己丑 丑辰 子辰戌
182 癸亥 卯辰 戌酉申
183 丁亥 戌卯 午丑申
184 壬午 丑卯 寅子戌
185 丁丑 亥申 午戌辰
186 戊子 酉寅 子未寅
187 丁未 未未 未丑戌
188 己卯 亥未 未亥卯
189 甲辰 戌寅 戌午寅
190 辛亥 子丑 戌酉申
191 癸卯 寅辰 丑亥酉
192 辛卯 寅巳 子未子
193 甲寅 卯丑 辰午申
194 己酉 酉未 丑卯巳
195 己未 子戌 酉酉酉
196 庚辰 酉辰 寅未子
197 庚辰 酉午 寅巳申
198 己丑 寅戌 酉丑巳
199 辛卯 酉辰 卯申丑
200 癸丑 卯卯 丑戌未
201 庚午 子丑 午巳辰
202 庚午 子酉 酉子卯
204 丁卯 卯戌 巳戌卯
205 丁酉 午辰 酉亥丑
206 辛丑 戌巳 卯申丑
207 庚申 卯巳 午辰寅
208 辛卯 午戌 未卯亥
209 乙酉 辰卯 亥子丑
210 己未 卯丑 酉酉酉
211 庚午 午未 午巳辰
212 乙未 未卯 亥卯未
213 壬辰 子巳 午丑申
214 壬辰 酉寅 午丑申
215 辛酉 丑丑 酉戌未
216 乙丑 卯戌 寅未子
217 乙巳 午亥 午丑申
218 戊戌 戌寅 寅戌午
219 癸丑 酉戌 子亥戌
220 壬子 申亥 午卯子
221 辛未 酉寅 酉辰亥"""

ZHINAN = """1 己巳 辰 寅亥申
2 丁酉 巳 丑巳巳
3 甲申 巳 申亥寅
4 甲戌 卯 辰巳午
5 甲寅 未 子巳戌
6 己丑 酉 卯巳未
7 乙酉 酉 未子巳
8 癸酉 子 未午巳
9 癸丑 未 未丑未
10 辛卯 戌 卯子卯
11 乙酉 辰 辰酉卯
12 辛丑 酉 子亥戌
13 癸卯 卯 未酉亥
15 丙戌 子 子未寅
16 辛卯 寅 未亥卯
17 丙辰 巳 巳申寅
18 乙巳 子 酉巳丑
19 己巳 寅 酉辰亥
20 戊辰 亥 巳亥巳
21 乙丑 子 巳丑酉
22 癸未 巳 酉丑巳
23 甲戌 戌 戌午寅
24 乙未 巳 酉戌亥
25 乙未 戌 戌辰戌
27 戊辰 午 寅午午
28 庚寅 午 午辰寅
29 甲子 亥 午卯子
30 丁未 戌 亥戌戌
32 辛巳 午 午寅戌
33 己未 申 未申申
34 己未 亥 亥卯未
35 甲寅 子 戌申午
36 甲子 申 寅申寅
37 丙子 亥 午子午
40 辛亥 寅 未亥卯
41 丁酉 寅 亥午丑
42 丙寅 子 子未寅
43 丁亥 辰 巳寅亥
44 甲午 未 子巳戌
45 辛丑 卯 卯申丑
46 壬戌 申 巳寅亥
47 乙未 申 亥卯未
48 丁巳 辰 亥申巳
49 丁丑 卯 巳丑酉
50 癸卯 亥 丑亥酉
51 己未 子 巳戌卯
54 丙午 戌 辰酉寅
55 己未 卯 卯亥未
56 癸酉 申 卯戌巳
57 己亥 亥 未亥卯
58 辛未 巳 酉辰亥
59 己丑 寅 卯戌巳
60 己亥 卯 未卯亥
61 乙丑 未 未戌丑
62 戊寅 巳 巳申寅
63 乙巳 酉 寅未子
64 戊子 戌 巳戌卯
65 己未 寅 酉辰亥
66 庚子 辰 子申辰
67 壬寅 丑 辰午申
68 丙寅 未 辰午申
69 乙未 卯 戌卯午
70 癸卯 巳 酉丑巳
71 丁酉 亥 亥卯未
72 丁丑 子 巳戌卯
73 丁亥 丑 巳亥巳
74 戊申 戌 卯申丑
75 丙辰 申 申亥寅
76 乙未 亥 午丑申
77 己酉 寅 亥午丑
78 甲午 丑 子亥戌
79 癸亥 午 午亥辰
81 戊午 巳 巳申寅
83 丁未 辰 亥辰辰
84 甲子 巳 申亥寅
85 丁亥 申 申酉戌
86 癸未 戌 戌未辰
87 癸亥 辰 辰未戌
88 癸卯 申 卯戌巳
89 甲寅 辰 辰午申
91 乙酉 申 申子辰
92 庚申 丑 卯丑丑
93 丙午 酉 酉丑巳
95 乙亥 申 未亥卯
97 丁亥 酉 酉亥丑
98 庚子 亥 午酉子
99 丙午 申 申亥寅
100 辛酉 亥 亥子丑
101 戊辰 酉 子辰申
103 丙子 巳 巳申寅
104 丁亥 戌 午戌寅
105 庚申 卯 戌巳子
106 庚子 午 午辰寅
107 壬戌 申 巳寅亥
108 丁丑 申 申酉戌
109 辛巳 亥 午未申
110 丁亥 子 巳戌卯
111 己酉 戌 卯午酉
113 丁未 寅 酉辰亥
114 辛亥 未 巳寅亥
115 戊申 酉 辰申子
116 庚戌 申 申寅巳
119 丁酉 戌 子卯午
120 乙丑 卯 子亥戌
121 乙未 子 卯亥未
122 辛巳 未 寅亥申
123 甲寅 亥 丑亥亥
124 甲申 子 午辰寅"""

# 深浅法与书不合、孟仲季法合的涉害课
DEPTH_DIFF = {"断案74", "断案120", "断案188", "断案189", "指南16", "指南56", "指南57"}
# 两种方法都不合的课。三课都像是以日干寄宫的地支判断第一课克贼，但全面这样改会多错二三十课，当特例
BOOK_DIFF = {
    "断案219": "癸丑日八专无克，书取干上子连茹",
    "指南20": "戊辰日返吟，亥加巳、巳加亥同为下贼上，书取巳",
    "指南100": "辛酉日别责，书取干上亥连茹",
}


def _cases():
    for line in DUANAN.splitlines():
        n, gz, js, ch = line.split()
        yield "断案" + n, gz, Pan(js[0], js[1]), ch
    for line in ZHINAN.splitlines():
        n, gz, up, ch = line.split()
        yield "指南" + n, gz, Pan(up, JIGONG[gz[0]]), ch


CASES = list(_cases())


@pytest.mark.parametrize("method", ["depth", "mzj"])
@pytest.mark.parametrize("name, gz, pan, chuan", CASES, ids=[c[0] for c in CASES])
def test_sanchuan_against_books(name, gz, pan, chuan, method):
    got = "".join(sanchuan(pan, gz[0], gz[1], method)["chuan"])
    if name in BOOK_DIFF or (method == "depth" and name in DEPTH_DIFF):
        assert got != chuan, f"{name} 以前不合，现在合了，检查规则改动"
    else:
        assert got == chuan, name


def test_shehai_depth_counting():
    """用户的例子：庚子日干上午，午火临申，顺数回午：申、庚、酉、辛 共克 4 次；戌临子：子、癸 2 次。取午。"""
    k = {"up": "午", "pos": "申"}
    assert core._shehai_depth(k, "ke") == 4
    assert core._shehai_depth({"up": "戌", "pos": "子"}, "ke") == 2
    assert sanchuan(Pan("午", "申"), "庚", "子", "depth")["chuan"] == ["午", "辰", "寅"]


def test_tian_jiang():
    # 断案01 己卯日 寅将酉时：夜贵申，三传 巳玄武 戌朱雀 卯白虎
    r = core.paipan("己", "卯", "寅", "酉")
    assert r["day_night"] == "夜"
    assert [(c["zhi"], c["jiang"]) for c in r["sanchuan"]["chuan"]] == [("巳", "玄武"), ("戌", "朱雀"), ("卯", "白虎")]
    # 断案04 庚寅日 辰将未时：昼贵丑，三传 巳勾陈 寅螣蛇 亥太阴
    r = core.paipan("庚", "寅", "辰", "未")
    assert [c["jiang"] for c in r["sanchuan"]["chuan"]] == ["勾陈", "螣蛇", "太阴"]
    # 昼夜可以手动指定
    assert core.paipan("庚", "寅", "辰", "未", day=False)["day_night"] == "夜"


def test_guiren_methods():
    # 甲(戊)庚牛羊：每句第二个干昼夜对调；其他干两种起法一样
    flip = {"庚": ("未", "丑"), "己": ("申", "子"), "丁": ("酉", "亥"), "癸": ("卯", "巳")}
    for g in core.GAN:
        for day in (True, False):
            std = core.gui_ren(g, day)
            if g in flip:
                assert core.gui_ren(g, day, "alt") == flip[g][0 if day else 1]
                assert std == flip[g][1 if day else 0]
            else:
                assert core.gui_ren(g, day, "alt") == std
    # 整盘：断案04 庚寅日 辰将未时，换成 甲(戊)庚牛羊 就是昼贵未
    r = core.paipan("庚", "寅", "辰", "未", guiren="alt")
    assert r["guiren"] == "alt" and next(p["zhi"] for p in r["pan"] if p["jiang"] == "贵人") == "未"
    assert core.paipan("庚", "寅", "辰", "未")["guiren"] == "std"
    with pytest.raises(ValueError):
        core.paipan("庚", "寅", "辰", "未", guiren="x")


def test_dun_kong_qin():
    # 甲子旬戌亥空；丙寅日（甲子旬）申遁壬、戌无遁干
    assert core.kong_wang("丙", "寅") == ["戌", "亥"]
    assert core.dun_gan("丙", "寅", "申") == "壬"
    assert core.dun_gan("丙", "寅", "戌") is None
    # 断案48 丙寅日：财壬申、官亥（空）、父丙寅
    r = core.paipan("丙", "寅", "亥", "申")
    assert [(c["qin"], c["dun"], c["zhi"], c["kong"]) for c in r["sanchuan"]["chuan"]] == [
        ("妻财", "壬", "申", False), ("官鬼", None, "亥", True), ("父母", "丙", "寅", False)]


def test_nianming():
    # 断案45 庚辰日 子将酉时，己未命：本命未上见戌；只给地支没有行年
    r = core.paipan("庚", "辰", "子", "酉", nianming=[{"name": "何秀才", "birth": "未"}])
    m = r["nianming"][0]
    assert m["benming"]["di"] == "未" and m["benming"]["zhi"] == "戌" and m["xingnian"] is None


@pytest.mark.parametrize("birth, year, male, zhi", [
    ("壬申", "戊申", True, "寅"),   # 断案25 三十七岁行年在寅
    ("己未", "戊申", True, "卯"),   # 断案45 五十岁行年在卯
    ("乙亥", "戊申", True, "亥"),   # 断案116 三十四岁行年在亥
    ("甲戌", "戊申", True, "子"),   # 断案166 三十五岁行年在子
    ("乙巳", "己酉", True, "午"),   # 断案176 六十五岁行年在午
    ("庚午", "己酉", True, "巳"),   # 断案16 酉加行年，酉在巳上
])
def test_xing_nian_books(birth, year, male, zhi):
    assert core.xing_nian(birth, year, male)[1] == zhi


def test_xing_nian_rule():
    assert core.xing_nian("甲子", "甲子", True) == "丙寅"      # 男一岁丙寅
    assert core.xing_nian("甲子", "乙丑", True) == "丁卯"      # 顺行
    assert core.xing_nian("甲子", "甲子", False) == "壬申"     # 女一岁壬申
    assert core.xing_nian("甲子", "乙丑", False) == "辛未"     # 逆行
    r = core.paipan("庚", "辰", "子", "酉", year="戊申",
                    nianming=[{"birth": "己未", "gender": "男"}, {"birth": "己未", "gender": "女"}])
    assert r["nianming"][0]["xingnian"]["ganzhi"] == "乙卯"
    assert r["nianming"][1]["xingnian"]["ganzhi"] == "癸未"     # 壬申逆数 49 位
    with pytest.raises(ValueError):
        core.paipan("庚", "辰", "子", "酉", nianming=[{"birth": "己未", "gender": "x"}])


def test_yuejiang_by_zhongqi():
    # 2024-02-19 雨水在 12:13，早上还是大寒子将，下午换亥将
    am = json.loads(handle(json.dumps({"cmd": "liuren_paipan", "date": {"year": 2024, "month": 2, "day": 19, "hour": 7}})))
    pm = json.loads(handle(json.dumps({"cmd": "liuren_paipan", "date": {"year": 2024, "month": 2, "day": 19, "hour": 13}})))
    assert am["input"]["yuejiang"] == "子" and am["input"]["qi"] == "大寒"
    assert pm["input"]["yuejiang"] == "亥" and pm["input"]["qi"] == "雨水"
    assert len(am["shensha"]) == 12
    taisui = [x for x in am["shensha_list"] if x["category"] == "岁煞" and x["name"] == "太岁"]
    assert taisui == [{"category": "岁煞", "name": "太岁", "branches": ["辰"]}]        # 甲辰年


def test_zishi_huan_ri():
    # 23 点算第二天子时
    r = json.loads(handle(json.dumps({"cmd": "liuren_paipan", "date": {"year": 2024, "month": 2, "day": 10, "hour": 23}})))
    assert r["input"]["day"] == "乙巳" and r["input"]["shi"] == "子"


def test_api_direct_and_errors():
    r = json.loads(handle(json.dumps({"cmd": "liuren_paipan", "day": "庚子", "yuejiang": "午", "shi": "申",
                                      "method": "mzj", "nianming": [{"birth": "庚午", "gender": "男"}]})))
    assert [c["zhi"] for c in r["sanchuan"]["chuan"]] == ["午", "辰", "寅"]
    assert "shensha" not in r and r["nianming"][0]["benming"]["di"] == "午"
    assert r["nianming"][0]["xingnian"] is None                    # 没给占年，排不了行年
    r = json.loads(handle(json.dumps({"cmd": "liuren_paipan", "date": {"year": 2024, "month": 3, "day": 1, "hour": 9},
                                      "nianming": [{"birth": "庚午", "gender": "男"}]})))
    assert r["nianming"][0]["xingnian"]["ganzhi"] == core.xing_nian("庚午", "甲辰", True)
    assert "error" in json.loads(handle(json.dumps({"cmd": "liuren_paipan", "day": "甲丑", "yuejiang": "午", "shi": "申"})))
    assert "error" in json.loads(handle(json.dumps({"cmd": "liuren_paipan", "day": "甲子", "yuejiang": "午", "shi": "申", "method": "x"})))


def test_date_with_overrides():
    """参考盘：2026-11-26 08:44 甲辰日辰时寅将，涉害。戌临子（仲）、寅临辰（季）同为上克下：
    默认孟仲季法取戌，三传 戌申午（其他排盘软件也是这样）；深浅法取寅，寅子戌。1980 庚申男行年壬子。"""
    req = {"cmd": "liuren_paipan", "date": {"year": 2026, "month": 11, "day": 26, "hour": 8, "minute": 44},
           "nianming": [{"birth": "庚申", "gender": "男"}]}
    r = json.loads(handle(json.dumps(req)))
    assert r["input"]["hour"] == "戊辰" and r["input"]["yuejiang"] == "寅"
    assert r["sanchuan"]["ke_ti"] == "涉害"
    assert [(c["zhi"], c["jiang"], c["dun"]) for c in r["sanchuan"]["chuan"]] == [("戌", "玄武", "庚"), ("申", "白虎", "戊"), ("午", "青龙", "丙")]
    r2 = json.loads(handle(json.dumps({**req, "method": "depth"})))
    assert [(c["zhi"], c["jiang"], c["dun"]) for c in r2["sanchuan"]["chuan"]] == [("寅", "螣蛇", None), ("子", "天后", "壬"), ("戌", "玄武", "庚")]
    assert r["nianming"][0]["xingnian"]["ganzhi"] == "壬子"
    # 活时：手动占时午，日不变
    r = json.loads(handle(json.dumps({**req, "shi": "午", "yuejiang": "丑"})))
    assert r["input"]["day"] == "甲辰" and r["shi"] == "午" and r["yuejiang"] == "丑" and r["input"]["hour"] is None
