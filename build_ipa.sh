#!/bin/bash
# 在 Mac 上运行: 把 Xcode 项目编译成未签名 .ipa (供轻松签签名)
# 用法: cd DualSubiOS && chmod +x build_ipa.sh && ./build_ipa.sh
set -e
PROJ="$(cd "$(dirname "$0")" && pwd)"
APP="DualSubiOS"
OUT="$PROJ/build"
rm -rf "$OUT"; mkdir -p "$OUT"

echo ">>> 编译 (未签名) ..."
xcodebuild -project "$PROJ/project.pbxproj" \
  -scheme "$APP" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/$APP.xcarchive" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  archive | tail -5

APP_PATH=$(find "$OUT/$APP.xcarchive/Products/Applications" -name "*.app" -maxdepth 1 | head -1)
echo ">>> 找到 app: $APP_PATH"

cd "$OUT"
rm -rf Payload
mkdir Payload
cp -R "$APP_PATH" Payload/
zip -r -q "$APP.ipa" Payload
echo ">>> 完成: $OUT/$APP.ipa  (丢进轻松签 -> 导入证书 -> 签名安装)"
open "$OUT"
