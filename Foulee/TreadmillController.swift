import AppKit
import CoreBluetooth
import FTMSKit
import Foundation
import Observation
import os

/// Connexion Bluetooth au tapis et pilotage par le protocole FTMS.
///
/// Cherche en continu un appareil annonçant le service Fitness Machine (`0x1826`), s'y connecte,
/// s'abonne aux données et demande le contrôle. Les commandes passent une par une sur le Control
/// Point, chacune attendant la réponse du tapis. Toute consigne de vitesse est bornée par
/// ``SpeedPolicy`` (plage du tapis et plafond choisi par l'utilisateur).
@MainActor
@Observable
final class TreadmillController: NSObject {
    enum ConnectionState: Equatable {
        case bluetoothUnavailable(String)
        case searching
        case connecting(name: String)
        case connected(name: String)
    }

    enum BeltState: Equatable {
        case unknown
        case stopped
        case running
        case paused
    }

    private enum DefaultsKey {
        static let speedCeiling = "plafondVitesse"
        static let speedStep = "incrementVitesse"
        static let slowSpeed = "vitesseLente"
    }

    static let defaultSpeedCeilingKmh = 4.0
    static let speedCeilingRange = 1.0...12.0
    static let speedCeilingStepKmh = 0.5
    static let speedStepChoices = [0.1, 0.2, 0.5, 1.0]
    static let defaultSlowSpeedKmh = 1.0
    /// Nombre de relevés (environ un par seconde) entre deux sauvegardes de la séance en cours.
    private static let checkpointInterval = 30
    private static let commandTimeout = Duration.seconds(3)
    private static let journalLimit = 300

    private(set) var connection = ConnectionState.searching
    /// Connexion perdue sans l'avoir demandé : le tapis continue de tourner à sa dernière vitesse.
    private(set) var connectionLost = false
    private(set) var belt = BeltState.unknown
    private(set) var hasControl = false
    private(set) var isSendingCommand = false
    private(set) var data: TreadmillData?
    private(set) var lastFrame: [UInt8] = []
    private(set) var targetSpeedKmh: Double?
    private(set) var speedRange: SpeedRange?
    private(set) var features: MachineFeatures?
    private(set) var trainingStatus: TrainingStatus?
    private(set) var lastError: String?
    private(set) var journal: [String] = []
    /// Vitesse quittée par la bascule lente, rétablie à la bascule suivante.
    private(set) var speedBeforeSlowdownKmh: Double?

    /// Plafond de vitesse choisi par l'utilisateur, en plus de la plage annoncée par le tapis.
    var speedCeilingKmh = TreadmillController.stored(
        DefaultsKey.speedCeiling,
        in: speedCeilingRange,
        default: defaultSpeedCeilingKmh,
    ) {
        didSet {
            UserDefaults.standard.set(speedCeilingKmh, forKey: DefaultsKey.speedCeiling)
        }
    }

    /// Incrément des boutons + et −, parmi ``speedStepChoices``.
    var speedStepKmh = TreadmillController.stored(
        DefaultsKey.speedStep,
        in: 0.1...1.0,
        default: 0.1,
    ) {
        didSet {
            UserDefaults.standard.set(speedStepKmh, forKey: DefaultsKey.speedStep)
        }
    }

    /// Vitesse de la bascule lente.
    var slowSpeedKmh = TreadmillController.stored(
        DefaultsKey.slowSpeed,
        in: speedCeilingRange,
        default: defaultSlowSpeedKmh,
    ) {
        didSet {
            UserDefaults.standard.set(slowSpeedKmh, forKey: DefaultsKey.slowSpeed)
        }
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var controlPoint: CBCharacteristic?
    @ObservationIgnored private var pending: PendingCommand?
    @ObservationIgnored private var commandChain: Task<Void, Never>?
    @ObservationIgnored private var isQuitting = false
    /// Observé : la fenêtre Statistiques affiche la séance en cours à chaque relevé.
    private var recorder = SessionRecorder()
    @ObservationIgnored private let sessions: SessionStore
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.arnrso.foulee",
        category: "tapis",
    )

    private struct PendingCommand {
        let opCode: UInt8
        let continuation: CheckedContinuation<ControlPointResponse?, Never>
        let timeout: Task<Void, Never>
    }

    var policy: SpeedPolicy? {
        speedRange.map {
            SpeedPolicy(range: $0, ceilingKmh: speedCeilingKmh, preferredStepKmh: speedStepKmh)
        }
    }

