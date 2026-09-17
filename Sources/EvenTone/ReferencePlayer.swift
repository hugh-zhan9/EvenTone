import AVFAudio
import Foundation

// Owned and used only by AudioWorker's serial queue. No input node or recording API.
final class ReferencePlayer {
    private var player: AVAudioPlayer?
    private var requestedUID: String?
    private var sound: Data?

    func play(uid: String, volume: Double, trim: Double) throws {
        stop()
        guard volume > 0 else {
            throw AudioFailure(message: "整体音量为零，请返回调整后再试听。")
        }
        guard try OutputDevice.available().contains(where: { $0.uid == uid }) else {
            throw AudioFailure(message: "这次要试听的设备未连接或不可用，连接后再次点击试听即可。")
        }
        if sound == nil { sound = ReferenceSignal.wav() }
        let next = try AVAudioPlayer(data: sound!)
        next.currentDevice = uid
        next.volume = ReferenceSignal.playbackVolume(volume: volume, trim: trim)
        guard next.prepareToPlay(), next.currentDevice == uid, next.play(), next.currentDevice == uid else {
            next.stop()
            throw AudioFailure(message: "无法在选定设备播放参考声，请确认设备连接后重试。")
        }
        player = next
        requestedUID = uid
    }

    func isPlaying() throws -> Bool {
        guard let player else { return false }
        guard player.currentDevice == requestedUID else {
            stop()
            throw AudioFailure(message: "试听的输出设备发生变化，本次试听已停止。")
        }
        return player.isPlaying
    }

    func stop() {
        player?.stop()
        player = nil
        requestedUID = nil
    }
}
