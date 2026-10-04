#!/data/data/com.termux/files/usr/bin/bash
# SPDX-License-Identifier: MPL-2.0
# 验收 APK：包名、版本、签名、新鲜度。判据用**产物形态**，不看"命令是否跑完"。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/build.env"
AAPT2="$ANDROID_SDK/build-tools/$AAPT2_BUILD_TOOLS/aapt2"
echo "=== 验收（aapt2 在容器内跑：它是 glibc 二进制，Termux 直接执行会报 Exec format error）==="
for pair in "full $PROJECT_DIR/app/build/outputs/apk/full/release/app-full-release.apk" \
            "lite $PROJECT_DIR/app/build/outputs/apk/lite/release/app-lite-release.apk"; do
  v="${pair%% *}"; f="${pair#* }"
  [ -f "$f" ] || { echo "  [$v] 缺文件 $f"; continue; }
  printf "  [%s] %s 字节  时间 %s\n" "$v" "$(stat -c %s "$f")" "$(date -r "$f" +%Y-%m-%d\ %H:%M)"
  badging="$(su -c "chroot '$CHROOT_ROOT' /usr/bin/env -i PATH=/usr/bin:/bin /bin/bash -c '$AAPT2 dump badging \"$f\" 2>&1 | grep -E \"^package\" | head -1'")"
  echo "      $badging"
  "$ANDROID_SDK/build-tools/$AAPT2_BUILD_TOOLS/apksigner" verify "$f" >/dev/null 2>&1 \
    && echo "      apksigner: 通过" || echo "      apksigner: 失败（未签名或签名无效）"
done
