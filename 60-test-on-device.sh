#!/bin/sh
# 60-test-on-device.sh —— 设备侧虚拟屏测试器入口
#
# 与 30/50 的区别：那两个是**产物验收**，这条是**界面验证**：
# 在手机上建一块 1280x720 的 PUBLIC 虚拟屏，把 App 启动上去并抓帧，
# 整个过程不需要 adb、不在主机侧运行。
#
# 用法：
#   ./60-test-on-device.sh build                编译 dex（javac + d8）
#   ./60-test-on-device.sh start [宽 高 dpi]     建屏并挂住
#   ./60-test-on-device.sh launch [包名]         把 App 启动到该屏
#   ./60-test-on-device.sh capture [png]         抓帧
#   ./60-test-on-device.sh tap X Y               向该屏注入点击
#   ./60-test-on-device.sh ids                   打印逻辑 id 与 SF id
#   ./60-test-on-device.sh stop                  释放虚拟屏
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
VD="$HERE/vdtester/run.sh"
cmd="${1:-}"
case "$cmd" in
build)   exec sh "$HERE/vdtester/build.sh" ;;
start|launch|capture|tap|ids|stop)
         shift
         exec sh "$VD" "$cmd" "$@"
         ;;
*)       sed -n '2,17p' "$0" ;;
esac
