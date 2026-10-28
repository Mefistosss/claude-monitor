import AppKit
import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Runs in the background (no Dock icon). The window opens on a manual launch,
/// on a widget tap, or when the app is opened again; not at login.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start()

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didSetUpLoginItem") {
            defaults.set(true, forKey: "didSetUpLoginItem")
            monitor.launchAtLogin = true
        }

        if !launchedAsLoginItem {
            showWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Claude Monitor"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: MainView(monitor: monitor))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Task { await monitor.refresh() }
    }
}

struct MainView: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if let snapshot = monitor.snapshot {
                    UsageCard(snapshot: snapshot)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
            .frame(width: 330, height: 155)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack {
                if let fetchedAt = monitor.snapshot?.fetchedAt, fetchedAt > .distantPast {
                    Text("Updated \(Text(fetchedAt, style: .relative)) ago")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(monitor.isRefreshing)
            }
            .font(.callout)

            Toggle("Launch at login", isOn: $monitor.launchAtLogin)

            Text("To add the widget: right-click the desktop → Edit Widgets → Claude Monitor.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Quit Claude Monitor") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 370)
    }
}
