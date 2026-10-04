# 踩过的坑（都是"编过但一跑就崩"或"看着成功其实没出包"）

## 1. `debug` 构建不跑 R8
`:app:compile*DebugKotlin` 永远查不出这些：**跨模块重复类**、只有 release 才启用的 shrink/优化问题、
签名配置错误。**Android 侧每次至少跑一次 `:app:assembleFullRelease`**，否则"编译通过"是假的安全感。

## 2. 跨模块同名同包类
`app` 与 `shared` 若在同一包名下有同名类，R8 会报
`Type X is defined multiple times: shared.jar:.../X.class, app/.../X.class`，且**一次只报一个**。
检出办法（按 FQN 而不是按类型名比对）：

```bash
# 列出两个模块中同包同名的类
for f in $(find app/src/main/kotlin -name '*.kt'); do
  pkg=$(grep -m1 '^package ' "$f" | sed 's/package //')
  for t in $(grep -oE '^(class|object|interface|enum class|data class) [A-Za-z0-9_]+' "$f" | awk '{print $NF}'); do
    echo "$pkg.$t"; done; done | sort > /tmp/app.types 2>/dev/null
# 同样的方式导出 shared 的类型，再 comm -12 取交集
```

## 3. `R` 与 `BuildConfig` 不受编译期检查保护
改 `namespace` / `applicationId` 时：显式 `import com.old.R`、以及**同包隐式**使用的 `R.` / `BuildConfig.` 都会断。
Manifest 里 `android:name=".Foo"` 是相对 `namespace` 解析的，类搬家后必须写全限定名。

## 4. 同一个包名有两种写法
点号 `com.old.pkg` 与斜杠 `com/old/pkg/`。批量替换只改一种，另一种会留在**打包脚本**里（脚本读版本号、
校验主类名），表现为脚本静默失败、产出空包。

## 5. 产物新鲜度：旧包充数
构建失败时旧的 APK / zip 仍在原地，`ls` 一看"有文件"就以为成功。
**判据必须包含时间戳与包内条目**（例如 Windows 包里是否有 `skiko-windows-*.jar` 与 `runtime/bin/java`）。

## 6. 容器里看不到宿主机路径
chroot/proot 的绑定挂载会掉。表现是 `cd: 目录不存在`，很容易误判成项目被删。
先跑 `10-enter.sh` 的挂载自检；Android 出包还需要 SDK 与 `~/.android`（签名密钥）挂进去。

## 7. `aapt2` 的架构
`build-tools` 里可能同时有 `aapt2` 的 x86_64 与 arm64 版本：在 arm64 设备上执行 x86_64 那份会报
`cannot execute binary file: Exec format error`。选与目标架构一致的那份（本工具用 `AAPT2_BUILD_TOOLS` 配置）。
注意 `apksigner` 是脚本 + jar，Termux 侧也能跑。

## 8. 签名密钥绝不入库
`keystore.properties` 与 `*.jks` 必须排除在版本控制外（本工具只把 `~/.android` **挂载**进容器）。

## 9. 用 `tail` 看构建输出 = 自断线索

排查构建失败时，把输出接到 `tail -N`（或 `grep 'FAILED'`）会**截掉报错正文**，只剩一行
`Task :x FAILED`。同一个坑在 Android R8、rpm 打包、权限错误上各踩一次。
正确做法：**只打印目标步骤的完整段落**，例如

```bash
gradle ... 2>&1 | sed -n '/5\/6 rpm/,/6\/6/p' | head -30
```

## 10. 范围 sed 会误删行

用 `sed -i "$((A-10)),${B}s|...|...|"` 这类**范围**替换时，范围内每一行都会被处理，很容易把
`Name:` 这种只在部分行出现的字段删空。表现是 `rpmbuild` 报 `Name field must be present`。
改多行段落时：先打印段落，再按**单行定位**改，改完再打印回看。

## 11. 带引号的 heredoc 不展开变量

`cat > file <<'EOF'` 里的 `$V` 是**字面量**，写进 deb 的 `control` 或 rpm 的 `.spec` 会直接失败
（`'Version' field value '$V': version number does not start with digit`）。两种正确做法：

- 用占位符 + 事后替换： heredoc 里写 `@V@`，紧跟一行 `sed -i "s/@V@/$V/" file`；
- 或去掉引号 `<<EOF`（但要先确认正文里没有 `$RPM_BUILD_ROOT` 这类会被误展开的宏）。

## 12. 单体 exe 的验收要落到"实物"

NSIS 打出的 exe，用 `7z l` 看到的路径是**解压目标路径**，形如
`$LOCALAPPDATA/JMNeXt/runtime/bin/java.exe`。所以：

- 判据写 `grep -q 'runtime/bin/java.exe'`（子串即可），不要写成从行首锚定；
- 更硬的判据是**解压后看实物**：`7z x -o<dir> app.exe`，再对 `java.exe` 跑 `file`。
  这一步能抓出"arm64 的包误装了 x64 的 JRE"——那种包装得上、却双击即崩，只看文件存在发现不了。
  实测输出形如 `PE32+ executable for MS Windows (console), ARM64`。

## 13. rpm 的产物名与内部版本

`rpmbuild -bb` 的输出名由 spec 的 `Name`/`Version`/`Release` 与 `_target_cpu` 决定，
脚本若只是 `cp` 出来，文件名会保持 `name-version-1.cpu.rpm`。要统一命名，就在复制时改名
（`cp {} "$OUT/Linux-aarch64-$V.rpm"`），并确认 spec 的 `Version` 也跟版本号同步 ——
否则**文件名对了、包内版本还是旧的**。核对命令：

```bash
rpm -qp --qf "%{NAME} %{VERSION}\n" dist/Linux-aarch64-<版本>.rpm
```

## 14. `set -e` 下的 `cmd && VAR=1` 会静默中止

在 `set -euo pipefail` 的脚本里，`[ -n "$(find ...)" ] && RPM_OK=1` 在 `find` 无结果时返回非零，
**整个脚本当场中止**，后面的诊断打印与收尾逻辑一行都不会执行。表现是"我加的日志打印怎么没生效"。
改成 `if [ -n "$(...)" ]; then RPM_OK=1; fi`。

## 15. 交叉构建 rpm 必须禁用 strip

`%install` 之后 rpm 会用宿主的 `strip` 处理包内二进制。宿主与目标架构不同时（aarch64 的 strip 处理
x86_64 的 `.so`）会报 `Unable to recognise the format of the input file`，并让 `%install` 失败。
修法：`--define "__strip /bin/true"`。详见 `DESKTOP-PACKAGING.md` 第六节。
