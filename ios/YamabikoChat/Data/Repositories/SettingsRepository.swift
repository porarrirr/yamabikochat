import Foundation
import Combine
import GRDB

final class SettingsRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func load() throws -> AppSettings {
        try dbQueue.write { db in
            if let settings = try AppSettings.fetchOne(db, key: 1) {
                var normalized = settings.normalizedForPersistence()
                if normalized != settings { try normalized.save(db) }
                return normalized
            }
            var initial = AppSettings()
            try initial.insert(db)
            return initial.normalizedForPersistence()
        }
    }

    func save(_ settings: AppSettings) throws {
        try dbQueue.write { db in
            var mutable = settings.normalizedForPersistence()
            try mutable.save(db)
        }
    }

    func observe() -> AnyPublisher<AppSettings, Never> {
        ValueObservation.tracking { db in
            try AppSettings.fetchOne(db)
        }
            .publisher(in: dbQueue)
            .replaceError(with: nil)
            .map { ($0 ?? AppSettings()).normalizedForPersistence() }
            .eraseToAnyPublisher()
    }
}
