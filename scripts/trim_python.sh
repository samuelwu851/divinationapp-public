#!/bin/sh
# trim_python.sh —— 打包后裁剪嵌入的 Python 标准库,删掉 app 用不到的部分
# (大头是 70M 的 test/),然后重新签名 Python.framework。
#
# 保留 universal(arm64 + x86_64),不动架构,Intel 与 Apple Silicon 都兼容。
# 用法:作为 Xcode 的 Run Script Build Phase,放在 "Embed Frameworks" 之后调用:
#     "${SRCROOT}/scripts/trim_python.sh"
set -eu

# macOS:CODESIGNING_FOLDER_PATH 指向 .app,framework 在 Contents/Frameworks 下。
# 将来做 iOS 版时,iOS 的 .app 没有 Contents/,改成 "${CODESIGNING_FOLDER_PATH}/Frameworks/Python.framework"。
FW="${CODESIGNING_FOLDER_PATH}/Contents/Frameworks/Python.framework"
if [ ! -d "$FW" ]; then
  echo "trim_python: 未找到 $FW,跳过"
  exit 0
fi

# 动态探测版本号(如 3.13),不写死
VER=$(ls "$FW/Versions" | grep -E '^[0-9]+\.[0-9]+$' | head -1)
PYLIB="$FW/Versions/$VER/lib/python$VER"
echo "trim_python: 裁剪 $PYLIB"

# —— 删掉 app 确定用不到的(测试套件 / 装包 / 文档 / 交互 / GUI 教学)——
rm -rf "$PYLIB/test" \
       "$PYLIB/ensurepip" \
       "$PYLIB/pydoc_data" \
       "$PYLIB/idlelib" \
       "$PYLIB/turtledemo" \
       "$PYLIB/tkinter" \
       "$PYLIB/lib2to3"

# lib-dynload 里的测试 / GUI 扩展模块(.so)
rm -f "$PYLIB"/lib-dynload/_test*.so \
      "$PYLIB"/lib-dynload/_ctypes_test*.so \
      "$PYLIB"/lib-dynload/_xxtestfuzz*.so \
      "$PYLIB"/lib-dynload/_tkinter*.so

# —— 删过文件后 framework 原签名失效,必须重签,否则 app 启动会因签名不符崩溃 ——
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  echo "trim_python: 重新签名(identity=$EXPANDED_CODE_SIGN_IDENTITY)"
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$FW/Versions/$VER/Python"
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$FW"
else
  echo "trim_python: 未设签名身份,跳过签名(本地 Debug 常见,无妨)"
fi

echo "trim_python: 完成"
