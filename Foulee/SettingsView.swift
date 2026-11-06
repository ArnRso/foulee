import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Fenêtre Réglages (⌘,) : vitesse, raccourcis clavier, séances et options générales.
struct SettingsView: View {
    @Bindable var treadmill: TreadmillController
    let sessions: SessionStore
    @Bindable var loginItem: LoginItem
    @Bindable var updates: UpdateManager

    var body: some View {
        Form {
            Section("Vitesse") {
                Stepper(
                    value: $treadmill.speedCeilingKmh,
                    in: TreadmillController.speedCeilingRange,
                    step: TreadmillController.speedCeilingStepKmh,
                ) {
                    LabeledContent(
                        "Vitesse maximale",
                        value: "\(Format.speed(treadmill.speedCeilingKmh)) km/h",
                    )
                }
                Picker("Incrément des boutons + et −", selection: $treadmill.speedStepKmh) {
                    ForEach(TreadmillController.speedStepChoices, id: \.self) { step in
                        Text("\(Format.speed(step)) km/h").tag(step)
                    }
                }
                Stepper(
                    value: $treadmill.slowSpeedKmh,
                    in: 1...treadmill.speedCeilingKmh,
                    step: 0.1,
                ) {
                    LabeledContent(
                        "Vitesse lente (bascule)",
                        value: "\(Format.speed(treadmill.slowSpeedKmh)) km/h",
                    )
                }
                Text(
                    "La vitesse maximale borne toutes les consignes envoyées par Foulée, pas celles de la télécommande."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Raccourcis clavier") {
                ForEach(ShortcutAction.allCases) { action in
                    KeyboardShortcuts.Recorder(action.title, name: action.name)
                }
                Text("Actifs dans toutes les apps, même quand le menu de Foulée est fermé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Rétablir les raccourcis par défaut") {
                    KeyboardShortcuts.reset(ShortcutAction.allCases.map(\.name))
                }
            }

            Section("Séances") {
                LabeledContent("Dossier", value: sessions.folderDescription)
                HStack {
                    Button("Ouvrir dans le Finder") {
                        sessions.openFolder()
                    }
                    Button("Changer…") {
                        sessions.chooseFolder()
                    }
                }
            }

            Section("Général") {
                Toggle("Ouvrir Foulée à la connexion", isOn: $loginItem.isEnabled)
                if loginItem.status == .requiresApproval {
                    HStack {
                        Text("À autoriser dans Réglages Système")
                            .foregroundStyle(.orange)
                        Button("Ouvrir") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .buttonStyle(.link)
                    }
                }
                if let error = loginItem.error {
                    Text(error).foregroundStyle(.red)
                }
                Toggle(
                    "Rechercher les mises à jour automatiquement",
                    isOn: $updates.checksAutomatically,
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            loginItem.refresh()
        }
    }
}
