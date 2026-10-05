#!/bin/bash
# 在 macOS 上打包 ObraDinnDifficultyPatcher.app 并打出发布 zip
#
#   bash packaging/build-macos.sh
#
# 需要：macOS、python3.12，以及先准备好 mac 版自包含 langtool
#   （Windows 上交叉发布：dotnet publish hardcore/langtool/LangTool.csproj -c Release
#     -r osx-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true
#     -p:TrimMode=partial -p:EnableCompressionInSingleFile=true -o hardcore/langtool/pub-osx-x64
#    然后把它放到 patcher/assets/bin/langtool 并 chmod +x）
#
# 产物：dist/ObraDinnDifficultyPatcher_MacOS.zip（里面只有 .app）
set -e
cd "$(dirname "${BASH_SOURCE[0]}")/.."
P="${PYTHON:-/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12}"
NAME="ObraDinnDifficultyPatcher_MacOS"
LT="patcher/assets/bin/langtool"

if [ ! -f "$LT" ]; then
  echo "!! 缺少 mac 版 langtool：$LT（换难度要靠它，见本文件顶部注释）"
  exit 1
fi
chmod +x "$LT"

echo "--- 1. png -> icns"
if [ -f icon-difficulty.png ]; then
  rm -rf /tmp/icon_diff.iconset icon-difficulty.icns
  mkdir -p /tmp/icon_diff.iconset
  for s in 16 32 64 128 256 512; do
    sips -z $s $s icon-difficulty.png --out /tmp/icon_diff.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) icon-difficulty.png --out /tmp/icon_diff.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns /tmp/icon_diff.iconset -o icon-difficulty.icns
  ls -l icon-difficulty.icns | awk '{print $5, $9}'
fi

echo "--- 2. venv + pyinstaller"
if [ ! -x .venv/bin/python ]; then "$P" -m venv .venv; fi
.venv/bin/python -m pip install -q --upgrade pip
# fonttools：打包前置检查要验证字体覆盖；lz4：换难度时 langpatch_tool 会 import 它
.venv/bin/python -m pip install -q pyinstaller fonttools lz4
echo -n "pyinstaller "; .venv/bin/python -m PyInstaller --version

echo "--- 3. build .app（含前置检查：字体覆盖 / langtool / 原版 DLL）"
pkill -f "ObraDinnDifficultyPatcher.app/Contents/MacOS" 2>/dev/null && echo "（已关掉旧的 .app 实例）" || true
sleep 1
rm -rf build dist
.venv/bin/python -m patcher.build_gui 2>&1 | tail -16
APP=dist/ObraDinnDifficultyPatcher.app
ls -d "$APP"

# langtool 是当 datas 打进去的，PyInstaller 不保证可执行位；补完权限要重新做 ad-hoc 签名
echo "--- 3b. langtool 可执行位 + 重新签名"
BUNDLED="$APP/Contents/Frameworks/patcher/assets/bin/langtool"
if [ -f "$BUNDLED" ]; then
  chmod +x "$BUNDLED"
  ls -l "$BUNDLED" | awk '{print $1, $5, $9}'
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 && echo "re-signed ad-hoc"
else
  echo "!! 包里没有 assets/bin/langtool"
fi

echo "--- 4. smoke（无窗口起服务）"
BIN="$APP/Contents/MacOS/ObraDinnDifficultyPatcher"
"$BIN" --no-browser --port 8791 >/tmp/patcher-smoke.log 2>&1 &
SM=$!
sleep 16
code=$(curl -s -o /tmp/p.out -w '%{http_code}' http://127.0.0.1:8791/ || echo 000)
echo "  / -> $code  $(wc -c < /tmp/p.out | tr -d ' ')B"
kill $SM 2>/dev/null || true
sleep 1
[ "$code" = "200" ] || { echo "!! 冒烟失败，日志尾部："; tail -6 /tmp/patcher-smoke.log; }

echo "--- 5. release zip（里面只有 .app）"
rm -rf "dist/$NAME" "dist/$NAME.zip"
rm -rf "$APP/Contents/MacOS/saves"
rm -f "$APP"/Contents/MacOS/*.log
mkdir -p "dist/$NAME"
cp -R "$APP" "dist/$NAME/"
( cd dist && ditto -c -k --sequesterRsrc --keepParent "$NAME" "$NAME.zip" )

echo "--- 结果"
ls -lh "dist/$NAME.zip" | awk '{print $5, $9}'
shasum -a 256 "dist/$NAME.zip" | awk '{print $1}'
