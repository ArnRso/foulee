import AppKit
import FTMSKit
import Foundation
import Observation

/// Enregistre chaque séance dans un fichier JSON, par défaut dans iCloud Drive › Foulee, et
/// relit toutes les séances du dossier pour les statistiques.
///
/// Foulée n'est pas sandboxée : elle écrit directement dans le dossier iCloud Drive de
/// l'utilisateur, que macOS synchronise ensuite, sans conteneur iCloud ni entitlement (qui
/// exigeraient une signature par une équipe Apple, incompatible avec les builds ad hoc).
/// Dossier et fichiers ont des noms ASCII sans espace, sûrs sur tous les systèmes.
@MainActor
@Observable
final class SessionStore {
    private enum DefaultsKey {
        static let folder = "dossierSeances"
    }

    /// Ancien dossier par défaut (nom accentué), dont les séances sont reprises au lancement.
    private nonisolated static let legacyFolderName = "Foulée"
    private nonisolated static let folderName = "Foulee"

    private(set) var folder: URL
    /// Séances du dossier, de la plus récente à la plus ancienne.
    private(set) var sessions: [TreadmillSession] = []
    /// Fichiers encore dans le nuage iCloud, en cours de téléchargement.
    private(set) var pendingDownloads = 0
    private(set) var isLoading = false
    private(set) var error: String?

    init() {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.folder)
        folder =
            stored.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? Self.defaultBase.appending(path: Self.folderName, directoryHint: .isDirectory)
    }

    /// iCloud Drive si iCloud Drive est activé, sinon Documents.
    private static var defaultBase: URL {
        let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser.appending(
            path: "Library/Mobile Documents/com~apple~CloudDocs",
            directoryHint: .isDirectory,
        )
        return FileManager.default.fileExists(atPath: iCloudDrive.path(percentEncoded: false))
            ? iCloudDrive : URL.documentsDirectory
    }

    /// Emplacement lisible, par exemple « iCloud Drive › Foulee ».
    var folderDescription: String {
        let path = folder.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let iCloudDrive = home + "Library/Mobile Documents/com~apple~CloudDocs/"
        if path.hasPrefix(iCloudDrive) {
            return (["iCloud Drive"] + path.dropFirst(iCloudDrive.count).split(separator: "/"))
                .joined(separator: " › ")
        }
        return path.hasPrefix(home) ? "~/" + path.dropFirst(home.count) : path
    }

    // MARK: - Écriture

    /// Écrit la séance, en remplaçant la version précédente du même fichier.
    @discardableResult
    func save(_ session: TreadmillSession) -> Bool {
        do {
            try Self.write(session, in: folder)
            error = nil
            return true
        } catch {
            self.error = "Séance non enregistrée : \(error.localizedDescription)"
            return false
        }
    }

    /// Séance terminée : enregistrée si elle vaut la peine, sinon sa sauvegarde intermédiaire
    /// éventuelle est supprimée.
    func store(_ session: TreadmillSession) {
        guard session.isWorthKeeping else {
            try? FileManager.default.removeItem(at: Self.fileURL(for: session, in: folder))
            sessions.removeAll { $0.id == session.id }
            return
        }
        guard save(session) else { return }
        sessions.removeAll { $0.id == session.id }
        let index = sessions.firstIndex { $0.startDate < session.startDate } ?? sessions.endIndex
        sessions.insert(session, at: index)
    }

    // MARK: - Lecture

    /// Relit toutes les séances du dossier, hors du fil principal.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let folder = folder
        let useLegacyFolder = UserDefaults.standard.string(forKey: DefaultsKey.folder) == nil
        let result = await Task.detached(priority: .userInitiated) {
            if useLegacyFolder {
                Self.migrateLegacyFolder(into: folder)
            }
            return Self.readSessions(in: folder)
        }
        .value
        sessions = result.sessions
        pendingDownloads = result.pendingDownloads
        error =
            result.unreadable.isEmpty
            ? nil : "Fichiers illisibles : \(result.unreadable.joined(separator: ", "))"
    }

    private struct ReadResult: Sendable {
        var sessions: [TreadmillSession] = []
        var pendingDownloads = 0
        var unreadable: [String] = []
    }

    /// Lit les fichiers JSON du dossier ; un fichier mal nommé (ancienne version de Foulée)
    /// est renommé, un fichier resté dans le nuage est téléchargé pour la prochaine lecture.
    private nonisolated static func readSessions(in folder: URL) -> ReadResult {
        var result = ReadResult()
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
            )) ?? []
        for file in files {
            let name = file.lastPathComponent
            // iCloud remplace un fichier non téléchargé par « .nom.json.icloud ».
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let original = folder.appending(path: String(name.dropFirst().dropLast(7)))
                try? FileManager.default.startDownloadingUbiquitousItem(at: original)
                result.pendingDownloads += 1
                continue
            }
            guard file.pathExtension == "json" else { continue }
            do {
                var session = try decoder.decode(
                    TreadmillSession.self,
                    from: Data(contentsOf: file),
                )
                if name != fileURL(for: session, in: folder).lastPathComponent {
                    session.formatVersion = TreadmillSession.formatVersion
                    try write(session, in: folder)
                    try FileManager.default.removeItem(at: file)
                }
                result.sessions.append(session)
            } catch {
                result.unreadable.append(name)
            }
        }
        result.sessions.sort { $0.startDate > $1.startDate }
        return result
    }

    /// Reprend les séances de l'ancien dossier par défaut « Foulée », puis le supprime s'il est vide.
    private nonisolated static func migrateLegacyFolder(into folder: URL) {
        let legacy = folder.deletingLastPathComponent().appending(
            path: legacyFolderName,
            directoryHint: .isDirectory,
        )
        guard legacy.standardizedFileURL != folder.standardizedFileURL,
            let files = try? FileManager.default.contentsOfDirectory(
                at: legacy,
                includingPropertiesForKeys: nil,
            )
        else { return }
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                var session = try? decoder.decode(TreadmillSession.self, from: data)
            else { continue }
            session.formatVersion = TreadmillSession.formatVersion
            if (try? write(session, in: folder)) != nil {
                try? FileManager.default.removeItem(at: file)
            }
        }
        if (try? FileManager.default.contentsOfDirectory(atPath: legacy.path(percentEncoded: false)))?
            .filter({ !$0.hasPrefix(".") }).isEmpty == true
        {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    // MARK: - Fichiers

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private nonisolated static func write(_ session: TreadmillSession, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(session).write(to: fileURL(for: session, in: folder), options: .atomic)
    }

    /// `session_2026-11-06_15-16-23.json`, à l'heure locale du début de la séance.
    private nonisolated static func fileURL(for session: TreadmillSession, in folder: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "session_\(formatter.string(from: session.startDate)).json"
        return folder.appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: - Dossier

    func chooseFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Choisir"
        panel.message = "Dossier où Foulée enregistre les séances"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: DefaultsKey.folder)
        Task { await reload() }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
