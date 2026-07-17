import SwiftUI
import AppKit

/// A bare SPM executable has no Info.plist/app bundle, so without this the
/// process never becomes a proper foreground app: its window can be drawn
/// and clicked, but keyboard focus stays with whatever app was frontmost
/// before it launched (e.g. the IDE), and keystrokes leak there instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}

@main
struct MySQLMacClientApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var connectionStore = ConnectionStore()
    @StateObject private var appState = AppState()
    @StateObject private var appearanceStore = AppearanceStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = appState.activeSession {
                    MainWindowView(session: session) {
                        Task { await appState.disconnect() }
                    }
                } else {
                    ConnectionFormView(connectionStore: connectionStore, appState: appState)
                }
            }
            .frame(minWidth: 800, minHeight: 560)
            .environmentObject(appearanceStore)
            .preferredColorScheme(appearanceStore.mode.colorScheme)
            .toolbar {
                // Placed at the app root (not inside MainWindowView) so it
                // stays put as more items get added here later, regardless
                // of which screen (connection form vs. main window) is
                // showing. `.navigation` placement is what puts it at the
                // toolbar's leading edge.
                ToolbarItem(placement: .navigation) {
                    Button {
                        Task { await appState.disconnect() }
                    } label: {
                        Label {
                            Text("Yeni Bağlantı")
                        } icon: {
                            Image.bundled("new_connection", fallbackSystemImage: "plus.circle")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 30, height: 30)
                        }
                    }
                    .help("Yeni Bağlantı")
                }
            }
        }
    }
}
