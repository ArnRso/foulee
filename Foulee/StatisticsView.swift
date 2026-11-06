import Charts
import FTMSKit
import Foundation
import SwiftUI

/// Fenêtre Statistiques : vue d'ensemble par jour, semaine ou mois, et détail de chaque séance,
/// y compris celle en cours, mise à jour à chaque relevé du tapis.
struct StatisticsView: View {
    let store: SessionStore
    let treadmill: TreadmillController
    @State private var selection: Selection? = .overview

    enum Selection: Hashable {
        case overview
        case session(UUID)
    }

    /// Séances enregistrées, sans la sauvegarde intermédiaire de la séance en cours (même
    /// identifiant), remplacée par sa version en direct.
    private var savedSessions: [TreadmillSession] {
        guard let live = treadmill.liveSession else { return store.sessions }
        return store.sessions.filter { $0.id != live.id }
    }

    private var allSessions: [TreadmillSession] {
        (treadmill.liveSession.map { [$0] } ?? []) + savedSessions
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Vue d'ensemble", systemImage: "chart.bar.xaxis")
                    .tag(Selection.overview)
                if let live = treadmill.liveSession {
                    Section("En cours") {
                        SessionRow(session: live, isLive: true)
                            .tag(Selection.session(live.id))
                    }
                }
                Section("Séances") {
                    ForEach(savedSessions) { session in
                        SessionRow(session: session, isLive: false)
                            .tag(Selection.session(session.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                footer
            }
        } detail: {
            switch selection {
            case .session(let id):
                // Une séance qui se termine garde son identifiant : la vue passe sans saut
                // de la version en direct à la version enregistrée.
                if let session = allSessions.first(where: { $0.id == id }) {
                    SessionDetailView(
                        session: session,
                        isLive: session.id == treadmill.liveSession?.id,
                    )
                } else {
                    ContentUnavailableView("Séance introuvable", systemImage: "questionmark")
                }
            case .overview, nil:
                OverviewView(sessions: allSessions)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await store.reload()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            if store.pendingDownloads > 0 {
                Text("\(store.pendingDownloads) séance(s) en cours de téléchargement depuis iCloud")
            }
            if let error = store.error {
                Text(error).foregroundStyle(.red)
            }
            Button("Actualiser") {
                Task { await store.reload() }
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SessionRow: View {
    let session: TreadmillSession
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                if isLive {
                    LiveBadge()
                }
            }
            Text(
                "\(Format.distance(session.distanceMeters)) · \(Format.duration(session.elapsedSeconds))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

/// Pastille « En cours » des séances suivies en direct.
private struct LiveBadge: View {
    var body: some View {
        Text("En cours")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.red, in: .capsule)
    }
}

// MARK: - Vue d'ensemble

private enum Metric: String, CaseIterable, Identifiable {
    case distance = "Distance"
    case duration = "Temps"
    case energy = "Énergie"
    case sessions = "Séances"

    var id: Self {
        self
    }

    var unit: String {
        switch self {
        case .distance: "km"
        case .duration: "min"
        case .energy: "kcal"
        case .sessions: "séances"
        }
    }

    func value(of summary: PeriodSummary) -> Double {
        switch self {
        case .distance: Double(summary.distanceMeters) / 1000
        case .duration: Double(summary.elapsedSeconds) / 60
        case .energy: Double(summary.energyKcal)
        case .sessions: Double(summary.sessionCount)
        }
    }
}

extension StatisticsPeriod {
    fileprivate var title: String {
        switch self {
        case .day: "Jour"
        case .week: "Semaine"
        case .month: "Mois"
        }
    }

    /// Nombre de périodes affichées dans le graphique.
    fileprivate var chartCount: Int {
        switch self {
        case .day: 30
        case .week: 12
        case .month: 12
        }
    }

    fileprivate var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    fileprivate func label(for date: Date) -> String {
        switch self {
        case .day: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week: "Semaine du \(date.formatted(.dateTime.day().month(.abbreviated)))"
        case .month: date.formatted(.dateTime.month(.wide).year())
        }
    }
}

private struct OverviewView: View {
    let sessions: [TreadmillSession]
    @State private var period = StatisticsPeriod.day
    @State private var metric = Metric.distance

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let summaries = SessionStatistics.summaries(
            of: sessions,
            by: period,
            count: period.chartCount,
            endingAt: now,
            calendar: calendar,
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    tile("Aujourd'hui", current(.day, calendar: calendar, now: now))
                    tile("Cette semaine", current(.week, calendar: calendar, now: now))
                    tile("Ce mois", current(.month, calendar: calendar, now: now))
                    tile("Depuis le début", SessionStatistics.total(of: sessions))
                }

                HStack {
                    Picker("Période", selection: $period) {
                        ForEach(StatisticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer()
                    Picker("Mesure", selection: $metric) {
                        ForEach(Metric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .fixedSize()
                }

                Chart(summaries) { summary in
                    BarMark(
                        x: .value("Période", summary.start, unit: period.calendarComponent),
                        y: .value(metric.rawValue, metric.value(of: summary)),
                    )
                    .foregroundStyle(.teal.gradient)
                }
                .chartYAxisLabel(metric.unit)
                .frame(height: 260)

                PeriodTable(
                    period: period,
                    summaries: summaries.filter { $0.sessionCount > 0 }.reversed(),
                )
            }
            .padding(20)
        }
        .navigationTitle("Statistiques")
    }

    private func current(_ period: StatisticsPeriod, calendar: Calendar, now: Date)
        -> PeriodSummary
    {
        SessionStatistics.summaries(
            of: sessions,
            by: period,
            count: 1,
            endingAt: now,
            calendar: calendar,
        )
        .first ?? PeriodSummary(start: now)
    }

    private func tile(_ title: String, _ summary: PeriodSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.distance(summary.distanceMeters))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(
                "\(Format.duration(summary.elapsedSeconds)) · \(summary.sessionCount) séance(s)"
            )
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

/// Totaux détaillés de chaque période qui compte au moins une séance.
private struct PeriodTable: View {
    let period: StatisticsPeriod
    let summaries: [PeriodSummary]

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text(period.title).gridColumnAlignment(.leading)
                Text("Séances")
                Text("Distance")
                Text("Temps")
                Text("Énergie")
                Text("Vitesse moy.")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(summaries) { summary in
                GridRow {
                    Text(period.label(for: summary.start))
                    Text("\(summary.sessionCount)")
                    Text(Format.distance(summary.distanceMeters))
                    Text(Format.duration(summary.elapsedSeconds))
                    Text("\(summary.energyKcal) kcal")
                    Text("\(Format.speed(summary.averageSpeedKmh)) km/h")
                }
                .monospacedDigit()
            }
        }
    }
}

// MARK: - Détail d'une séance

/// Ligne de la chronologie : changement de vitesse lu dans les relevés, ou événement.
private struct TimelineEntry: Identifiable {
    let id: Int
    let offsetSeconds: Double
    let symbol: String
    let text: String
    let color: Color
}

private struct SessionDetailView: View {
    let session: TreadmillSession
    let isLive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(session.startDate.formatted(date: .complete, time: .shortened))
                        .font(.title2.weight(.semibold))
                    if isLive {
                        LiveBadge()
                    }
                }
                if session.isInterrupted {
                    Label(
                        "Séance interrompue (fermeture de Foulée) : totaux au dernier relevé reçu",
                        systemImage: "exclamationmark.triangle",
                    )
                    .foregroundStyle(.orange)
                }

                HStack(spacing: 24) {
                    figure("Distance", Format.distance(session.distanceMeters))
                    figure("Temps de marche", Format.duration(session.elapsedSeconds))
                    figure("Énergie", session.energyKcal.map { "\($0) kcal" } ?? "—")
                    figure("Vitesse moyenne", "\(Format.speed(session.averageSpeedKmh)) km/h")
                    figure("Vitesse max.", "\(Format.speed(session.maximumSpeedKmh)) km/h")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Vitesse").font(.headline)
                    speedChart
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chronologie").font(.headline)
                    timeline
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Séance")
    }

    private func date(at offset: Double) -> Date {
        session.startDate.addingTimeInterval(offset)
    }

    private var speedChart: some View {
        Chart {
            ForEach(Array(session.samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("Heure", date(at: sample.offsetSeconds)),
                    y: .value("Vitesse", sample.speedKmh),
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(.teal)
            }
            ForEach(Array(session.events.enumerated()), id: \.offset) { _, event in
                RuleMark(x: .value("Heure", date(at: event.offsetSeconds)))
                    .foregroundStyle(Self.color(for: event.kind).opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYAxisLabel("km/h")
        .frame(height: 240)
    }

    private var timeline: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Heure")
                Text("Écoulé")
                Text("")
                Text("Événement")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(entries) { entry in
                GridRow {
                    Text(date(at: entry.offsetSeconds).formatted(date: .omitted, time: .standard))
                    Text(Format.duration(Int(entry.offsetSeconds)))
                        .foregroundStyle(.secondary)
                    Image(systemName: entry.symbol)
                        .foregroundStyle(entry.color)
                    Text(entry.text)
                }
                .monospacedDigit()
            }
        }
    }

    private var entries: [TimelineEntry] {
        let changes = session.speedChanges.map { change in
            let delta = change.deltaKmh
            let text =
                change.toKmh == 0
                ? "Bande arrêtée (\(Format.speed(change.fromKmh)) → 0 km/h)"
                : "\(Format.speed(change.fromKmh)) → \(Format.speed(change.toKmh)) km/h (\(delta > 0 ? "+" : "")\(Format.speed(delta)))"
            return (
                change.offsetSeconds,
                delta > 0 ? "arrow.up.right" : "arrow.down.right",
                text,
                delta > 0 ? Color.green : Color.orange,
            )
        }
        let events = session.events.map { event in
            (
                event.offsetSeconds,
                Self.symbol(for: event.kind),
                Self.description(of: event),
                Self.color(for: event.kind),
            )
        }
        return (changes + events)
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { index, entry in
                TimelineEntry(
                    id: index,
                    offsetSeconds: entry.0,
                    symbol: entry.1,
                    text: entry.2,
                    color: entry.3,
                )
            }
    }

    private static func symbol(for kind: TreadmillSession.Event.Kind) -> String {
        switch kind {
        case .started: "play.fill"
        case .paused: "pause.fill"
        case .stopped: "stop.fill"
        case .targetSpeed: "speedometer"
        case .connectionLost: "antenna.radiowaves.left.and.right.slash"
        case .reconnected: "antenna.radiowaves.left.and.right"
        }
    }

    private static func color(for kind: TreadmillSession.Event.Kind) -> Color {
        switch kind {
        case .started, .reconnected: .green
        case .paused, .targetSpeed: .blue
        case .stopped, .connectionLost: .red
        }
    }

    private static func description(of event: TreadmillSession.Event) -> String {
        switch event.kind {
        case .started: "Démarrage ou reprise"
        case .paused: "Pause"
        case .stopped: "Arrêt"
        case .targetSpeed: "Consigne Foulée : \(event.speedKmh.map(Format.speed) ?? "?") km/h"
        case .connectionLost: "Connexion perdue"
        case .reconnected: "Connexion retrouvée"
        }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }
}