    var deviceName: String? {
        switch connection {
        case .connecting(let name), .connected(let name): name
        case .bluetoothUnavailable, .searching: nil
        }
    }

    /// Séance en cours, mise à jour à chaque relevé du tapis.
    var liveSession: TreadmillSession? {
        recorder.current
    }

    /// Les commandes sont possibles : connecté, contrôle obtenu, aucune commande en cours.
    var canCommand: Bool {
        hasControl && !isSendingCommand && policy != nil
    }

    init(sessions: SessionStore) {
        self.sessions = sessions
    }

    /// À appeler une fois au lancement : macOS demande alors l'autorisation Bluetooth.
    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Commandes

    func startBelt() async {
        await send(.startOrResume)
    }

    func pauseBelt() async {
        await send(.pause)
    }

    func stopBelt() async {
        await send(.stop)
    }

    /// Pause si la bande tourne, sinon démarrage ou reprise.
    func togglePause() async {
        await (belt == .running ? pauseBelt() : startBelt())
    }

    /// Passe à la vitesse lente, ou revient à la vitesse quittée si le tapis y est encore.
    func toggleSlowSpeed() async {
        guard let policy, belt == .running else { return }
        let current = targetSpeedKmh ?? data?.speedKmh ?? policy.range.minimumKmh
        let slow = policy.clamped(slowSpeedKmh)
        if let previous = speedBeforeSlowdownKmh, abs(current - slow) < 0.05 {
            speedBeforeSlowdownKmh = nil
            await setSpeed(previous)
        } else if abs(current - slow) >= 0.05 {
            speedBeforeSlowdownKmh = current
            await setSpeed(slow)
        }
    }

    /// Boutons + (`direction` = 1) et − (`direction` = -1).
    func changeSpeed(direction: Int) async {
        guard let policy else { return }
        let base = targetSpeedKmh ?? data?.speedKmh ?? policy.range.minimumKmh
        await setSpeed(policy.stepped(from: base, direction: direction))
    }

    func setSpeed(_ kmh: Double) async {
        guard let policy else { return }
        let safe = policy.clamped(kmh)
        if safe != kmh {
            record("Consigne \(kmh) km/h ramenée à \(safe) km/h")
        }
        if await send(.setTargetSpeed(kmh: safe)) == .success {
            targetSpeedKmh = safe
            recorder.note(.targetSpeed, speedKmh: safe, at: .now)
        }
    }

    func requestControl() async {
        hasControl = await send(.requestControl) == .success
        if !hasControl {
            lastError = "Le tapis a refusé le contrôle : fermez l'appli FitShow et réessayez."
        }
    }

