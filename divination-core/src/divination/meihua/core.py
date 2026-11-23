"""
这个文件是梅花易数的起卦逻辑
"""

from divination.iching.model import Hexagram, Trigram

def _trigram_of(total: int) -> Trigram:
    n = total % 8
    if n != 0:
        trigram =  n
    else:
        trigram = 8
    return Trigram(8 - trigram)

def _moving_of(n: int) -> int:
    """数 → 动爻：除以 6 的余数，余 0 当第 6 爻（上爻）。"""
    return n % 6 or 6


def trigram_of_number(n: int) -> Trigram:
    """先天数（乾1 兑2 离3 震4 巽5 坎6 艮7 坤8；超过 8 先除以 8 取余，余 0 当 8）→ 三爻卦。"""
    return _trigram_of(n)


def qigua_numbers(a: int, b: int, c: int) -> tuple[Hexagram, int]:
    """数字起卦：第一个数定上卦、第二个数定下卦（除以 8 取余），第三个数定动爻（除以 6 取余）。"""
    up, down = _trigram_of(a), _trigram_of(b)
    return Hexagram((down.value << 3) | up.value), _moving_of(c)


def qigua_specified(upper: int, lower: int, moving: int) -> tuple[Hexagram, int]:
    """指定起卦：直接给上卦、下卦（先天数 1–8）和动爻（1–6）。"""
    up, down = _trigram_of(upper), _trigram_of(lower)
    return Hexagram((down.value << 3) | up.value), moving


def qigua(year: int, month: int, day: int, hour: int) -> tuple[Hexagram, int]:
    up = _trigram_of(year + month + day)
    down = _trigram_of(year + month + day + hour)

    hexagram = Hexagram((down.value << 3) | up.value)
    moving = (year + month + day + hour) % 6
    if moving == 0:
        moving = 6                                   # 余 0 当第 6 爻(上爻)
    return hexagram, moving