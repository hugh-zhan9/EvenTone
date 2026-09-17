import SwiftUI

@available(macOS 14.2, *)
struct CalibrationView: View {
    @ObservedObject var model: AppModel
    private let mint = Color(red: 0.57, green: 0.91, blue: 0.77)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("匹配设备音量").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("取消并返回") { model.finishCalibration(save: false) }
                    .buttonStyle(.plain).foregroundStyle(mint)
                    .accessibilityIdentifier("calibrationCancel")
            }
            Text("用同一段声音，让两副设备听起来一样响。\n请先暂停其他播放，保持系统音量不变。")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let session = model.calibration {
                VStack(alignment: .leading, spacing: 12) {
                    Text("参考设备 · \(model.device?.name ?? "未连接")")
                        .font(.system(size: 13, weight: .medium))
                    Picker("匹配设备", selection: Binding(get: { session.targetUID ?? "" }, set: model.selectCalibrationTarget)) {
                        Text("请选择另一副设备").tag("")
                        if let uid = session.targetUID, !model.outputDevices.contains(where: { $0.uid == uid }) {
                            Text("已选设备（等待连接）").tag(uid)
                        }
                        ForEach(model.outputDevices.filter { $0.uid != session.referenceUID }, id: \.uid) { output in
                            Text(output.name).tag(output.uid)
                        }
                    }
                    .disabled(model.busy)
                    .accessibilityIdentifier("calibrationTarget")
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))

                if session.targetUID != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(session.heardReference ? "戴好待匹配设备，比较一下" : "先戴好参考设备，记住它的音量")
                            .font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 10) {
                            Button { model.playCalibration(.reference) } label: {
                                Label(session.heardReference ? "重听参考" : "试听参考设备", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(mint)
                            .disabled(model.busy)
                            .accessibilityIdentifier("calibrationPlayReference")

                            if session.heardReference {
                                Button { model.playCalibration(.target) } label: {
                                    Label("试听匹配设备", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                .background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                .foregroundStyle(mint)
                                .disabled(model.busy)
                                .accessibilityIdentifier("calibrationPlayTarget")
                            }
                        }
                    }
                } else {
                    Text("选择要匹配的设备后，开始试听。")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }

                if session.heardTarget {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("这副设备比参考设备…").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(String(format: "%+.1f dB", session.draftTrim))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(mint)
                        }
                        HStack(spacing: 10) {
                            Button("偏小，再响一点") { model.adjustCalibration(.quieter) }
                                .accessibilityIdentifier("calibrationQuieter")
                            Button("偏大，再轻一点") { model.adjustCalibration(.louder) }
                                .accessibilityIdentifier("calibrationLouder")
                        }.disabled(model.busy || !session.canCompare)
                        Text("调整后会自动重播。可随时重听参考设备。")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        if session.atLimit {
                            Text("已到补偿上限或下限。仍不匹配时，请返回调整参考设备。")
                                .font(.system(size: 11)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button { model.finishCalibration(save: true) } label: {
                            Text("听起来一致，保存并返回")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundStyle(.black)
                                .background(mint, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain).disabled(model.busy || !session.canCompare)
                        .accessibilityIdentifier("calibrationSave")
                    }
                }

                if let error = model.calibrationError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if model.busy {
                        ProgressView().controlSize(.small)
                        Text("正在处理…")
                    } else {
                        Text(model.calibrationPlaying == nil ? "每次试听 6 秒 · 未保存前不改原补偿" : "正在试听 · 6 秒后停止")
                    }
                    Spacer()
                    if model.calibrationPlaying != nil {
                        Button("停止") { model.stopCalibrationSound() }
                            .disabled(model.busy).accessibilityIdentifier("calibrationStop")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .buttonStyle(.bordered)
        .padding(24).frame(width: 426)
        .background(Color(red: 0.065, green: 0.09, blue: 0.085))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
