import CoreaderKit
import SwiftUI

/// Daily highlight review, reading time and streak.
@MainActor
@Observable
final class ReviewModel {
    struct Card: Identifiable, Equatable, Sendable {
        var entry: BookEntry
        var annotation: Annotation
        var id: String { annotation.id }
    }

    var libraryRoot: URL
    var due: [Card] = []
    var all: [Card] = []
    var streak = 0
    var secondsToday: Double = 0
    var week: [(day: Date, seconds: Double)] = []

    @ObservationIgnored private var state = ReviewState(items: [:])
    @ObservationIgnored private var log = ReadingLog()
    @ObservationIgnored private var unsavedSeconds: Double = 0

    init(libraryRoot: URL) { self.libraryRoot = libraryRoot }

    func reload(app: AppModel) {
        let library = app.library, notes = app.notes, root = libraryRoot
        Task {
            struct Loaded: Sendable {
                var pairs: [Card]
                var state: ReviewState
                var log: ReadingLog
            }
            let loaded: Loaded? = try? await offMain {
                let pairs = try notes.all(in: library).map { Card(entry: $0.entry, annotation: $0.annotation) }
                return Loaded(pairs: pairs, state: ReviewStore(libraryRoot: root).load(), log: ReadingLogStore(libraryRoot: root).load())
            }
            guard let loaded else { return }
            all = loaded.pairs
            state = loaded.state
            log = loaded.log
            refreshDue()
            refreshStats()
        }
    }

    private func refreshDue() {
        // Only passages worth recalling: real highlights of some length.
        let eligible = all.filter { $0.annotation.kind == .highlight && $0.annotation.quote.count >= 24 }
        let created = Dictionary(eligible.map { ($0.id, $0.annotation.createdAt) }, uniquingKeysWith: { a, _ in a })
        let ids = ReviewScheduler().due(annotationIDs: eligible.map(\.id), createdAt: created, state: state, now: Date())
        let byID = Dictionary(eligible.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        due = ids.compactMap { byID[$0] }
    }

    private func refreshStats() {
        streak = log.streak(asOf: Date())
        secondsToday = log.secondsRead(on: Date())
        week = log.lastDays(7)
    }

    func grade(_ card: Card, _ grade: ReviewGrade) {
        ReviewScheduler().record(grade, for: card.id, in: &state, now: Date())
        due.removeAll { $0.id == card.id }
        let state = state, root = libraryRoot
        Task { try? await offMain { try ReviewStore(libraryRoot: root).save(state) } }
    }

    func recordReading(seconds: Double, bookID: String) {
        log.record(seconds: seconds, bookID: bookID, date: Date())
        refreshStats()
        unsavedSeconds += seconds
        // One write a minute is plenty; the file syncs through iCloud.
        guard unsavedSeconds >= 60 else { return }
        unsavedSeconds = 0
        let log = log, root = libraryRoot
        Task { try? await offMain { try ReadingLogStore(libraryRoot: root).save(log) } }
    }
}
