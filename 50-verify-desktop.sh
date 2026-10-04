#!/data/data/com.termux/files/usr/bin/bash
# SPDX-License-Identifier: MPL-2.0
# 验收桌面端产物（Linux aarch64/x86_64 与 Windows x64/arm64）。
# 判据全部是**产物形态**，不是"命令是否跑完"：体积对比查不出空包，包内条目才查得出。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/build.env"
: "${DIST_AARCH64:=$PROJECT_DIR/desktop/dist}" "${DIST_X64:=$PROJECT_DIR/desktop/dist-x64}" \
  "${DIST_WIN64:=$PROJECT_DIR/desktop/dist-win64}" "${DIST_WINARM:=$PROJECT_DIR/desktop/dist-win}"
VER="${APP_VERSION:-$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$PROJECT_DIR/desktop/src/main/kotlin/${PKG_PATH:-com/jmnext/desktop}/Version.kt" | tail -1)}"
[ -n "$VER" ] || { echo "拿不到版本号（检查 PKG_PATH/Version.kt）"; exit 1; }
echo "=== 验收桌面端产物：版本 $VER ==="
bad=0
chk_file() { # 文件、期望最小体积、说明
  local f="$1" min="$2" what="$3" sz d today
  if [ ! -f "$f" ]; then echo "  缺 $what：$f"; bad=1; return; fi
  sz=$(stat -c %s "$f"); d=$(date -r "$f" +%Y-%m-%d); today=$(date +%Y-%m-%d)
  printf "  %-48s %10s 字节  %s\n" "$what" "$sz" "$d"
  [ "$sz" -ge "$min" ] || { echo "     体积异常小（<%s），疑似空包" "$min"; bad=1; }
  [ "$d" = "$today" ] || { echo "     不是今天的产物（可能拿旧包充数）"; bad=1; }
}
chk_zip_member() { # zip、成员正则、说明
  local z="$1" re="$2" what="$3"
  unzip -l "$z" 2>/dev/null | grep -qE "$re" || { echo "     包内缺 $what"; bad=1; }
}
chk_tar_member() { local t="$1" re="$2" what="$3"; tar tzf "$t" 2>/dev/null | grep -qE "$re" || { echo "     包内缺 $what"; bad=1; }; }

# Linux aarch64
chk_file "$DIST_AARCH64/jmnext-$VER-linux-aarch64-portable.tar.gz" 20000000 "aarch64 便携 tar.gz"
chk_tar_member "$DIST_AARCH64/jmnext-$VER-linux-aarch64-portable.tar.gz" 'libskiko.*\.so' "libskiko*.so"
chk_file "$DIST_AARCH64/jmnext_${VER}_arm64.deb" 20000000 "aarch64 deb"
chk_file "$DIST_AARCH64/jmnext-$VER-1.aarch64.rpm" 20000000 "aarch64 rpm"
chk_file "$DIST_AARCH64/jmnext-$VER-aarch64.AppImage" 20000000 "aarch64 AppImage"
# Linux x86_64（交叉包）
chk_file "$DIST_X64/jmnext-$VER-linux-x86_64-portable.tar.gz" 20000000 "x86_64 便携 tar.gz"
chk_tar_member "$DIST_X64/jmnext-$VER-linux-x86_64-portable.tar.gz" 'libskiko.*\.so' "libskiko*.so"
chk_file "$DIST_X64/jmnext_${VER}_amd64.deb" 20000000 "x86_64 deb"
chk_file "$DIST_X64/jmnext-$VER-x86_64.AppImage" 20000000 "x86_64 AppImage"
# Windows
chk_file "$DIST_WIN64/jmnext-$VER-windows-x64.zip" 20000000 "Windows x64 zip"
chk_zip_member "$DIST_WIN64/jmnext-$VER-windows-x64.zip" 'skiko-windows.*\.jar' "skiko-windows*.jar（缺它会启动即崩）"
chk_zip_member "$DIST_WIN64/jmnext-$VER-windows-x64.zip" 'runtime/bin/java' "免装 JRE"
chk_file "$DIST_WINARM/jmnext-$VER-windows-arm64.zip" 20000000 "Windows arm64 zip"
chk_zip_member "$DIST_WINARM/jmnext-$VER-windows-arm64.zip" 'skiko-windows.*\.jar' "skiko-windows*.jar"
chk_zip_member "$DIST_WINARM/jmnext-$VER-windows-arm64.zip" 'runtime/bin/java' "免装 JRE"

echo "=== deb 内图标条目（需容器内的 dpkg-deb）==="
for d in "$DIST_AARCH64/jmnext_${VER}_arm64.deb" "$DIST_X64/jmnext_${VER}_amd64.deb"; do
  [ -f "$d" ] || continue
  n=$(su -c "chroot '$CHROOT_ROOT' /usr/bin/env -i PATH=/usr/bin:/bin dpkg-deb -c '$d'" 2>/dev/null | grep -c "jmnext.png")
  echo "  $(basename "$d") 图标条目: $n"
  [ "${n:-0}" -ge 2 ] || { echo "     图标条目不足（桌面启动器可能没图标）"; bad=1; }
done
[ "$bad" = 0 ] && echo "桌面端产物验收通过" || { echo "有项目未通过，拒绝发布"; exit 1; }
