"""术数清单：笔记「用了哪些术数」的可选项。

- code：存进数据库 note_types.type 的值。能在笔记里插入排盘的术数，code 和排盘类型 charts.type 相同，
  所以插入某种排盘时，前端可以直接把这个 code 勾上。
- name：显示名。
- tone：显示用的色系（前端按它上色，笔记列表里的术数胶囊）：
    yi 易学（黑）/ ren 六壬类（蓝）/ qimen 奇门（青）/ red 红 / ziwei 紫微（紫）/ earth 风水（土黄）/ plain 随笔（灰）
  色系由后端给，插件加的术数也能自己指定，前端不用认识每一个术数。
- 顺序就是界面上的显示顺序。

插件可以加自己的术数：在插件模块里导出
    SHUSHU = [{"code": "...", "name": "...", "tone": "色系（可省，默认 plain）",
               "after": "排在哪个 code 后面（可省，省略就排最后）"}]
api 扫描插件时调 register_many 合并进来（同 COMMANDS / CHART_BUILDERS 的做法）。
"""

CATALOG: list[dict] = [
    {"code": "iching", "name": "易经", "tone": "yi"},
    {"code": "meihua", "name": "梅花易数", "tone": "yi"},
    {"code": "liuyao", "name": "六爻", "tone": "yi"},
    # 皇极经世：只是「笔记用了哪个术数」的一个选项（用户允许出现在公开版清单里）；
    # 皇极的排盘功能本身仍只在内部版。code 同内部版的排盘类型，插入皇极排盘时会自动勾上。
    {"code": "huangji", "name": "皇极经世", "tone": "yi"},
    {"code": "bazi", "name": "八字", "tone": "red"},
    {"code": "ziwei", "name": "紫微斗数", "tone": "ziwei"},
    {"code": "daliuren", "name": "大六壬", "tone": "ren"},
    {"code": "qimen", "name": "奇门遁甲", "tone": "qimen"},
    {"code": "taiyi", "name": "太乙神数", "tone": "red"},
    {"code": "xiaoliuren", "name": "小六壬", "tone": "ren"},
    {"code": "fengshui", "name": "风水", "tone": "earth"},
    {"code": "jinkoujue", "name": "金口诀", "tone": "ren"},
    {"code": "suibi", "name": "随笔", "tone": "plain"},
]


def register_many(items: list[dict]) -> None:
    """插件加术数。不许和已有的 code 重复。"""
    for item in items:
        code, name = item["code"], item["name"]
        if any(c["code"] == code for c in CATALOG):
            raise ValueError(f"术数重复注册：{code}")
        entry = {"code": code, "name": name, "tone": item.get("tone", "plain")}
        after = item.get("after")
        idx = next((i for i, c in enumerate(CATALOG) if c["code"] == after), None)
        if idx is None:
            CATALOG.append(entry)
        else:
            CATALOG.insert(idx + 1, entry)


def all_items() -> list[dict]:
    return [dict(c) for c in CATALOG]


def is_known(code: str) -> bool:
    return any(c["code"] == code for c in CATALOG)


def sort_and_name(codes) -> list[dict]:
    """一组 code → 按清单顺序排好的 [{code, name}]；不认识的 code（比如别的版本存的）跳过。"""
    have = set(codes)
    return [dict(c) for c in CATALOG if c["code"] in have]
