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

## 五、Windows 单体 exe（NSIS）

ZIP 版对普通用户不友好（拿到手要自己找 `.bat`）。单体 exe 的做法：

- 工具：**NSIS**（Debian 的 `nsis` 包，`apt-get install -y nsis`），`makensis` 能在 Linux 上编译 Windows exe；
- 形态：`SilentInstall silent` + `RequestExecutionLevel user` + `SetOutPath "$LOCALAPPDATA\<App>"` +
  `File /r stage\*`，然后 `Exec` 启动 `runtime\bin\javaw.exe -cp "app.jar;skiko-windows-<arch>.jar" <MainKt>`；
  用 `javaw` 是为了不弹控制台；`System::Call 'kernel32::SetEnvironmentVariable(...)'` 可设 `JMCOMIC_RENDER=GL`；
- 内容与 ZIP 版一致：应用 jar + Skiko 原生库 + 免装 JRE；
- **两个架构各出一个**（x64 与 arm64），JRE 与 Skiko 都要取对应架构，别混用；
- 验收见 `docs/PITFALLS.md` 第 12 条：`MZ` 头 + 解压看 `java.exe` 的 `file` 架构 + 包内含 `jmnext.jar`
  与 `skiko-windows-<arch>.jar`。

未验证：作者环境无法运行 Windows 程序，**exe 未在真机实跑**，只验证了结构与架构。

## 六、rpm 的跨架构构建（两个硬经验）

在 aarch64 宿主上产 x86_64 的 rpm，以及反过来，会连撞两堵墙，两堵都要拆：

**第一堵：架构检查。** 宿主 `rpmbuild` 会以 `No compatible architectures found for build` 拒绝跨架构
（试过多种 `--define` 组合无效）。绕法是让 `rpmbuild` **自己就是目标架构**：装多架构的 `rpm:amd64`
（`apt-get install -y rpm:amd64`），再用 qemu 跑它：

```bash
/usr/bin/qemu-x86_64-static /usr/bin/rpmbuild -bb \
  --define "_topdir $TOP" --define "_buildrootdir $TOP/BUILDROOT" \
  --define "__strip /bin/true" "$TOP/SPECS/jmnext.spec"
```

**第二堵（更隐蔽）：`%install` 末尾的 brp-strip。** rpm 在 `%install` 后会调用宿主的 `/usr/bin/strip`
去 strip 包内二进制；用 aarch64 的 `strip` 处理 x86_64 的 `.so` 会报
`Unable to recognise the format of the input file`，**整个 `%install` 直接失败**。
修法是交叉构建时禁用 strip：`--define "__strip /bin/true"`。

**方向反过来（宿主是 x86_64、要产 aarch64 包）**：装 `rpm:amd64` 会把系统里 arm64 的 `rpmbuild`
替换掉，于是 aarch64 那条路径也坏了。解法是**私有解包**一份 arm64 的 rpm（连同它的库）：

```bash
apt-get download rpm:arm64 librpm9:arm64 librpmio9:arm64 librpmbuild9:arm64 librpmsign9:arm64
for d in rpm_*.deb librpm*_arm64.deb; do dpkg-deb -x "$d" /opt/rpm-arm64; done
LD_LIBRARY_PATH=/opt/rpm-arm64/usr/lib/aarch64-linux-gnu /opt/rpm-arm64/usr/bin/rpmbuild -bb ...
```

**顺带两条**：
- rpm 产物名与内部版本要分别核对：`rpm -qp --qf "%{NAME} %{VERSION} %{ARCH}\n" file.rpm`
  （脚本若只是 `cp` 出来，文件名会保持 `name-version-1.cpu.rpm`）；
- `rpmbuild` 的输出**不要**用 `tail -3` 看：失败命令本身就在被截掉的那段。写进日志文件，失败时打印末尾 30 行。

## 七、跨架构 rpm 别再走 qemu：让目标架构"看起来"兼容

在 aarch64 上产 x86_64 的 rpm，常见做法是用 qemu 跑 x86_64 的 rpmbuild —— 能成，但**慢一到两个数量级**
（实测 233 秒 → 用下面的办法 83 秒，其中 rpm 那一步从一两分钟降到十几秒）。

原因是 rpm 的"没有兼容架构"判断来自 **rpmrc 的兼容表**，而不是真的编译了什么。包里全是**数据文件**
（我们已把 x86_64 的运行时交叉摆好），所以放开该检查是安全的：

```
# 自定义 rpmrc（复制系统的那份，追加两行）
arch_compat: aarch64: x86_64
buildarch_compat: aarch64: x86_64

# 然后用**原生** rpmbuild 指定目标架构
rpmbuild -bb --rcfile /opt/rpm-aarch64-custom/rpmrc --target x86_64 \
  --define "_topdir $TOP" --define "_buildrootdir $TOP/BUILDROOT" --define "__strip /bin/true" \
  "$TOP/SPECS/x.spec"
```

验证（两项都要看）：`rpm -qp --qf '%{NAME} %{VERSION} %{ARCH}\n'` 的 `%{ARCH}` 必须是目标架构；
`rpm -qpl` 里必须能看到该架构的运行时文件。

**适用边界**：只适用于**纯文件负载**的包。若 spec 里会编译代码（`%build` 真跑 gcc 等），这个技巧不成立 ——
那时必须用目标架构的执行环境（qemu 或真机）。`__strip /bin/true` 仍然必需：宿主 strip 处理不了目标架构的 .so。
