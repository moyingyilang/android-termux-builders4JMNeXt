# vdtester —— 设备侧虚拟屏测试器

不经过 adb、不在主机侧运行：**全部动作都在手机上、以 root 身份完成**。
用途是给界面测试/截图一块 1280×720 的干净屏幕，不和用户抢主屏。

## 用法

```sh
sh scripts/vdtester/build.sh              # 宿主机/Termux 侧编译一次（javac + d8）
sh scripts/vdtester/run.sh start 1280 720 240
sh scripts/vdtester/run.sh launch com.jmnext
sh scripts/vdtester/run.sh capture /sdcard/vd.png
sh scripts/vdtester/run.sh tap 640 360
sh scripts/vdtester/run.sh stop
```

`capture` 出来的 PNG 尺寸与 `start` 的参数一致（实测 1280×720）。

## 实现

| 步骤 | 做法 |
| --- | --- |
| 造 Context | `app_process` 里没有 Application，反射 `ActivityThread.systemMain()` 取 `mSystemContext` |
| 建屏 | `DisplayManager.createVirtualDisplay(name, w, h, dpi, surface, flags)`，Surface 用 `ImageReader` 接 |
| flags | `PUBLIC \| PRESENTATION \| OWN_CONTENT_ONLY \| SUPPORTS_TOUCH(1<<6)` |
| 放 App | `am start --display <逻辑 id>`（公有 VD 上可直接成功） |
| 抓帧 | `screencap -d <SF id>`；SF id 与逻辑 id 必须分别取 |
| 输入 | `input -d <逻辑 id> tap x y` |

## 实测结论（都是踩过的）

1. `settings put global overlay_display_devices` 建的「叠加视图」**不能承载 App**：
   root(0) / shell(2000) / system(1000) 三个身份 `am start --display` 全被
   `SafeActivityOptions` 拒；必须是 `DisplayManager` 建的 PUBLIC 虚拟屏才行。
2. `screencap` 认 **SurfaceFlinger id**，`input` 认**逻辑 id**，两者不能互换。
3. `run.sh start` 用后台 `app_process` 挂住 VD；`run.sh stop` 杀掉它即释放。
4. 虚拟屏上的输入框会抢主屏输入法，需要时补 `setDisplayImePolicy(vdId, HIDE)`
   （见 `docs/VIRTUAL-DISPLAY.md`）。

## 与主项目的关系

它只是调试工具，不参与发布产物；`dex/` 为构建产物，已在 `.gitignore` 里忽略。
