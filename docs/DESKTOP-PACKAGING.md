# Compose Desktop 跨架构打包：要换的只有三样东西

桌面端是**纯 JVM**（没有自写原生代码），所以"交叉打包"比想象的简单 —— 难点不在编译，而在
**运行时、原生库、启动器**这三处。以下内容来自实际出包并验收通过的流程（JMNeXt 2.0.0）。

## 一、aarch64 Linux（本机原生打包）

`createDistributable` 产出 app-image（`build/compose/binaries/main/app/<packageName>`），再打成
便携 tar.gz、deb、rpm、AppImage 四种。每一处都带自检，任何一项不过就拒绝出包：

- deb：包内必须有图标条目（否则桌面启动器没图标）；
- rpm / AppImage：同样校验包内文件；
- 便携包：解压后能直接 `./bin/<name>` 跑。

## 二、aarch64 → x86_64 Linux（交叉）

只需换三样东西：

| 要换 | 怎么做 | 不换会怎样 |
| --- | --- | --- |
| **JVM 运行时** | 用 `jlink` + **目标架构 JDK 的 jmods** 生成一份 x86_64 runtime，替换 app-image 里的 `lib/runtime` | 在 x86_64 上跑 aarch64 的 `java`，直接无法执行 |
| **Skiko 原生库** | 换成 `libskiko-linux-x64.so`，并**删掉宿主那份 arm64 的 .so** | 两份并存时可能加载到错的那份，表现为启动崩溃或渲染异常 |
| **启动器** | `jpackage` **不能**跨平台生成启动器（ELF 是宿主架构），改用 **shell 脚本**启动器调 `runtime/bin/java -cp ...` | 启动器是 aarch64 ELF，在 x86_64 上无法执行 |

应用自己的 jar 是平台无关的，**直接用 aarch64 构建出的那份**即可，不必重新编译。

## 三、Windows x64 / arm64（免装 Java 的 ZIP）

关键教训：**只放应用的 fat jar 会闪退**。Compose 桌面端必须有 Skiko 的原生库（`.dll`），
`gradle fatJar` 打出的 jar **不含**它。表现是启动即
`java.lang.ExceptionInInitializerError`，位置在
`androidx.compose.ui.scene.skia.SurfaceSkiaLayerComponent.<init>`。
**实测确认：补上 `skiko-windows-x64.jar` 后正常启动**（2026-10-04，用户真机反馈）。

因此 ZIP 里必须有四样：应用 jar、`skiko-windows-<arch>.jar`、免装 JRE（`runtime/bin/java.exe`）、
`.bat` 启动器。Skiko 的 jar 从 Maven 取：

```
https://repo1.maven.org/maven2/org/jetbrains/skiko/skiko-awt-runtime-windows-x64/<version>/...
https://repo1.maven.org/maven2/org/jetbrains/skiko/skiko-awt-runtime-windows-arm64/<version>/...
```

Windows 免装 JRE 用目标架构的 JRE 解压后放进 `runtime/`（大小与架构都要对：
x64 与 arm64 各一份，别混）。启动器里设 `JMCOMIC_RENDER=GL` 可绕开部分环境的 OpenGL 上下文问题。

## 四、验收（`50-verify-desktop.sh`）

判据必须落在**产物形态**上，体积对比查不出空包：

| 检查 | 为什么 |
| --- | --- |
| 时间戳是当天 | 构建失败时旧产物还在原地，`ls` 有文件不等于成功 |
| Windows 包内有 `skiko-windows*.jar` 与 `runtime/bin/java` | 缺前者启动即崩，缺后者不是"免装" |
| Linux 便携包内有 `libskiko*.so` | 缺它启动即崩 |
| deb 内有图标条目 | 缺它桌面没图标，且安装脚本可能报错 |
| 产物名带正确版本号 | 名字错会导致用户下错包、或发布时漏传 |
