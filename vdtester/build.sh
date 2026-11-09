#!/bin/sh
# 编译 vdtester 的 dex（宿主机/Termux 侧执行一次）
#
# 依赖：javac（Termux 自带即可）、Android SDK 的 android.jar 与 d8。
# 产物：dex/classes.dex（HoldVd）与 dex/VdTester.dex
set -eu
cd "$(dirname "$0")" || exit 1
SDK="${ANDROID_SDK:-$HOME/android-sdk}"
AJ=$(ls "$SDK"/platforms/*/android.jar 2>/dev/null | tail -1)
D8=$(ls "$SDK"/build-tools/*/d8 2>/dev/null | tail -1)
[ -n "$AJ" ] && [ -n "$D8" ] || { echo "找不到 android.jar 或 d8（SDK=$SDK）"; exit 1; }

rm -rf classes classes2 dex
mkdir -p classes classes2 dex
javac -source 11 -target 11 -nowarn -cp "$AJ" -d classes VdTester.java
javac -source 11 -target 11 -nowarn -cp "$AJ" -d classes2 HoldVd.java
"$D8" --lib "$AJ" --min-api 30 --output dex classes/*.class classes2/*.class >/dev/null
# d8 会把两个类打进同一个 dex；改名便于区分用途
mv dex/classes.dex dex/vdtester.dex
echo "  已生成 $(pwd)/dex/vdtester.dex（$(stat -c%s dex/vdtester.dex) 字节）"
