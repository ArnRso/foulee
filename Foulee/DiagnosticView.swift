import FTMSKit
import SwiftUI

/// Fenêtre de diagnostic, ouverte depuis le menu : capacités du tapis, dernière trame reçue et
/// journal des commandes, à copier dans un signalement de problème.
struct DiagnosticView: View {
    let treadmill: TreadmillController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Tapis") {
                VStack(alignment: .leading, spacing: 4) {
                    row("Appareil", treadmill.deviceName ?? "non connecté")
                    row("Contrôle", treadmill.hasControl ? "obtenu" : "non obtenu")
                    row("Entraînement", treadmill.trainingStatus?.description ?? "—")
                    if let range = treadmill.speedRange {
                        row(
                            "Plage de vitesse",
                            "\(Format.speed(range.minimumKmh)) à \(Format.speed(range.maximumKmh)) km/h",
                        )
                    }
                    if let features = treadmill.features {
                        row("Réglages acceptés", features.targetSettings.joined(separator: ", "))
                    }
                    row("Dernière trame", hexString(treadmill.lastFrame))
                    if let extra = treadmill.data?.extraBytes, extra != 0 {
                        row("Écart de longueur", "\(extra) octet(s)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Journal") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(treadmill.journal.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)
                .defaultScrollAnchor(.bottom)
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)

            Button("Copier le diagnostic") {
                treadmill.copyJournal()
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
