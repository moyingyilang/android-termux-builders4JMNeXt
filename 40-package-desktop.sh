#!/data/data/com.termux/files/usr/bin/bash
# SPDX-License-Identifier: MPL-2.0
# 打桌面端全部产物并验收。各平台的打包脚本仍留在项目仓库里（含项目专属命名与图标），
# 这里只负责：进容器 → 依次执行 → 用 50-verify-desktop.sh 验收（判据是产物形态）。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/build.env"
: "${DESKTOP_DIR:=$PROJECT_DIR/desktop}"
: "${DESKTOP_STEPS:=$DESKTOP_DIR/scripts/package-linux.sh $DESKTOP_DIR/scripts/package-linux-x64.sh $DESKTOP_DIR/scripts/package-windows-x64.sh $DESKTOP_DIR/scripts/package-windows-arm64-x.sh}"
"$HERE/10-enter.sh"

echo "=== 依次执行打包步骤（每步的失败都会中止，避免产出半套）==="
for s in $DESKTOP_STEPS; do
  echo "--- $(basename "$s")"
  su -c "chroot '$CHROOT_ROOT' /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root JAVA_HOME='$CONTAINER_JDK' LD_LIBRARY_PATH='$CONTAINER_JDK/lib' TERM=xterm /bin/bash -c 'cd \"$DESKTOP_DIR\" && nice -n 19 $s 2>&1 | tail -4'" || { echo "  该步骤失败，停止"; exit 1; }
done

echo "=== 验收（产物形态）==="
"$HERE/50-verify-desktop.sh"
