import Foundation
import SwiftData

@MainActor
final class SwiftDataEventStore: EventStoreService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func save(_ event: BabyEvent) {
        modelContext.insert(event)
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save BabyEvent: \(error)")
        }
    }

    func recentEvents(limit: Int) -> [BabyEvent] {
        var descriptor = FetchDescriptor<BabyEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            assertionFailure("Failed to fetch BabyEvent: \(error)")
            return []
        }
    }
}
