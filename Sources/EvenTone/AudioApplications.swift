import AppKit
import CoreAudio
import Darwin

/// Called only on AudioWorker's queue. Enumeration never captures audio.
enum AudioApplications {
    static func read(deviceID: AudioObjectID) throws -> [AudioApplication] {
        let objects = try Hardware.objects(Hardware.system, kAudioHardwarePropertyProcessObjectList)
        var applications: [AudioApplication] = []
        for object in objects {
            do {
                let pid = try Hardware.value(object, kAudioProcessPropertyPID, initial: pid_t(0))
                guard pid > 0, pid != getpid() else { continue }
                let devices = try Hardware.objects(object, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
                guard devices.contains(deviceID) else { continue }
                let active = try Hardware.value(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) != 0
                let bundleID = try Hardware.string(object, kAudioProcessPropertyBundleID)
                var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                let length = proc_pidpath(pid, &path, UInt32(path.count))
                let executable = length > 0 ? URL(fileURLWithPath: String(cString: path)) : nil
                let appURL = executable.flatMap(ApplicationMuteState.owningApplication)
                    ?? NSRunningApplication(processIdentifier: pid)?.bundleURL
                if let appURL, let bundle = Bundle(url: appURL) {
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? appURL.deletingPathExtension().lastPathComponent
                    applications.append(AudioApplication(id: appURL.standardizedFileURL.path, name: name,
                                                         processIDs: [object], isActive: active))
                } else {
                    // Shared XPC services cannot safely be attributed to a browser by name alone.
                    let name = bundleID.isEmpty ? (executable?.lastPathComponent ?? "音频进程") : bundleID
                    applications.append(AudioApplication(id: "process:\(pid):\(object)", name: "\(name) (\(pid))",
                                                         processIDs: [object], isActive: active))
                }
            } catch {
                // Processes can exit between list and property reads. Only disappearance is ignored.
                let current = try Hardware.objects(Hardware.system, kAudioHardwarePropertyProcessObjectList)
                if current.contains(object) { throw error }
            }
        }
        return ApplicationMuteState.group(applications)
    }
}