    /// Sécurité à la fermeture : Stop si le tapis tourne, puis déconnexion propre.
    func prepareForQuit() async {
        isQuitting = true
        if hasControl, belt != .stopped {
            record("Arrêt du tapis avant de quitter")
            await send(.stop)
        }
        if let session = recorder.finish(interrupted: true) {
            store(session)
        }
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    func copyJournal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticReport(), forType: .string)
    }

    func diagnosticReport() -> String {
        var lines = [
            "Foulée \(Bundle.main.shortVersion) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Tapis : \(deviceName ?? "non connecté")",
            "Contrôle : \(hasControl ? "obtenu" : "non obtenu")",
        ]
        if let features {
            lines.append("Mesures : \(features.measurements.joined(separator: ", "))")
            lines.append("Réglages : \(features.targetSettings.joined(separator: ", "))")
        }
        if let speedRange {
            lines.append(
                "Vitesse : \(speedRange.minimumKmh) à \(speedRange.maximumKmh) km/h, pas \(speedRange.incrementKmh)"
            )
        }
        lines.append("Dernière trame 0x2ACD : \(hexString(lastFrame))")
        lines.append("")
        return (lines + journal).joined(separator: "\n")
    }

    // MARK: - Control Point

    /// Envoie les commandes une par une : chacune attend la réponse de la précédente.
    @discardableResult
    private func send(_ command: ControlPointCommand) async -> ControlPointResult? {
        let previous = commandChain
        let task = Task { () -> ControlPointResult? in
            await previous?.value
            return await self.transmit(command)
        }
        commandChain = Task { _ = await task.value }
        return await task.value
    }

    private func transmit(_ command: ControlPointCommand) async -> ControlPointResult? {
        let name = ControlPointCommand.name(ofOpCode: command.opCode)
        guard let peripheral, let controlPoint else {
            record("\(name) impossible : tapis non connecté")
            return nil
        }
        isSendingCommand = true
        defer { isSendingCommand = false }
        record("→ \(hexString(command.bytes))  (\(name))")
        let response = await withCheckedContinuation { continuation in
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.commandTimeout)
                self?.resolvePending(with: nil)
            }
            pending = PendingCommand(
                opCode: command.opCode,
                continuation: continuation,
                timeout: timeout,
            )
            peripheral.writeValue(Data(command.bytes), for: controlPoint, type: .withResponse)
        }
        guard let response else {
            record("   pas de réponse à \(name)")
            lastError = "Le tapis ne répond pas à \(name)."
            return nil
        }
        if response.result != .success {
            lastError = response.description
        }
        return response.result
    }

    private func resolvePending(with response: ControlPointResponse?) {
        guard let pending else { return }
        self.pending = nil
        pending.timeout.cancel()
        pending.continuation.resume(returning: response)
    }

    // MARK: - Trames reçues

    private func received(_ bytes: [UInt8], from uuid: CBUUID) {
        do {
            switch uuid {
            case GATT.treadmillData:
                let decoded = try TreadmillData(decoding: bytes)
                data = decoded
                lastFrame = bytes
                if belt == .unknown, let speed = decoded.speedKmh {
                    belt = speed > 0 ? .running : .stopped
                }
                if let finished = recorder.record(decoded, at: .now, deviceName: deviceName) {
                    store(finished)
                }
                // Sauvegarde intermédiaire : une séance interrompue par un plantage n'est pas perdue.
                if let current = recorder.current,
                    current.samples.count.isMultiple(of: Self.checkpointInterval)
                {
                    sessions.save(current)
                }
            case GATT.controlPoint:
                let response = try ControlPointResponse(decoding: bytes)
                record("← \(hexString(bytes))  (\(response.description))")
                if response.requestOpCode == pending?.opCode {
                    resolvePending(with: response)
                }
            case GATT.machineStatus:
                handle(try MachineStatus(decoding: bytes), raw: bytes)
            case GATT.trainingStatus:
                let status = try TrainingStatus(decoding: bytes)
                trainingStatus = status
                record("État d'entraînement : \(status.description)  [\(hexString(bytes))]")
            case GATT.feature:
                let decoded = try MachineFeatures(decoding: bytes)
                features = decoded
                record("Mesures fournies : \(decoded.measurements.joined(separator: ", "))")
                record("Réglages acceptés : \(decoded.targetSettings.joined(separator: ", "))")
            case GATT.speedRange:
                let range = try SpeedRange(decoding: bytes)
                speedRange = range
                record(
                    "Plage de vitesse : \(range.minimumKmh) à \(range.maximumKmh) km/h, pas \(range.incrementKmh)"
                )
            default:
                break
            }
        } catch {
            record("Trame illisible de \(uuid) : \(hexString(bytes)) (\(error))")
        }
    }

    private func handle(_ status: MachineStatus, raw: [UInt8]) {
        record("Statut du tapis : \(status.description)  [\(hexString(raw))]")
        if let finished = recorder.record(status, at: .now) {
            store(finished)
        }
        if status.resetsTargetSpeed {
            targetSpeedKmh = nil
            speedBeforeSlowdownKmh = nil
        }
        switch status {
        case .startedOrResumedByUser: belt = .running
        case .pausedByUser: belt = .paused
        case .stoppedByUser, .stoppedBySafetyKey, .reset: belt = .stopped
        case .targetSpeedChanged(let kmh): targetSpeedKmh = kmh
        case .controlPermissionLost: hasControl = false
        case .targetInclinationChanged, .other: break
        }
    }

    private func store(_ session: TreadmillSession) {
        sessions.store(session)
        let summary =
            "\(Format.distance(session.distanceMeters)) en \(Format.duration(session.elapsedSeconds))"
        if !session.isWorthKeeping {
            record("Séance trop courte, non enregistrée (\(summary))")
        } else if let error = sessions.error {
            record(error)
        } else {
            record("Séance enregistrée : \(summary)")
        }
    }

    private func record(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let time = Date.now.formatted(.dateTime.hour().minute().second())
        journal.append("\(time)  \(message)")
        if journal.count > Self.journalLimit {
            journal.removeFirst(journal.count - Self.journalLimit)
        }
    }

    // MARK: - Connexion

    private func scan() {
        guard let central, central.state == .poweredOn, !isQuitting else { return }
        connection = .searching
        central.scanForPeripherals(withServices: [GATT.fitnessMachine])
    }

    private func resetSession() {
        resolvePending(with: nil)
        peripheral = nil
        controlPoint = nil
        hasControl = false
        targetSpeedKmh = nil
        data = nil
        belt = .unknown
    }

    private static func stored(
        _ key: String,
        in range: ClosedRange<Double>,
        default value: Double,
    ) -> Double {
        let stored = UserDefaults.standard.double(forKey: key)
        return range.contains(stored) ? stored : value
    }
}

