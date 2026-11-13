#!/data/data/com.termux/files/usr/bin/bash
# SPDX-License-Identifier: MPL-2.0
# 进入构建用 Linux 环境，并**自检绑定挂载**（挂载掉了是最常见的坑：容器里路径看不见，
# 报错却是"目录不存在"，很容易误判成项目被删）。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/build.env" ] && . "$HERE/build.env" || { echo "缺 build.env（可从 env.example 复制）"; exit 1; }
: "${PROJECT_DIR:?}" "${CHROOT_ROOT:?}"

# 宿主机侧：确认项目在
[ -d "$PROJECT_DIR" ] || { echo "宿主机上找不到项目：$PROJECT_DIR"; exit 1; }

# 容器里的 /dev 必须是可用的：rootfs 放在 /data 上，SELinux 不允许直接使用那里
# mknod 出来的设备节点（表现为 ">/dev/null: Permission denied"，极易被误判成项目丢了）。
# 修法：给 /dev 挂一个 tmpfs，再在里面 mknod 出四个基本设备。
if ! su -c "chroot '$CHROOT_ROOT' /bin/sh -c 'echo probe > /dev/null'" 2>/dev/null; then
  echo "  /dev 不可用，重建中"
  su -c "
    mountpoint -q '$CHROOT_ROOT/dev' || mount -t tmpfs tmpfs '$CHROOT_ROOT/dev'
    for n in 'null c 1 3' 'zero c 1 5' 'random c 1 8' 'urandom c 1 9'; do
      set -- \$n
      [ -e '$CHROOT_ROOT/dev/'\$1 ] || mknod -m 666 '$CHROOT_ROOT/dev/'\$1 \$2 \$3 \$4
    done
  " || { echo "  /dev 重建失败"; exit 1; }
fi

# 逐个挂载点检查并补挂（需要 root；tmoe 环境下 su 可用）
need=0
for d in ${MOUNT_DIRS:-}; do
  rel="${d#"$HOME"/}"
  target="$CHROOT_ROOT/$HOME/$rel"
  if [ -d "$d" ] && ! su -c "ls -d '$target' >/dev/null 2>&1"; then
    su -c "mkdir -p '$target' && mount -o bind '$d' '$target'" && echo "  已挂载 $d" || { echo "  挂载失败：$d"; need=1; }
  fi
done
[ "$need" = 0 ] || { echo "有挂载失败，先修好再构建"; exit 1; }

# 容器内自检：项目与 SDK 都要看得见
su -c "chroot '$CHROOT_ROOT' /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root /bin/bash -c '
  ls -d \"$PROJECT_DIR\" >/dev/null 2>&1 && echo \"  容器内可见项目\" || { echo \"  容器内看不到项目（绑定挂载缺失）\"; exit 1; }
  ls -d \"$ANDROID_SDK/platforms\" >/dev/null 2>&1 && echo \"  容器内可见 Android SDK\" || echo \"  提示：容器内看不到 Android SDK，出 Android 包会失败\"
'"
