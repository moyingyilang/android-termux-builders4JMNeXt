#!/data/data/com.termux/files/usr/bin/bash
# SPDX-License-Identifier: MPL-2.0
# 打 Android release 包（full + lite）。
# 为什么必须用 release 而不是 debug：**debug 不跑 R8**，跨模块重复类、缺类、签名问题都查不出来。
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/build.env"
"$HERE/10-enter.sh"

echo "=== 容器内构建：$ANDROID_RELEASE_TASKS ==="
su -c "chroot '$CHROOT_ROOT' /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root JAVA_HOME='$CONTAINER_JDK' LD_LIBRARY_PATH='$CONTAINER_JDK/lib' TERM=xterm /bin/bash -c '
  cd \"$PROJECT_DIR\" && nice -n 19 \"$CONTAINER_GRADLE\" --console=plain --no-daemon $ANDROID_RELEASE_TASKS 2>&1 | tail -30
  pkill -f \"[K]otlinCompileDaemon\" 2>/dev/null || true
'"

echo "=== 产物新鲜度自检（防拿旧包充数）==="
today="$(date +%Y-%m-%d)"; bad=0
for f in "$PROJECT_DIR/app/build/outputs/apk/full/release/"*.apk "$PROJECT_DIR/app/build/outputs/apk/lite/release/"*.apk; do
  [ -f "$f" ] || { echo "  缺产物：$f"; bad=1; continue; }
  d="$(date -r "$f" +%Y-%m-%d)"
  printf "  %-24s %s 字节  %s\n" "$(basename "$f")" "$(stat -c %s "$f")" "$(date -r "$f" +%Y-%m-%d\ %H:%M)"
  [ "$d" = "$today" ] || { echo "    产物不是今天的，可能构建没真正跑成"; bad=1; }
done
[ "$bad" = 0 ] || exit 1
echo "构建与新鲜度检查通过；接着用 30-verify-apk.sh 验包名与签名"
