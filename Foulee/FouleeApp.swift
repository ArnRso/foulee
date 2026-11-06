import AppKit
import SwiftUI

@main
struct FouleeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                treadmill: appDelegate.treadmill,
                sessions: appDelegate.sessions,
                loginItem: appDelegate.loginItem,
                updates: appDelegate.updates,
            )
        } label: {
            MenuBarIcon(treadmill: appDelegate.treadmill)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                treadmill: appDelegate.treadmill,
                sessions: appDelegate.sessions,
                loginItem: appDelegate.loginItem,
                updates: appDelegate.updates,
            )
        }

        Window("Statistiques Foulée", id: "statistics") {
            StatisticsView(store: appDelegate.sessions, treadmill: appDelegate.treadmill)
        }
        .defaultLaunchBehavior(.suppressed)

        Window("Diagnostic Foulée", id: "diagnostic") {
            DiagnosticView(treadmill: appDelegate.treadmill)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessions: SessionStore
    let treadmill: TreadmillController
    let loginItem = LoginItem()
    let updates = UpdateManager()

    override init() {
        sessions = SessionStore()
        treadmill = TreadmillController(sessions: sessions)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        treadmill.start()
        ShortcutAction.listen(for: treadmill)
        Task { await sessions.reload() }
    }

    /// Sécurité : le tapis reçoit Stop avant que l'app ne se ferme.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await treadmill.prepareForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
