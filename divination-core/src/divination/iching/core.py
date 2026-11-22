import divination.iching.model as model
"""core —— 易经的领域算法（纯逻辑，只依赖 model）。

这一层把"规则"变成"计算"，全部是纯函数，不碰文字资料、不碰 I/O：

    - 起卦：把输入（如筮法的 6/7/8/9）变成一个卦
    - 变卦：按动爻从本卦推出变卦
    - 互、错、综等衍生卦

它只知道卦象的数学结构，不知道每个卦叫什么、卦辞是什么——
那些文字属于 repository 层。
"""


def determine_yinyang(Hexagram: model.Hexagram, line: int) -> model.Polarity:
    """判断某一根爻是阴还是阳"""
    index = 6 - line
    bit = (Hexagram.value >> index) & 1
    return model.Polarity(bit)

def flip(hexagram: model.Hexagram, line: int) -> model.Hexagram:
    """翻转第 line 爻，返回一个新卦（原卦不动）。line：1=初爻 … 6=上爻。"""
    index = 6 - line
    mask = 1 << index
    new_value = hexagram.value ^ mask
    return model.Hexagram(new_value)

def zonggua(hexagram: model.Hexagram) -> model.Hexagram:
    #value = int(format(hexagram.value, '06b')[::-1], 2)
    #return model.Hexagram(value)
    value = hexagram.value
    result = 0
    for i in range(6):
        bit = (value >> i) & 1 # 得到每一爻的阴阳
        result |= bit << (5 - i) # 放到镜像位置，并入result
    return model.Hexagram(result)

def cuogua(hexagram: model.Hexagram) -> model.Hexagram:
    result = hexagram.value ^ (0b111111)
    return model.Hexagram(result)

def split(hexagram: model.Hexagram) -> tuple[model.Trigram, model.Trigram]:
    """拆成 (下卦, 上卦)。下卦是高 3 位（初、二、三爻），上卦是低 3 位（四、五、上爻）。"""
    return model.Trigram((hexagram.value >> 3) & 0b111), model.Trigram(hexagram.value & 0b111)


def join(lower: model.Trigram, upper: model.Trigram) -> model.Hexagram:
    """下卦 + 上卦 → 重卦。"""
    return model.Hexagram((lower.value << 3) | upper.value)


def cangua(original: model.Hexagram, changed: model.Hexagram):
    """参卦：看本卦 → 变卦时，下卦、上卦各自有没有变。
    某一部分（三爻卦）有变，就用它变化前的「原」和变化后的「变」起两个参卦：
        参卦一：上原下变
        参卦二：上变下原
    只有下卦变或只有上卦变 → 2 个；上下都变 → 4 个（先下卦、后上卦）；六爻不变 → 没有。

    返回 [(部分 'lower'/'upper', 原, 变, 参卦一, 参卦二), ...]
    """
    result = []
    for part, (a, b) in (("lower", (split(original)[0], split(changed)[0])),
                         ("upper", (split(original)[1], split(changed)[1]))):
        if a != b:
            result.append((part, a, b, join(lower=b, upper=a), join(lower=a, upper=b)))
    return result


# ---------- 京房八宫 ----------
BAGONG_STAGES = ("本宫", "一世", "二世", "三世", "四世", "五世", "游魂", "归魂")


def _build_bagong() -> dict[int, tuple[model.Trigram, int]]:
    """正推八宫表：卦值 → (宫, 第几位 0~7)。
    每宫从八纯卦出发：依次变初、二、三、四、五爻 → 一世…五世；
    五世卦的四爻变回去 → 游魂；游魂卦的下卦整个变回本宫 → 归魂。上爻始终不变。
    """
    table = {}
    for palace in model.Trigram:
        h = join(palace, palace)
        seq = [h]
        for line in range(1, 6):
            h = flip(h, line)
            seq.append(h)
        you = flip(h, 4)
        gui = you
        for line in (1, 2, 3):
            gui = flip(gui, line)
        seq += [you, gui]
        for i, x in enumerate(seq):
            table[x.value] = (palace, i)
    assert len(table) == 64, "八宫表应正好覆盖 64 卦"
    return table


def bagong(hexagram: model.Hexagram) -> tuple[model.Trigram, str]:
    """这个卦属于哪一宫、是第几世。如 天風姤 → (乾, "一世")。"""
    palace, stage = _BAGONG[hexagram.value]
    return palace, BAGONG_STAGES[stage]


def hugua(hexagram: model.Hexagram) -> model.Hexagram:
    """取中间四爻重组。下卦=原2,3,4爻；上卦=原3,4,5爻。"""
    lower = (hexagram.value >> 2) & 0b111   # 原第2,3,4爻 → 互卦下卦
    upper = (hexagram.value >> 1) & 0b111   # 原第3,4,5爻 → 互卦上卦
    value = (lower << 3) | upper
    return model.Hexagram(value)




"""
def flip

def zonggua

def cuogua

def hugua

"""


_BAGONG = _build_bagong()
