#!/usr/bin/env bash
# APK 断言式验收：发布前必须通过，否则不许上传。
#
# 为什么要有它：2.1.2 曾把"只有 classes.dex、没有 manifest 与资源"的坏包发出去，
# 而当时的验收只检查"文件存在 + 大小非零"—— 那是个**只会通过**的判据，aapt2 无输出时脚本照样往下走。
#
# 判据（全部为断言，不满足即退出非零）：
#   1) aapt2 dump badging 必须输出 package: 行（能识别格式）；
#   2) 包内必须同时存在 AndroidManifest.xml 与 resources.arsc；
#   3) 期望的包名与 versionName 必须匹配（可传参覆盖）。
# 用法：verify-apk.sh <apk> <期望包名> <期望版本前缀>
set -u
APK="${1:?用法: verify-apk.sh <apk> <期望包名> <期望版本前缀>}"
WANT_PKG="${2:?缺期望包名}"
WANT_VER="${3:-}"
AAPT2="${AAPT2:-/data/data/com.termux/files/home/android-sdk/build-tools/35.0.1/aapt2}"
RUN="$AAPT2"; [ -x "$RUN" ] || RUN="aapt2"
[ -s "$APK" ] || { echo "失败：APK 不存在或为空：$APK"; exit 1; }
badging="$("$RUN" dump badging "$APK" 2>&1)"
line="$(printf '%s\n' "$badging" | grep -m1 '^package:')"
[ -n "$line" ] || { echo "失败：aapt2 无法识别该 APK 格式（可能缺少 manifest/资源）"; echo "$badging" | head -3; exit 1; }
m="$(unzip -l "$APK" 2>/dev/null | grep -cE 'AndroidManifest.xml|resources.arsc')"
[ "$m" -ge 2 ] || { echo "失败：包内缺 AndroidManifest.xml 或 resources.arsc（匹配 $m 项）"; exit 1; }
printf '%s\n' "$line" | grep -q "name='$WANT_PKG'" || { echo "失败：包名不符。实际：$line（期望 $WANT_PKG）"; exit 1; }
if [ -n "$WANT_VER" ]; then
  printf '%s\n' "$line" | grep -q "versionName='$WANT_VER" || { echo "失败：版本不符。实际：$line（期望前缀 $WANT_VER）"; exit 1; }
fi
echo "通过：$(basename "$APK") —— $line"