/// Identifiants Bluetooth du service FTMS et de ses caractéristiques.
@MainActor
private enum GATT {
    static let fitnessMachine = CBUUID(string: "1826")
    static let feature = CBUUID(string: "2ACC")
    static let treadmillData = CBUUID(string: "2ACD")
    static let trainingStatus = CBUUID(string: "2AD3")
    static let speedRange = CBUUID(string: "2AD4")
    static let controlPoint = CBUUID(string: "2AD9")
    static let machineStatus = CBUUID(string: "2ADA")

    static let notified = [treadmillData, trainingStatus, machineStatus, controlPoint]
    static let read = [feature, speedRange, trainingStatus]
}

// Le gestionnaire Bluetooth est créé sur la file principale : ses rappels arrivent sur le
// thread principal, ce que vérifie la conformité @preconcurrency.
extension TreadmillController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            scan()
        case .unauthorized:
            connection = .bluetoothUnavailable(
                "Autorisez Foulée dans Réglages Système › Confidentialité et sécurité › Bluetooth."
            )
        case .poweredOff:
            connection = .bluetoothUnavailable("Le Bluetooth du Mac est désactivé.")
        case .unsupported:
            connection = .bluetoothUnavailable("Ce Mac ne prend pas en charge le Bluetooth LE.")
        case .resetting, .unknown:
            connection = .searching
        @unknown default:
            connection = .bluetoothUnavailable("État Bluetooth inattendu.")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi signalStrength: NSNumber,
    ) {
        guard self.peripheral == nil else { return }
        central.stopScan()
        let name = peripheral.name ?? "tapis"
        record("Tapis trouvé : \(name) (\(signalStrength) dBm)")
        self.peripheral = peripheral
        peripheral.delegate = self
        connection = .connecting(name: name)
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        record("Connecté")
        connection = .connected(name: peripheral.name ?? "tapis")
        if connectionLost {
            recorder.note(.reconnected, at: .now)
        }
        connectionLost = false
        lastError = nil
        peripheral.discoverServices([GATT.fitnessMachine])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?,
    ) {
        record("Échec de connexion : \(error?.localizedDescription ?? "raison inconnue")")
        resetSession()
        scan()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: (any Error)?,
    ) {
        if isQuitting {
            record("Déconnecté")
            return
        }
        let wasRunning = belt == .running
        record("CONNEXION PERDUE : \(error?.localizedDescription ?? "sans raison donnée")")
        connectionLost = true
        lastError =
            wasRunning
            ? "Connexion perdue : le tapis continue de tourner. Arrêtez-le à la télécommande."
            : "Connexion perdue avec le tapis."
        if wasRunning {
            NSSound.beep()
        }
        // La séance continue si le tapis est retrouvé ; en attendant, elle est mise à l'abri.
        recorder.note(.connectionLost, at: .now)
        if let current = recorder.current {
            sessions.save(current)
        }
        resetSession()
        scan()
    }
}

extension TreadmillController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] where service.uuid == GATT.fitnessMachine {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?,
    ) {
        for characteristic in service.characteristics ?? [] {
            if GATT.read.contains(characteristic.uuid) {
                peripheral.readValue(for: characteristic)
            }
            if characteristic.uuid == GATT.controlPoint {
                controlPoint = characteristic
            }
            // S'abonner aux indications du Control Point est obligatoire avant d'y écrire.
            if GATT.notified.contains(characteristic.uuid) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?,
    ) {
        if let error {
            record("Abonnement impossible à \(characteristic.uuid) : \(error.localizedDescription)")
            return
        }
        if characteristic.uuid == GATT.controlPoint, characteristic.isNotifying {
            Task { await requestControl() }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?,
    ) {
        guard error == nil, let value = characteristic.value else { return }
        received(Array(value), from: characteristic.uuid)
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
