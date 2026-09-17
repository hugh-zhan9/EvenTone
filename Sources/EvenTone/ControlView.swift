import SwiftUI

@available(macOS 14.2, *)
struct ControlView: View {
    @ObservedObject var model: AppModel
    @State private var showCalibration = false
    private let mint = Color(red: 0.57, green: 0.91, blue: 0.77)
    private let secondary = Color.white.opacity(0.52)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(mint.opacity(0.12)).frame(width: 48, height: 48)
                    Image(systemName: "waveform.path").font(.system(size: 27, weight: .medium)).foregroundStyle(mint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("EvenTone").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("匀声 · 舒服的音量，始终如一").font(.system(size: 11)).foregroundStyle(secondary)
                }
                Spacer()
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("v\(version)").font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(mint).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(mint.opacity(0.1), in: Capsule())
                        .accessibilityLabel("版本 \(version)")
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(model.error != nil ? Color.orange : model.enabled ? mint : secondary).frame(width: 6, height: 6)
                        Text(model.status).font(.system(size: 12, weight: .medium))
                    }
                    Spacer()
                    Toggle("启用 EvenTone", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                        .labelsHidden().toggleStyle(.switch).tint(mint).accessibilityIdentifier("enableProcessing")
                        .disabled(model.busy)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("让声音").foregroundStyle(.white.opacity(0.9))
                    Text("恰到好处。").foregroundStyle(mint)
                }.font(.system(size: 27, weight: .medium))
                HStack(spacing: 16) {
                    levelMeter(title: "输入", value: model.meters.inputDB)
                    Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(secondary)
                    levelMeter(title: "输出", value: model.meters.outputDB)
                }
                HStack {
                    Text("自动增益").foregroundStyle(secondary)
                    Text(model.enabled ? String(format: "%+.1f dB", model.meters.automaticGainDB) : "—")
                        .monospacedDigit().foregroundStyle(mint)
                    Spacer()
                    Text(model.meters.reductionDB > 0.5 && model.enabled ? "峰值保护中" : "峰值保护就绪")
                        .foregroundStyle(secondary)
                }.font(.system(size: 10))
            }
            .padding(18)
            .background(LinearGradient(colors: [mint.opacity(0.10), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(mint.opacity(0.12), lineWidth: 1))

            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Label("整体音量", systemImage: "speaker.wave.2").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(model.volume * 100))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(mint)
                }
                Slider(value: $model.volume, in: 0...1).tint(mint).accessibilityLabel("整体音量")
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("自动响度均衡").font(.system(size: 13, weight: .medium))
                        Text("柔和拉近不同视频的音量差距").font(.system(size: 11)).foregroundStyle(secondary)
                    }
                    Spacer()
                    Toggle("自动响度均衡", isOn: $model.automatic).labelsHidden().toggleStyle(.switch).tint(mint)
                }
            }

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)

            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "hifispeaker").font(.system(size: 19)).foregroundStyle(mint)
                        .frame(width: 36, height: 36).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前输出设备").font(.system(size: 10)).foregroundStyle(secondary)
                        Text(model.device?.name ?? "未连接").font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    Spacer()
                    if let device = model.device {
                        Text(String(format: "%.1f kHz", device.sampleRate / 1000))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(secondary)
                    }
                    Menu {
                        if model.outputDevices.isEmpty {
                            Text("没有可用的输出设备")
                        }
                        ForEach(model.outputDevices, id: \.uid) { output in
                            Button { model.selectOutput(uid: output.uid) } label: {
                                if output.uid == model.device?.uid {
                                    Label(output.name, systemImage: "checkmark")
                                } else {
                                    Text(output.name)
                                }
                            }
                        }
                    } label: {
                        Label("切换", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(mint)
                    }
                    .menuStyle(.borderlessButton)
                    .environment(\.colorScheme, .dark)
                    .fixedSize()
                    .foregroundStyle(mint)
                    .disabled(model.busy)
                    .accessibilityIdentifier("switchOutputDevice")
                }
                HStack {
                    Text("设备音量补偿").font(.system(size: 12))
                    Button { showCalibration.toggle() } label: {
                        Image(systemName: "questionmark.circle").foregroundStyle(secondary)
                    }.buttonStyle(.plain).help("如何校准两副耳机")
                    Spacer()
                    Text(String(format: "%+.1f dB", model.trim)).font(.system(size: 12, design: .monospaced)).foregroundStyle(mint)
                    Button("重置") { model.trim = 0 }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(secondary)
                        .disabled(model.device == nil)
                }
                Slider(value: $model.trim, in: -12...12, step: 0.5).tint(mint)
                    .disabled(model.device == nil).accessibilityLabel("当前设备音量补偿")
                HStack {
                    Text("更轻 −12 dB")
                    Spacer()
                    Text("按设备自动记忆")
                    Spacer()
                    Text("更响 +12 dB")
                }.font(.system(size: 9)).foregroundStyle(secondary)
                if showCalibration {
                    Text("播放一段熟悉的视频，开启 EvenTone。保持系统音量与整体音量不变，切换耳机后调节这里，让听感接近。每副耳机会单独记住补偿值。")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineSpacing(4)
                        .padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            LoginItemView(controller: model.loginItem, tint: mint, secondary: secondary)

            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).lineSpacing(3)
                    Button("打开系统权限设置") { model.openPermissions() }.buttonStyle(.plain).underline().font(.system(size: 11))
                }.foregroundStyle(.orange.opacity(0.9)).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 5) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("仅本机处理 · 不保存音频").font(.system(size: 10))
                Spacer()
                Button("退出") { model.shutdown(); NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).accessibilityIdentifier("quitEvenTone")
            }.foregroundStyle(secondary)
        }
        .padding(24)
        .frame(width: 426)
        .background(Color(red: 0.065, green: 0.09, blue: 0.085))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { model.loginItem.refresh() }
    }

    private func levelMeter(title: String, value: Float) -> some View {
        let level = model.enabled && !model.suspended && model.receivingAudio ? value : -120
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).foregroundStyle(secondary)
                Spacer()
                Text(level < -90 ? "— dBFS" : String(format: "%.1f dBFS", level)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
            }.font(.system(size: 10))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule().fill(mint.opacity(0.8)).frame(width: geometry.size.width * CGFloat(min(1, max(0, (level + 60) / 60))))
                }
            }.frame(height: 5)
        }
    }
}

private struct LoginItemView: View {
    @ObservedObject var controller: LoginItemController
    let tint: Color
    let secondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录时启动").font(.system(size: 12, weight: .medium))
                    Text(controller.caption).font(.system(size: 10)).foregroundStyle(secondary)
                }
                Spacer()
                Toggle("登录时启动", isOn: Binding(get: { controller.isRegistered }, set: controller.setEnabled))
                    .labelsHidden().toggleStyle(.switch).tint(tint)
                    .accessibilityIdentifier("launchAtLogin")
            }
            if controller.needsApproval {
                Button("打开系统登录项设置") { controller.openSettings() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(tint)
            }
            if let error = controller.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
