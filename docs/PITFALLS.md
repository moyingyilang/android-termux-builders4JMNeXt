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
