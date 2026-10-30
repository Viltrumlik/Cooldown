import CooldownCore
import Foundation

struct TargetRow: Identifiable {
    let target: any CleanTarget
    /// nil until the first scan finishes.
    var scan: ScanResult?
    var isEnabled: Bool

    var info: TargetInfo { target.info }
    var id: String { info.id }
    var hasWork: Bool { scan?.hasWork ?? false }
}

struct GroupSection: Identifiable {
    let group: TargetGroup
    let rows: [TargetRow]
    var id: TargetGroup { group }
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case cleaning(done: Int, total: Int)
    }

    @Published private(set) var rows: [TargetRow]
    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastReport: CleanReport?
    /// Set after the first click when the selection includes risky items.
    @Published private(set) var awaitingConfirmation = false
    @Published private(set) var launchAtLogin = LaunchAtLogin.isEnabled
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var isHot = false
    @Published private(set) var hasCompletedFirstScan = false

    private let preferences: Preferences
    private var lastRefresh: Date?
    private var pollTask: Task<Void, Never>?

    init(targets: [any CleanTarget] = Catalog.defaultTargets(), preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.rows = targets.map { TargetRow(target: $0, scan: nil, isEnabled: preferences.isEnabled($0.info)) }
        startThermalPolling()
    }

    // MARK: - Derived state

    var menuBarSymbol: String { isHot ? "flame" : "snowflake" }

    var isBusy: Bool { phase != .idle }

    /// True until every target has reported once, so rows for tools that
    /// aren't installed never flash up and disappear.
    var isFirstScan: Bool { !hasCompletedFirstScan }

    var sections: [GroupSection] {
        TargetGroup.allCases.compactMap { group in
            let visible = rows.filter { $0.info.group == group && $0.scan != .notApplicable }
            return visible.isEmpty ? nil : GroupSection(group: group, rows: visible)
        }
    }

    var selectedRows: [TargetRow] { rows.filter { $0.isEnabled && $0.hasWork } }
    var selectedBytes: Int64 { selectedRows.reduce(0) { $0 + ($1.scan?.bytes ?? 0) } }
    var selectedProcessCount: Int { selectedRows.reduce(0) { $0 + ($1.scan?.processCount ?? 0) } }
    var selectionHasCaution: Bool { selectedRows.contains { $0.info.risk == .caution } }

    // MARK: - Intents

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isEnabled = enabled
        preferences.setEnabled(enabled, for: id)
        awaitingConfirmation = false
    }

    /// Called whenever the popover opens.
    func refreshIfStale() {
        // Reopening the popover never carries over a half-given confirmation.
        awaitingConfirmation = false
        // The user may have changed Login Items in System Settings.
        launchAtLogin = LaunchAtLogin.isEnabled
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 15 { return }
        refresh()
    }

    func refresh() {
        guard !isBusy else { return }
        phase = .scanning
        lastRefresh = Date()
        awaitingConfirmation = false
        let targets = rows.map(\.target)

        Task {
            async let snapshot = SystemMonitor.snapshot()
            await withTaskGroup(of: (String, ScanResult).self) { group in
                for target in targets {
                    group.addTask { (target.id, await target.scan()) }
                }
                for await (id, result) in group {
                    if let index = rows.firstIndex(where: { $0.id == id }) {
                        rows[index].scan = result
                    }
                }
            }
            hasCompletedFirstScan = true
            let fresh = await snapshot
            self.snapshot = fresh
            applyThermal(speedLimit: fresh.cpuSpeedLimit, thermal: fresh.thermal)
            phase = .idle
        }
    }

    func cleanTapped() {
        guard !isBusy, !selectedRows.isEmpty else { return }
        if selectionHasCaution && !awaitingConfirmation {
            awaitingConfirmation = true
            return
        }
        awaitingConfirmation = false

        // Stop processes first: they may hold the files we are about to delete.
        let work = selectedRows
            .map(\.target)
            .sorted { ($0.info.group == .processes ? 0 : 1) < ($1.info.group == .processes ? 0 : 1) }
        phase = .cleaning(done: 0, total: work.count)

        Task {
            var outcomes: [CleanOutcome] = []
            for (index, target) in work.enumerated() {
                outcomes.append(await target.clean())
                phase = .cleaning(done: index + 1, total: work.count)
            }
            lastReport = CleanReport(outcomes: outcomes)
            phase = .idle
            refresh()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: - Menu bar icon

    /// Cheap check every 30 s so the icon turns into a flame when the Mac is
    /// throttling, even while the popover is closed.
    private func startThermalPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let speed = await SystemMonitor.cpuSpeedLimit()
                let thermal = SystemMonitor.thermalLevel()
                self?.applyThermal(speedLimit: speed, thermal: thermal)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func applyThermal(speedLimit: Int?, thermal: ThermalLevel) {
        // Same threshold as SystemSnapshot.isThrottled and the CPU tile.
        isHot = (speedLimit ?? 100) < 90 || thermal >= .serious
    }
}
