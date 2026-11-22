#!/usr/bin/env python3
"""把笔记编辑器用到的 TipTap 模块下载到 App 里（离线可用，不需要 node）。

做法：从 esm.sh 拿到 TipTap 的 ES 模块，顺着 import 把依赖全部抓下来，
每个模块存成 divinationapp/NoteEditor/ne-v-*.mjs（扁平目录，互相用 ./ 相对路径引用），
再生成一个 ne-deps.mjs 把编辑器要用的东西统一导出给 note-editor.mjs。

用法（在仓库根目录）：
    python3 scripts/vendor_note_editor.py
升级 TipTap：改下面的 VERSION 再跑一次，然后在 App 里把编辑器各项功能试一遍。
"""
import hashlib
import pathlib
import re
import subprocess

VERSION = "2.27.3"
CDN = "https://esm.sh"
OUT = pathlib.Path(__file__).resolve().parent.parent / "divinationapp" / "NoteEditor"

# 包名 → 编辑器需要的导出
PACKAGES = {
    "@tiptap/core": "export { Editor, Node, Mark, mergeAttributes } from '{file}'",
    "@tiptap/starter-kit": "export { default as StarterKit } from '{file}'",
    "@tiptap/extension-underline": "export { default as Underline } from '{file}'",
    "@tiptap/extension-highlight": "export { default as Highlight } from '{file}'",
    "@tiptap/extension-image": "export { default as Image } from '{file}'",
    "@tiptap/extension-placeholder": "export { default as Placeholder } from '{file}'",
    "@tiptap/extension-table": "export { default as Table } from '{file}'",
    "@tiptap/extension-table-row": "export { default as TableRow } from '{file}'",
    "@tiptap/extension-table-cell": "export { default as TableCell } from '{file}'",
    "@tiptap/extension-table-header": "export { default as TableHeader } from '{file}'",
}


def entry_url(pkg: str) -> str:
    # 所有包都把 @tiptap/core 和 @tiptap/pm 当外部依赖，统一由下面的 resolve 指到同一份，
    # 保证整个编辑器里只有一份 ProseMirror（多份会出错）
    external = "@tiptap/pm" if pkg == "@tiptap/core" else "@tiptap/core,@tiptap/pm"
    return f"{CDN}/{pkg}@{VERSION}?external={external}&target=es2022"


def resolve(spec: str) -> str | None:
    """把模块里的 import 地址变成完整 URL；不认识的返回 None。"""
    if spec.startswith("https://esm.sh/"):
        return spec
    if spec.startswith("/"):
        return CDN + spec
    if spec == "@tiptap/core":
        return entry_url("@tiptap/core")
    if spec.startswith("@tiptap/pm/"):
        return f"{CDN}/@tiptap/pm@{VERSION}/{spec[len('@tiptap/pm/'):]}?target=es2022"
    return None


def local_name(url: str) -> str:
    tail = re.sub(r"[^A-Za-z0-9]+", "-", url.split("?")[0].rstrip("/").split("/")[-1].removesuffix(".mjs"))[-30:]
    return f"ne-v-{hashlib.sha1(url.encode()).hexdigest()[:10]}-{tail.strip('-')}.mjs"


SPEC_RE = re.compile(r"""(\bfrom\s*|\bimport\s*\(?\s*)(["'])([^"']+)\2""")


def fetch(url: str) -> str:
    # 用系统自带的 curl 下载：python.org 版的 Python 默认没装根证书，urllib 会报 SSL 错
    out = subprocess.run(["curl", "-fsSL", "--max-time", "60", "-A", "Mozilla/5.0 (vendor script)", url],
                         check=True, capture_output=True)
    return out.stdout.decode("utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("ne-v-*.mjs"):
        old.unlink()

    done: dict[str, str] = {}          # url → 本地文件名
    queue = [entry_url(p) for p in PACKAGES]
    while queue:
        url = queue.pop()
        if url in done:
            continue
        name = local_name(url)
        done[url] = name
        code = re.sub(r"//# sourceMappingURL=\S+", "", fetch(url))   # 没下载 .map，去掉引用

        def rewrite(m: re.Match) -> str:
            target = resolve(m.group(3))
            if target is None:
                return m.group(0)
            if target not in done:
                queue.append(target)
            return f"{m.group(1)}{m.group(2)}./{local_name(target)}{m.group(2)}"

        (OUT / name).write_text(SPEC_RE.sub(rewrite, code), encoding="utf-8")
        print(f"  {name}  ←  {url}")

    lines = ["// 由 scripts/vendor_note_editor.py 生成，不要手改", f"// TipTap {VERSION}"]
    lines += [tpl.replace("{file}", "./" + local_name(entry_url(pkg))) for pkg, tpl in PACKAGES.items()]
    (OUT / "ne-deps.mjs").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"共 {len(done)} 个模块 → {OUT}")


if __name__ == "__main__":
    main()
