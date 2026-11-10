import Foundation

struct AudioApplication: Identifiable, Equatable {
    let id: String
    let name: String
    var processIDs: Set<UInt32>
    var isActive: Bool
    var isMuted = false
}

/// Session-only intent. A failed HAL operation never commits a new selection.
struct ApplicationMuteState {
    private(set) var selected: [String: String] = [:]

    func processIDs(in applications: [AudioApplication]) -> Set<UInt32> {
        Set(applications.filter { selected[$0.id] != nil }.flatMap(\.processIDs))
    }

    mutating func set(_ application: AudioApplication, muted: Bool,
                      applications: [AudioApplication], apply: (Set<UInt32>) throws -> Void) rethrows {
        var next = self
        if muted { next.selected[application.id] = application.name }
        else { next.selected.removeValue(forKey: application.id) }
        try apply(next.processIDs(in: applications))
        self = next
    }

    mutating func clear() { selected.removeAll() }

    func rows(_ applications: [AudioApplication]) -> [AudioApplication] {
        var rows = applications.filter { $0.isActive || selected[$0.id] != nil }
        for (id, name) in selected where !rows.contains(where: { $0.id == id }) {
            rows.append(AudioApplication(id: id, name: name, processIDs: [], isActive: false))
        }
        return rows.map { row in
            var row = row
            row.isMuted = selected[row.id] != nil
            return row
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    static func group(_ processes: [AudioApplication]) -> [AudioApplication] {
        var groups: [String: AudioApplication] = [:]
        for process in processes {
            if var group = groups[process.id] {
                group.processIDs.formUnion(process.processIDs)
                group.isActive = group.isActive || process.isActive
                groups[process.id] = group
            } else { groups[process.id] = process }
        }
        return Array(groups.values)
    }

    /// The outer .app owns embedded browser helpers; do not merge by a name prefix.
    static func owningApplication(at executable: URL) -> URL? {
        var candidate = executable.standardizedFileURL
        var result: URL?
        while candidate.path != "/" {
            if candidate.pathExtension == "app" { result = candidate }
            candidate.deleteLastPathComponent()
        }
        return result
    }
}

/// Owns the transaction across original-output suppression and processed-mix exclusion.
/// A sticky failure survives dropped UI responses until explicit teardown/restart.
final class ProcessMuteRoutingState {
    private(set) var applied: Set<UInt32> = []
    private var failure: Error?

    func reset(applied: Set<UInt32> = []) {
        self.applied = applied
        failure = nil
    }

    func checkHealth() throws {
        if let failure { throw failure }
    }

    func update(_ target: Set<UInt32>, suppress: (Set<UInt32>) throws -> Void,
                exclude: (Set<UInt32>) throws -> Void, cleanup: () throws -> Void) throws {
        try checkHealth()
        guard target != applied else { return }
        do {
            try suppress(applied.union(target))
            try exclude(target)
            try suppress(target)
            applied = target
        } catch {
            let original = error
            do { try cleanup(); failure = original }
            catch { failure = MuteRoutingFailure(message: "\(original.localizedDescription)\n\(error.localizedDescription)") }
            throw failure!
        }
    }
}

private struct MuteRoutingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
