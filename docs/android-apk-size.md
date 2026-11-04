# Android APK 体积优化

项目是 Flutter 应用，直接运行 `flutter build apk --release` 会生成包含多个 CPU 架构的通用 APK。大部分手机只需要其中一个架构，因此优先按 ABI 拆分发布包，减少用户下载和安装的体积；无需删减业务功能或依赖。

## 分 ABI 构建 APK

```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
```

构建结果位于 `build/app/outputs/flutter-apk/`，通常包括：

- `app-armeabi-v7a-release.apk`：32 位 ARM 设备
- `app-arm64-v8a-release.apk`：64 位 ARM 设备，适用于大多数现代 Android 手机
- `app-x86_64-release.apk`：x86_64 设备或模拟器

按设备选择对应 APK 分发。不要把多个 ABI 的 APK 一起安装到同一设备。相比通用 APK，单个拆分包不会包含其他架构的 Flutter 引擎和原生插件库；总体积降低多少取决于所用 Flutter 版本和插件，需以实际构建结果为准。

## Google Play 发布

应用商店发布建议使用 Android App Bundle，由 Google Play 根据设备生成只含所需 ABI 等资源��安装包：

```bash
flutter build appbundle --release
```

生成文件通常位于 `build/app/outputs/bundle/release/app-release.aab`。AAB 不能直接像 APK 一样安装；本地测试仍可使用上面的分 ABI APK。

## 注意事项

- 必须使用 `--release`；Debug APK 仅用于开发调试，不应作为发布包比较或分发。
- 不要只构建 `arm64-v8a` 后面向所有设备分发，否则不支持 64 位 ARM 的设备将无法安装。若只面向已确认的 arm64 设备，可以使用 `flutter build apk --release --target-platform android-arm64` 构建单架构包。
- 本仓库的 `android/app/build.gradle.kts` 未配置 ABI 限制；通过 Flutter 的 `--split-per-abi` 按需拆包，避免把特定架构限制写入所有构建。
- 如需继续优化，先用 Android Studio APK Analyzer 检查 release APK 中各 ABI 的 `.so`、资源及依赖占比，再决定是否移除未使用依赖；不要未经验证开启 R8/资源压缩，以免影响插件功能。
