import AppKit
import ServiceManagement
import WidgetKit

/// Periodically refreshes the snapshot and asks WidgetKit to redraw the widget.
@MainActor
final class Monitor: ObservableObject {
    static let refreshInterval: TimeInterval = 5 * 60

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    private var timer: Timer?

    init() {
        snapshot = SharedStore.load()
    }

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previous = snapshot
        let next = await Task.detached { await UsageFetcher.refresh(previous: previous) }.value
        snapshot = next
        try? SharedStore.save(next)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login change failed: \(error)")
        }
    }
}
