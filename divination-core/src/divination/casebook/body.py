"""笔记正文（编辑器 JSON 文档）的解析：抽纯文字、找引用的排盘和图片。

正文结构（TipTap / ProseMirror 文档）：
    {"type": "doc", "content": [ 节点, ... ]}
节点：{"type": "...", "attrs": {...}, "content": [子节点...], "text": "..."}
    - 文字：       {"type": "text", "text": "..."}
    - 排盘卡片：   {"type": "chart", "attrs": {"id": 5}}
    - 图片：       {"type": "image", "attrs": {"src": "attachment:3f2a9c.png", "width": "50%"}}

正文如果不是合法 JSON（比如旧数据是纯文字），就整段当作纯文字处理。
"""
import json

ATTACHMENT_PREFIX = "attachment:"

# 这些节点结束后换行，让抽出来的文字保持分段
_BLOCK_TYPES = {
    "paragraph", "heading", "blockquote", "codeBlock", "listItem",
    "tableRow", "bulletList", "orderedList", "table", "horizontalRule",
}


def parse(body: str) -> dict | None:
    """把正文解析成文档；空正文或不是 JSON 文档时返回 None。"""
    if not body:
        return None
    try:
        doc = json.loads(body)
    except (ValueError, TypeError):
        return None
    return doc if isinstance(doc, dict) else None


def _walk(node: dict):
    """深度优先遍历所有节点。"""
    yield node
    for child in node.get("content") or []:
        if isinstance(child, dict):
            yield from _walk(child)


def extract_text(body: str) -> str:
    """抽出纯文字：块与块之间换行，表格单元格之间用空格隔开。"""
    doc = parse(body)
    if doc is None:
        return body or ""

    parts: list[str] = []

    def visit(node: dict, in_cell: bool) -> None:
        t = node.get("type")
        if t == "text":
            parts.append(node.get("text", ""))
            return
        if t == "hardBreak":
            parts.append(" " if in_cell else "\n")
            return
        is_cell = t in ("tableCell", "tableHeader")
        for child in node.get("content") or []:
            if isinstance(child, dict):
                visit(child, in_cell or is_cell)
        if is_cell or (in_cell and t in _BLOCK_TYPES):
            parts.append(" ")          # 同一行表格的单元格连成一行
        elif t in _BLOCK_TYPES:
            parts.append("\n")

    visit(doc, False)
    lines = [" ".join(line.split()) for line in "".join(parts).split("\n")]
    return "\n".join(line for line in lines if line)


def referenced_chart_ids(body: str) -> set[int]:
    """正文里出现的所有排盘 id。"""
    doc = parse(body)
    if doc is None:
        return set()
    ids = set()
    for n in _walk(doc):
        if n.get("type") == "chart":
            cid = (n.get("attrs") or {}).get("id")
            if isinstance(cid, int):
                ids.add(cid)
    return ids


def referenced_attachments(body: str) -> set[str]:
    """正文里出现的所有图片文件名（去掉 attachment: 前缀）。"""
    doc = parse(body)
    if doc is None:
        return set()
    names = set()
    for n in _walk(doc):
        if n.get("type") == "image":
            src = (n.get("attrs") or {}).get("src") or ""
            if src.startswith(ATTACHMENT_PREFIX):
                names.add(src[len(ATTACHMENT_PREFIX):])
    return names
