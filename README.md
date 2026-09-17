# EvenTone · 匀声

一个原生 macOS 菜单栏小工具，减少切换耳机、切换视频时反复调音量。

[构建状态](https://github.com/hugh-zhan9/EvenTone/actions/workflows/release.yml) · [下载安装包](https://github.com/hugh-zhan9/EvenTone/releases)

**源码版本：v0.3.0，30 项音频与应用逻辑测试通过。新增独立引导校准，保留手动设备补偿；已发布版本以 Releases 为准。** 下次实际登录启动、AirPods 切换、主观听感与长时间稳定性仍需验证，详见 [验证记录](docs/VERIFICATION.md)。

- **设备补偿**：每个输出设备独立保存 -12～+12 dB 校准值，跟随系统默认输出设备。
- **引导校准**：用同一段参考声比较两副设备，回答更响 / 更轻，应用逐步计算补偿；保存后切换设备自动应用。
- **快速切换**：在当前设备旁选择已连接的输出设备，自动加载对应补偿。
- **登录启动**：使用 macOS 原生登录项，可在应用中开启、关闭及查看状态。
- **自动均衡**：轻声逐渐抬升，响声适当降低；静音门控、平滑增益、左右声道联动。
- **峰值保护**：-1 dBFS 采样峰值限幅，避免增益处理造成数字削波。
- **本地处理**：不保存、不上传音频，不读取麦克风内容。需要系统音频录制权限。

## 打开 demo

Apple Silicon Mac 可从 [Releases](https://github.com/hugh-zhan9/EvenTone/releases) 下载 `EvenTone-…-macOS-arm64.zip`，解压后打开 `EvenTone.app`。标记为 Pre-release 的是 main 分支预览版；当前安装包使用临时签名，尚未经过 Apple 公证，macOS 可能阻止打开。每个发布附带 `SHA256SUMS.txt`，可在下载目录运行 `shasum -a 256 -c SHA256SUMS.txt` 校验文件。

要求 macOS 14.2+、Swift 5.10+ / Command Line Tools。克隆仓库后先构建：

```sh
git clone git@github.com:hugh-zhan9/EvenTone.git
cd EvenTone
./scripts/build.sh
open dist/EvenTone.app
```

源码仓库不包含编译产物。构建后的应用位于 `dist/EvenTone.app`，之后可直接打开：

```sh
open dist/EvenTone.app
```

首次运行保持关闭。播放一个视频，点击右上角开关，按 macOS 提示允许系统音频录制。如系统要求退出重开，请从同一个路径重开此应用。出现输入 / 输出电平后，说明捕获到了音频。关闭控制窗口后应用仍在菜单栏运行，点击波形图标可打开面板；点击「退出」完全退出。

没有权限或电平一直为空时，到「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」检查 EvenTone。系统版本不同，设置项名称可能略有变化。应用中的「打开系统权限设置」也可跳转。没有音频时界面只显示等待，不把空电平当作授权成功。

### 切换设备与登录启动

点击当前设备旁的「切换」，选择目标设备；勾选项代表当前输出。切换后加载该设备保存的补偿，保留总开关的开关状态。未连接的蓝牙设备需先在 macOS 中连接。

开启「登录时启动」后，应用会在登录 Mac 后自动打开，不是在登录前运行后台服务。音频处理恢复上次退出前的总开关：之前开启则自动开启，之前关闭则保持关闭；首次使用默认关闭。若显示等待系统允许，可点击设置按钮处理；关闭此选项会取消注册。应用重新打开或回到前台时会刷新系统状态。

登录项注册的是当前应用位置，请保留 `dist/EvenTone.app`；移动应用后重新检查登录项状态。

### 引导校准一次，以后自动匹配

1. 连接两副输出设备，将当前设备调到舒服的音量，点击「引导校准」。
2. 暂停其他播放，保持系统音量不变。选择要匹配的设备，先戴好当前耳机，点击「试听参考设备」。
3. 戴好另一副设备，点击「试听匹配设备」。每次播放同一段 6 秒参考声。
4. 根据听感点击「偏小，再响一点」或「偏大，再轻一点」，应用调整并重新试听；可随时重听参考设备。
5. 听感接近后点击「听起来一致，保存并返回」。以后开启 EvenTone 切换设备时，会自动加载保存的补偿。

校准在当前面板内打开，按试听进度显示下一步。点击顶部「取消并返回」回到主页面，不关闭窗口，也不保存本轮调整。

校准期间暂停普通音频处理，参考声直接发送到所选设备，不改变系统默认输出和硬件音量。连接状态只在点击试听时检查，而且只检查本次试听的设备；进入、选择设备和保存时不要求两副设备同时在线。试听失败保留草稿，连接好后再次点击试听即可。系统默认输出和设备列表变化不会中止校准。取消不保存草稿；结束后在最新默认输出上恢复原来的处理开关。参考声只在内存生成，不使用麦克风。

### 手动设备补偿

手动滑块与重置仍可独立使用，完成引导校准后也能继续微调：

1. 播放一段熟悉的视频，开启 EvenTone，先把整体音量调到舒服的水平。
2. 保持同一参考片段、系统音量和整体音量，切换到另一副耳机。
3. 调整「设备音量补偿」，直到主观听感接近。每个设备自动记忆，不需点击保存。
4. 再次切换设备，补偿值应自动恢复。系统音量键仍控制系统音量。

软件无法仅凭数字信号测出耳内真实声压，所以首次校准仍需要听感判断。更改硬件音量、耳机模式或明显改变使用环境后，可能需要重新校准。自动响度均衡不会让每个瞬间一样响；这会破坏内容动态。菜单里关闭「自动响度均衡」后，设备补偿和整体音量仍有效；关闭总开关则退出处理通路。

## 开发与验证

要求 macOS 14.2+，Swift 5.10+ / Command Line Tools。无第三方包，不需要付费开发者账号来构建本地 demo。

```sh
./scripts/test.sh    # 独立测试执行器，无需 XCTest / 完整 Xcode
./scripts/build.sh   # release 编译、生成图标、打包、本机 ad-hoc 签名
open dist/EvenTone.app

# 只读诊断，不捕获音频、不修改设备设置
./dist/EvenTone.app/Contents/MacOS/EvenTone --diagnose
```

`swift build` 可检查源码编译；使用带 Info.plist 的 `.app` 运行音频功能，以便 macOS 正确显示用途说明。重新构建会覆盖本项目的 `dist/EvenTone.app`，构建前请退出正在运行的 EvenTone。

测试通过 C DSP 直接处理合成信号，覆盖响度收敛、突变峰值、静音、低底噪、立体声比例、异常浮点值、单帧、单声道、缓冲区映射和配置持久化；还覆盖设备切换的异步确认、超时与错误，以及登录项注册、取消、待批准和外部状态变化。测试失败以非零状态退出。没有把算法输出自称为耳机实测。

### 自动打包与发布

| 事件 | 结果 |
| --- | --- |
| 推送到 `main` | 测试、打包，发布 `preview-<提交 SHA 前 12 位>` 预览版 |
| 推送 `vX.Y.Z` 标签 | 测试、打包，发布正式版；标签必须与 Info.plist 版本一致 |
| 提交 PR / 手动运行 workflow | 测试和打包，仅保存 Actions 构建产物 |

发布文件为 ZIP 和 SHA-256 校验清单；Actions 构建产物保留 14 天，Releases 附件持续保留。首次流水线支持 Apple Silicon（arm64），尚未构建 Intel 版本。使用仓库自带的 `GITHUB_TOKEN`，无需配置个人令牌；构建任务只读，发布任务仅在受支持的 push 事件获得 Releases 写权限。不使用 GitHub Packages。

正式发布前，修改 `Resources/Info.plist` 中的 `CFBundleShortVersionString` 和 `CFBundleVersion`，提交并推送，再为同一提交创建匹配标签，例如：

```sh
git tag v0.3.0
git push origin v0.3.0
```

已有标签和 Release 不自动覆盖。发布前及公开草稿前会核对远端标签与构建提交，标签被移动时拒绝发布。同一提交已经发布成功时重跑发布任务会报版本已存在；上传失败可能留下草稿，应先检查该草稿与 Actions 日志，再决定如何处理。

本地检查发布脚本（打包测试要求先构建 `dist/EvenTone.app`）：

```sh
python3 -B -m unittest discover -s Tests/ReleaseTests -v
python3 -B -m unittest discover -s Tests/PackageTests -v
./scripts/package.sh dist/EvenTone.app dist/release 0.3.0
```

`EVENTONE_DIST_DIR` 可指定构建产物目录，用于验证打包而不覆盖正在使用的应用。此流水线不包含 Developer ID 签名或公证证书配置。

## MVP 边界

- 使用短时 RMS 估计，尚不是符合 EBU R128 的 LUFS 测量器；限幅为采样峰值，不是过采样真峰值限幅。
- 面向当前默认设备的单流、单声道 / 立体声 Float32 输出。多声道 / 多音频流设备会明确报不支持。
- 仅在点击切换设备时修改系统默认输出，不改变硬件音量或系统提示音的独立输出设置。指定其他输出设备的应用、独占播放、受保护内容不保证被处理；分开路由的系统提示音也可能不经过这里。
- 切换设备、休眠唤醒会重建音频通路，可能短暂中断。AirPods 通话模式、蓝牙延迟和音画同步需在实际设备验证。
- ad-hoc 签名适合本机 demo，未做 Developer ID 公证。重新编译可能导致系统重新要求授权；有签名证书时可用 `EVENTONE_SIGN_IDENTITY='证书名称' ./scripts/build.sh`。不通过关闭 Gatekeeper 绕过系统保护。
- 总开关及其他设置保存在 `local.eventone.app` 的 UserDefaults，启动恢复上次状态。故障导致总开关关闭时也保存关闭；退出释放资源不改变保存值。系统音频授权仍由 macOS 管理。

实现：SwiftUI 界面与状态管理、Core Audio process tap + 私有 aggregate、无锁原子配置的 C11 DSP。没有安装驱动，没有网络服务。

## 项目结构

```text
Sources/EvenTone/       界面、设置、设备切换与音频通路
Sources/AudioDSP/       实时音频处理（C11）
Tests/EvenToneTests/    独立测试执行器与回归测试
Resources/Info.plist    应用信息、版本号与权限说明
scripts/               构建、测试及图标生成
docs/                  设计与实机验证记录
```

设计见 [概要设计](docs/loopx/design/2026-09-16-mvp/概要设计.md) 和 [实现合同](docs/loopx/design/2026-09-16-mvp/需求设计文档.md)。实际验证与尚未验证的范围见 [VERIFICATION](docs/VERIFICATION.md)。Core Audio 路径依据 [Apple 官方示例](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) 与本机 SDK 头文件实现。

## 许可证

[MIT License](LICENSE)。
