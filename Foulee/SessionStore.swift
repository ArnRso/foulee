import AppKit
import FTMSKit
import Foundation
import Observation

/// Enregistre chaque séance dans un fichier JSON, par défaut dans iCloud Drive › Foulee, et
/// tient la liste des séances pour les statistiques.
///
/// Foulée n'est pas sandboxée : elle écrit directement dans le dossier iCloud Drive de
/// l'utilisateur, que macOS synchronise ensuite, sans conteneur iCloud ni entitlement (qui
/// exigeraient une signature par une équipe Apple, incompatible avec les builds ad hoc).
/// Dossier et fichiers ont des noms ASCII sans espace, sûrs sur tous les systèmes.
///
/// Un fichier par séance plutôt qu'une base SQLite : iCloud Drive synchronise des fichiers
/// entiers et peut corrompre une base modifiée sur place, alors qu'un fichier JSON écrit d'un
/// bloc ne risque, au pire, qu'un conflit sur une seule séance.
///
/// Pour ne pas relire tous les relevés à chaque ouverture des statistiques, les totaux de chaque
/// séance sont gardés dans un index local (dans les caches de l'app, jamais synchronisé) : seuls
/// les fichiers nouveaux ou modifiés depuis la dernière lecture sont décodés.
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
    /// Totaux des séances du dossier, de la plus récente à la plus ancienne.
    private(set) var sessions: [SessionSummary] = []
    /// Fichiers encore dans le nuage iCloud, en cours de téléchargement.
    private(set) var pendingDownloads = 0
    private(set) var isLoading = false
    private(set) var error: String?

    @ObservationIgnored private var index = SessionIndex()

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
        let file = Self.fileURL(startingAt: session.startDate, in: folder)
        sessions.removeAll { $0.id == session.id }
        guard session.isWorthKeeping else {
            try? FileManager.default.removeItem(at: file)
            index.entries[file.lastPathComponent] = nil
            index.save()
            return
        }
        guard save(session) else { return }
        let summary = session.summary
        let position = sessions.firstIndex { $0.startDate < summary.startDate } ?? sessions.endIndex
        sessions.insert(summary, at: position)
        if let entry = SessionIndex.Entry(file: file, summary: summary) {
            index.entries[file.lastPathComponent] = entry
            index.save()
        }
    }

    // MARK: - Lecture

    /// Met à jour la liste des séances, hors du fil principal : seuls les fichiers nouveaux ou
    /// modifiés depuis la dernière lecture sont décodés.
    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let folder = folder
        let useLegacyFolder = UserDefaults.standard.string(forKey: DefaultsKey.folder) == nil
        let cached =
            index.folder == folder.path(percentEncoded: false) ? index : SessionIndex.load()
        let result = await Task.detached(priority: .userInitiated) {
            if useLegacyFolder {
                Self.migrateLegacyFolder(into: folder)
            }
            return Self.readSessions(in: folder, cached: cached)
        }
        .value
        index = result.index
        sessions = result.index.entries.values.map(\.summary).sorted { $0.startDate > $1.startDate }
        pendingDownloads = result.pendingDownloads
        error =
            result.unreadable.isEmpty
            ? nil : "Fichiers illisibles : \(result.unreadable.joined(separator: ", "))"
    }

    /// Relit une séance complète (relevés compris), hors du fil principal.
    ///
    /// - Throws: si le fichier est illisible ; un fichier resté dans le nuage iCloud est mis en
    ///   téléchargement et l'erreur l'indique.
    func loadSession(_ summary: SessionSummary) async throws -> TreadmillSession {
        let file = Self.fileURL(startingAt: summary.startDate, in: folder)
        return try await Task.detached(priority: .userInitiated) {
            do {
                return try Self.decoder.decode(TreadmillSession.self, from: Data(contentsOf: file))
            } catch {
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                throw error
            }
        }
        .value
    }

    private struct ReadResult: Sendable {
        var index: SessionIndex
        var pendingDownloads = 0
        var unreadable: [String] = []
    }

    /// Parcourt le dossier en ne décodant que les fichiers nouveaux ou modifiés.
    ///
    /// Les fichiers inchangés depuis la dernière lecture gardent leur résumé en cache ; les
    /// autres sont décodés, renommés ou réécrits au format compact si besoin. Un fichier resté
    /// dans le nuage est téléchargé pour la prochaine lecture.
    private nonisolated static func readSessions(in folder: URL, cached: SessionIndex) -> ReadResult
    {
        var index = SessionIndex(folder: folder.path(percentEncoded: false))
        let cached = cached.folder == index.folder ? cached : SessionIndex()
        var result = ReadResult(index: index)
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: SessionIndex.Entry.resourceKeys,
            )) ?? []
        for file in files {
            let name = file.lastPathComponent
            // iCloud remplace un fichier non téléchargé par « .nom.json.icloud ».
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                let original = folder.appending(path: String(name.dropFirst().dropLast(7)))
                try? FileManager.default.startDownloadingUbiquitousItem(at: original)
                result.pendingDownloads += 1
                if let entry = cached.entries[original.lastPathComponent] {
                    index.entries[original.lastPathComponent] = entry
                }
                continue
            }
            guard file.pathExtension == "json" else { continue }
            if let entry = cached.entries[name], entry.matches(file) {
                index.entries[name] = entry
                continue
            }
            do {
                let session = try decoder.decode(
                    TreadmillSession.self,
                    from: Data(contentsOf: file),
                )
                let expected = fileURL(startingAt: session.startDate, in: folder)
                if expected.lastPathComponent != name
                    || session.formatVersion < TreadmillSession.formatVersion
                {
                    try write(session, in: folder)
                    if expected.lastPathComponent != name {
                        try FileManager.default.removeItem(at: file)
                    }
                }
                if let entry = SessionIndex.Entry(file: expected, summary: session.summary) {
                    index.entries[expected.lastPathComponent] = entry
                }
            } catch {
                result.unreadable.append(name)
            }
        }
        if index != cached {
            index.save()
        }
        result.index = index
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
                let session = try? decoder.decode(TreadmillSession.self, from: data)
            else { continue }
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

    /// JSON compact (sans indentation) : les relevés représentent l'essentiel du fichier.
    private nonisolated static func write(_ session: TreadmillSession, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(session)
            .write(to: fileURL(startingAt: session.startDate, in: folder), options: .atomic)
    }

    /// `session_2026-11-06_15-16-23.json`, à l'heure locale du début de la séance.
    private nonisolated static func fileURL(startingAt date: Date, in folder: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "session_\(formatter.string(from: date)).json"
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

/// Index local des séances, simple cache reconstruit s'il est absent ou illisible.
///
/// Garde le résumé de chaque fichier, avec sa date de modification et sa taille pour savoir
/// s'il a changé.
private struct SessionIndex: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        static let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]

        var modificationDate: Date
        var size: Int
        var summary: SessionSummary

        init?(file: URL, summary: SessionSummary) {
            guard let values = try? file.resourceValues(forKeys: Set(Self.resourceKeys)),
                let modificationDate = values.contentModificationDate,
                let size = values.fileSize
            else { return nil }
            self.modificationDate = modificationDate
            self.size = size
            self.summary = summary
        }

        func matches(_ file: URL) -> Bool {
            let values = try? file.resourceValues(forKeys: Set(Self.resourceKeys))
            return values?.contentModificationDate == modificationDate && values?.fileSize == size
        }
    }

    /// Dossier des séances indexé : un autre dossier repart d'un index vide.
    var folder = ""
    var entries: [String: Entry] = [:]

    private static var url: URL {
        URL.cachesDirectory.appending(path: "com.arnrso.foulee/index.json")
    }

    static func load() -> SessionIndex {
        (try? JSONDecoder().decode(SessionIndex.self, from: Data(contentsOf: url)))
            ?? SessionIndex()
    }

    func save() {
        try? FileManager.default.createDirectory(
            at: Self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
