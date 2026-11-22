"""参卦：本卦 → 变卦时，变了的三爻卦（原 → 变）起两个参卦：参卦一 上原下变，参卦二 上变下原。
例子都是和用户逐一核对过的。"""
import json

from divination.api import handle
from divination.iching import core, repository
from divination.iching.model import Hexagram

VALUE = {repository.name_of(Hexagram(v)): v for v in range(64)}


def cangua(org: str, chg: str) -> list:
    r = json.loads(handle(json.dumps({"cmd": "cangua", "org_value": VALUE[org], "chg_value": VALUE[chg]})))
    return [(g["part_name"], g["from"], g["to"], [x["name"] for x in g["guas"]]) for g in r["groups"]]


def test_only_lower_changes():
    assert cangua("天風姤", "乾為天") == [("下卦", "巽", "乾", ["風天小畜", "天風姤"])]
    assert cangua("坎為水", "水澤節") == [("下卦", "坎", "兌", ["水澤節", "澤水困"])]


def test_both_parts_change_gives_four():
    q = Hexagram(VALUE["地山謙"])
    for line in (1, 2, 5, 6):
        q = core.flip(q, line)
    assert repository.name_of(q) == "風天小畜"
    assert cangua("地山謙", "風天小畜") == [
        ("下卦", "艮", "乾", ["山天大畜", "天山遯"]),
        ("上卦", "坤", "巽", ["地風升", "風地觀"]),
    ]


def test_only_upper_changes():
    # 乾為天 五爻变 → 火天大有：上卦 乾 → 離
    assert cangua("乾為天", "火天大有") == [("上卦", "乾", "離", ["天火同人", "火天大有"])]


def test_no_change_no_cangua():
    assert cangua("地山謙", "地山謙") == []


def test_brief_has_lines_and_text():
    r = json.loads(handle(json.dumps({"cmd": "cangua", "org_value": VALUE["坎為水"], "chg_value": VALUE["水澤節"]})))
    g = r["groups"][0]["guas"][1]
    assert g["label"] == "参卦二" and len(g["lines"]) == 6 and g["text"]["still"]
