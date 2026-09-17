import Foundation

struct CalibrationSession {
    enum Side { case reference, target }
    enum Feedback { case louder, quieter }

    let referenceUID: String
    let referenceName: String
    let referenceTrim: Double
    let volume: Double
    private(set) var targetUID: String?
    private(set) var draftTrim: Double = 0
    private(set) var heardReference = false
    private(set) var heardTarget = false
    private(set) var step: Double = 2
    private var lastFeedback: Feedback?

    init(referenceUID: String, referenceName: String, referenceTrim: Double, volume: Double) {
        self.referenceUID = referenceUID
        self.referenceName = referenceName
        self.referenceTrim = referenceTrim
        self.volume = volume
    }

    var canCompare: Bool { heardReference && heardTarget && targetUID != nil }
    var atLimit: Bool { abs(draftTrim) >= 12 }

    mutating func selectTarget(uid: String, trim: Double) {
        targetUID = uid.isEmpty || uid == referenceUID ? nil : uid
        draftTrim = trim.isFinite ? min(12, max(-12, trim)) : 0
        heardTarget = false
        step = 2
        lastFeedback = nil
    }

    mutating func markPlayed(_ side: Side) {
        if side == .reference { heardReference = true }
        else if targetUID != nil { heardTarget = true }
    }

    mutating func adjust(_ feedback: Feedback) {
        guard canCompare else { return }
        if let lastFeedback, lastFeedback != feedback { step = max(0.5, step / 2) }
        lastFeedback = feedback
        let next = min(12, max(-12, draftTrim + (feedback == .louder ? -step : step)))
        if next != draftTrim { heardTarget = false }
        draftTrim = next
    }

    mutating func preparePlayback(_ side: Side) {
        if side == .reference { heardReference = false }
        else { heardTarget = false }
    }

    @discardableResult
    func save(to preferences: Preferences) -> Bool {
        guard canCompare, let targetUID else { return false }
        preferences.setTrim(draftTrim, for: targetUID)
        return true
    }
}
