#!/system/bin/sh
# 设备侧运行 vdtester（root；不经过 adb）
#
#   ./run.sh start [宽 高 dpi]     建一块 PUBLIC 虚拟屏并挂住（默认 1280 720 240）
#   ./run.sh launch [包名]         把目标 App 启动到那块屏（默认 com.jmnext）
#   ./run.sh capture [png]         抓帧（默认 /sdcard/vd.png）
#   ./run.sh tap X Y               向该屏注入点击
#   ./run.sh ids                   打印 SF id 与逻辑 id
#   ./run.sh stop                  释放虚拟屏
#
# 关键事实（实测）：
#   - settings 的 overlay_display_devices 建的「叠加视图」不能承载 App：
#     root / shell / system 三个身份启动都会被 SafeActivityOptions 拒；
#   - DisplayManager 建的 PUBLIC 虚拟屏可以，`am start --display` 直接成功；
#   - screencap 认 SF id，input 认逻辑 id，两者必须分开取。
set -u
DEX=${DEX:-/data/local/tmp/vdtester.dex}
PIDF=/data/local/tmp/vdtester.pid
LOG=/data/local/tmp/vdtester.log
NAME=TestVD

sf_id() {
    su -c "dumpsys SurfaceFlinger --display-id" 2>/dev/null \
        | sed -n "s/.*Display \([0-9]*\) (Virtual display): displayName=\"$NAME\".*/\1/p" | head -1
}

logical_id() {
    sed -n 's/.*id=\([0-9]*\).*/\1/p' "$LOG" 2>/dev/null | head -1
}

case "${1:-}" in
start)
    w=${2:-1280}; h=${3:-720}; dpi=${4:-240}
    su -c "cp $DEX /data/local/tmp/vdtester.dex" 2>/dev/null || true
    # 记录 PID：不用 pkill -f（它会把命令行里含同样字符串的自己杀掉）
    su -c "CLASSPATH=$DEX app_process /system/bin HoldVd $w $h $dpi > $LOG 2>&1 & echo \$! > $PIDF"
    i=0
    while [ $i -lt 20 ]; do
        id=$(logical_id)
        [ -n "$id" ] && break
        sleep 0.5; i=$((i+1))
    done
    [ -n "${id:-}" ] || { echo "建屏失败，日志："; cat "$LOG"; exit 1; }
    echo "虚拟屏就绪：逻辑 id=$id  SF id=$(sf_id)"
    ;;
launch)
    pkg=${2:-com.jmnext}
    id=$(logical_id)
    [ -n "$id" ] || { echo "虚拟屏没起（先 ./run.sh start）"; exit 1; }
    act=$(su -c "cmd package resolve-activity --brief $pkg" 2>/dev/null | tail -1)
    [ -n "$act" ] || { echo "解析不到 $pkg 的入口 Activity"; exit 1; }
    su -c "am start --display $id -n $act" 2>&1 | head -3
    ;;
capture)
    out=${2:-/sdcard/vd.png}
    sf=$(sf_id)
    [ -n "$sf" ] || { echo "找不到虚拟屏（先 ./run.sh start）"; exit 1; }
    su -c "screencap -d $sf -p $out" || exit 1
    su -c "chmod 644 $out" 2>/dev/null
    echo "已抓帧：$out（$(su -c "stat -c%s $out" 2>/dev/null) 字节）"
    ;;
tap)
    id=$(logical_id)
    [ -n "$id" ] || { echo "虚拟屏没起"; exit 1; }
    su -c "input -d $id tap ${2:-640} ${3:-360}"
    ;;
ids)
    echo "逻辑 id=$(logical_id)  SF id=$(sf_id)"
    ;;
stop)
    pid=$(su -c "cat $PIDF" 2>/dev/null)
    if [ -n "${pid:-}" ]; then
        su -c "kill $pid" 2>/dev/null
        su -c "rm -f $PIDF" 2>/dev/null
        echo "已释放虚拟屏（pid=$pid）"
    else
        echo "没有在跑的虚拟屏"
    fi
    ;;
*)
    sed -n '2,16p' "$0"
    ;;
esac
