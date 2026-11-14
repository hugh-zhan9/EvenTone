/// Coordinates native startup without treating a Bluetooth call transition as
/// a user request to disable processing. Cleanup errors must never be hidden.
enum ProcessingStartup {
    static func currentCallDeviceUID(read: () throws -> OutputDevice) throws -> String? {
        let device = try read()
        return device.isBluetoothCallMode ? device.uid : nil
    }

    static func run(callMode: Bool, start: () throws -> Void,
                    stop: () throws -> Void, currentCallMode: () throws -> Bool) throws -> Bool {
        if callMode {
            try stop()
            return false
        }
        do {
            try start()
            return true
        } catch {
            let startupError = error
            try stop()
            if (try? currentCallMode()) == true { return false }
            throw startupError
        }
    }
}
