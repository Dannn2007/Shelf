#!/bin/zsh
set -e
set -o pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

SDK=$(xcrun --sdk macosx --show-sdk-path)
BIN="$ROOT/.build/Shelf"
APP="$ROOT/.build/Shelf.app"

# 1. 编译
mkdir -p "$ROOT/.build"
echo "==> swiftc release ..."
# Universal binary：分架构编译再 lipo 合并（Apple Silicon + Intel 都能跑）
swiftc -O \
  -target arm64-apple-macosx15.0 \
  -sdk "$SDK" \
  -parse-as-library \
  -o "$ROOT/.build/Shelf-arm64" "$ROOT/Sources/Shelf"/*.swift

swiftc -O \
  -target x86_64-apple-macosx15.0 \
  -sdk "$SDK" \
  -parse-as-library \
  -o "$ROOT/.build/Shelf-x86_64" "$ROOT/Sources/Shelf"/*.swift

lipo -create "$ROOT/.build/Shelf-arm64" "$ROOT/.build/Shelf-x86_64" \
     -output "$BIN"

# 2. 组装 .app
echo "==> assembling app bundle ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Shelf"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# 3. ad-hoc 签名
echo "==> ad-hoc signing ..."
codesign --force --deep --sign - --options runtime "$APP" 2>/dev/null || \
codesign --force --deep --sign - "$APP"

echo ""
echo "✅ $APP built."
echo ""
echo "下一步："
echo "   open $APP          # 试运行"
echo "   ./Tools/install.sh # 安装到 /Applications"