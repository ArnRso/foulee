import AppKit
import FTMSKit
import SwiftUI

/// Panneau ouvert depuis l'icône de la barre des menus.
struct MenuBarView: View {
    let treadmill: TreadmillController
    let sessions: SessionStore
    let loginItem: LoginItem
    let updates: UpdateManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Foulée")
                    .font(.headline)
                Spacer()
                ConnectionLabel(treadmill: treadmill)
                    .font(.caption)
            }

            if let error = treadmill.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(treadmill.connectionLost ? .orange : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if treadmill.data != nil {
                MetricsView(treadmill: treadmill)
            }

            if case .connected = treadmill.connection {
                controls
            }

            Divider()

            SessionsView(sessions: sessions)

            Divider()

            if let version = updates.availableVersion {
                Button("Installer la mise à jour \(version)…") {
                    updates.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                Button("À propos de Foulée \(updates.currentVersion)") {
                    AboutPanel.show()
                }
                .buttonStyle(.link)
                .font(.caption)
                Spacer()
                Button("Rechercher les mises à jour…") {
                    updates.checkForUpdates()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            HStack {
                Button("Réglages…") {
                    openSettings()
                    NSApp.activate()
                }
                .keyboardShortcut(",")
                Button("Diagnostic…") {
                    openWindow(id: "diagnostic")
                    NSApp.activate()
                }
                Spacer()
                Button("Quitter Foulée") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            loginItem.refresh()
        }
    }

    @ViewBuilder private var controls: some View {
        if !treadmill.hasControl {
            Button("Prendre le contrôle du tapis") {
                Task { await treadmill.requestControl() }
            }
            .disabled(treadmill.isSendingCommand)
        } else {
            VStack(spacing: 10) {
                if treadmill.belt == .running {
                    speedButtons
                }
                beltButtons
            }
            .disabled(!treadmill.canCommand)
        }
    }

    private var speedButtons: some View {
        HStack {
            Button {
                Task { await treadmill.changeSpeed(direction: -1) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 20)
            }
            Spacer()
            VStack(spacing: 0) {
                Text("Consigne")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(treadmill.targetSpeedKmh.map { "\(Format.speed($0)) km/h" } ?? "—")
                    .monospacedDigit()
            }
            Spacer()
            Button {
                Task { await treadmill.changeSpeed(direction: 1) }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 20)
            }
        }
        .controlSize(.large)
    }

    /// Bascule entre la vitesse lente et la vitesse quittée.
    private var slowToggle: some View {
        let label =
            treadmill.speedBeforeSlowdownKmh.map { "\(Format.speed($0)) km/h" }
            ?? "\(Format.speed(treadmill.slowSpeedKmh)) km/h"
        let symbol = treadmill.speedBeforeSlowdownKmh == nil ? "tortoise.fill" : "hare.fill"
        return Button(label, systemImage: symbol) {
            Task { await treadmill.toggleSlowSpeed() }
        }
        .help(
            treadmill.speedBeforeSlowdownKmh == nil
                ? "Ralentir à la vitesse lente" : "Revenir à la vitesse quittée"
        )
    }

    private var beltButtons: some View {
        HStack {
            if treadmill.belt == .running {
                Button("Pause", systemImage: "pause.fill") {
                    Task { await treadmill.pauseBelt() }
                }
                slowToggle
            } else {
                Button(
                    treadmill.belt == .paused ? "Reprendre" : "Démarrer",
                    systemImage: "play.fill",
                ) {
                    Task { await treadmill.startBelt() }
                }
            }
            Spacer()
            Button("Arrêter", systemImage: "stop.fill", role: .destructive) {
                Task { await treadmill.stopBelt() }
            }
            .disabled(treadmill.belt == .stopped)
        }
    }
}

/// Vitesse, distance, temps et énergie reçus du tapis.
private struct MetricsView: View {
    let treadmill: TreadmillController

    var body: some View {
        let data = treadmill.data
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(data?.speedKmh.map(Format.speed) ?? "—")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("km/h")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(beltDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                metric("Distance", data?.totalDistanceMeters.map(Format.distance))
                Spacer()
                metric("Temps", data?.elapsedSeconds.map(Format.duration))
                Spacer()
                metric("Énergie", data?.totalEnergyKcal.map { "\($0) kcal" })
            }
        }
    }

    private var beltDescription: String {
        switch treadmill.belt {
        case .unknown: ""
        case .stopped: "À l'arrêt"
        case .running: "En marche"
        case .paused: "En pause"
        }
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .monospacedDigit()
        }
    }
}

/// Dossier des séances et dernière séance enregistrée.
private struct SessionsView: View {
    let sessions: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Statistiques…", systemImage: "chart.bar.xaxis") {
                openWindow(id: "statistics")
                NSApp.activate()
            }
            .font(.body)
            HStack {
                Label(sessions.folderDescription, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Ouvrir") {
                    sessions.openFolder()
                }
                .buttonStyle(.link)
                Button("Changer…") {
                    sessions.chooseFolder()
                }
                .buttonStyle(.link)
            }
            if let session = sessions.sessions.first {
                Text(
                    "Dernière séance : \(Format.distance(session.distanceMeters)) en \(Format.duration(session.elapsedSeconds)), \(session.startDate.formatted(date: .abbreviated, time: .shortened))"
                )
                .foregroundStyle(.secondary)
            }
            if let error = sessions.error {
                Text(error)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
    }
}

/// Point coloré et état de la connexion Bluetooth.
private struct ConnectionLabel: View {
    let treadmill: TreadmillController

    var body: some View {
        let (text, color): (String, Color) =
            switch treadmill.connection {
            case .bluetoothUnavailable: ("Bluetooth indisponible", .red)
            case .searching:
                treadmill.connectionLost
                    ? ("Connexion perdue", .orange) : ("Recherche du tapis…", .secondary)
            case .connecting(let name): ("Connexion à \(name)…", .secondary)
            case .connected(let name): (name, treadmill.hasControl ? .green : .orange)
            }
        Label {
            Text(text)
        } icon: {
            Circle().fill(color).frame(width: 8, height: 8)
        }
    }
}

/// Icône de la barre des menus : marcheur, avec la vitesse quand le tapis tourne.
struct MenuBarIcon: View {
    let treadmill: TreadmillController

    var body: some View {
        if treadmill.connectionLost {
            Image(systemName: "exclamationmark.triangle.fill")
        } else if treadmill.belt == .running, let speed = treadmill.data?.speedKmh {
            Text("\(Image(systemName: "figure.walk.motion")) \(Format.speed(speed))")
        } else {
            Image(systemName: "figure.walk")
        }
    }
}

/// Mise en forme des valeurs, selon la langue du système.
enum Format {
    static func speed(_ kmh: Double) -> String {
        kmh.formatted(.number.precision(.fractionLength(1)))
    }

    static func distance(_ meters: Int) -> String {
        meters < 1000
            ? "\(meters) m"
            : "\((Double(meters) / 1000).formatted(.number.precision(.fractionLength(2)))) km"
    }

    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds)
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
