#!/bin/zsh
set -e
SRC="$HOME/Projects/Shelf/.build/Shelf.app"
DEST="/Applications/Shelf.app"

if [[ ! -d "$SRC" ]]; then
    echo "❌ 找不到 $SRC，先运行 ./Tools/build.sh"
    exit 1
fi

# 先 掉旧的（如果存在），再拷贝
if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
fi

cp -R "$SRC" "$DEST"

# 重新签名
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

# 登记 LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true

echo "✅ 已安装到 $DEST"
echo "   打开「启动台」或在 Spotlight 里搜「Shelf」就能找到它"
echo "   拖到程序坞 = 永久固定"