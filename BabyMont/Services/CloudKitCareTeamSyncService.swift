import CloudKit
import Foundation

@MainActor
final class CloudKitCareTeamSyncService: CloudSyncServicing {
    private let container: CKContainer
    private let database: CKDatabase
    private let babyId: UUID
    private(set) var network: CareNetwork?
    private(set) var recentCloudEvents: [BabyEvent] = []
    private(set) var isAvailable = false

    init(
        containerIdentifier: String = "iCloud.wcs.BabyMont",
        babyId: UUID = UUID(uuidString: "8FD073F6-E04B-47D8-B93D-BABF00000001") ?? UUID()
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.babyId = babyId
    }

    func configure() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = status == .available
            guard isAvailable else { return }
            try await fetchOrCreateNetwork()
        } catch {
            isAvailable = false
        }
    }

    func updateDeviceToken(_ token: String?) async {
        guard isAvailable, let token else { return }
        do {
            var network = self.network ?? CareNetwork(babyId: babyId)
            if let index = network.caregivers.firstIndex(where: { $0.role == .primary }) {
                network.caregivers[index] = Caregiver(
                    id: network.caregivers[index].id,
                    name: network.caregivers[index].name,
                    email: network.caregivers[index].email,
                    role: .primary,
                    apnsDeviceToken: token
                )
            } else {
                network.caregivers.append(
                    Caregiver(name: "Primary caregiver", role: .primary, apnsDeviceToken: token)
                )
            }
            try await save(network)
        } catch {
            isAvailable = false
        }
    }

    func save(_ event: BabyEvent) async {
        guard isAvailable else { return }
        let record = CKRecord(recordType: "NurseryEvent")
        record["id"] = event.id.uuidString as NSString
        record["babyId"] = babyId.uuidString as NSString
        record["timestamp"] = event.timestamp as NSDate
        record["category"] = event.category.rawValue as NSString
        record["severity"] = event.severity.rawValue as NSString
        record["title"] = event.title as NSString
        record["detail"] = event.detail as NSString
        record["confidence"] = event.confidence as NSNumber
        record["metadataJSON"] = event.metadataJSON as NSString

        do {
            _ = try await database.save(record)
            recentCloudEvents.insert(event, at: 0)
        } catch {
            isAvailable = false
        }
    }

    func fetchRecentEvents(limit: Int) async -> [BabyEvent] {
        guard isAvailable else { return [] }
        let predicate = NSPredicate(format: "babyId == %@", babyId.uuidString)
        let query = CKQuery(recordType: "NurseryEvent", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let response = try await database.records(matching: query, resultsLimit: limit)
            let events = response.matchResults.compactMap { _, result in
                try? BabyEvent(record: result.get())
            }
            recentCloudEvents = events
            return events
        } catch {
            isAvailable = false
            return []
        }
    }

    private func fetchOrCreateNetwork() async throws {
        let predicate = NSPredicate(format: "babyId == %@", babyId.uuidString)
        let query = CKQuery(recordType: "CareNetwork", predicate: predicate)
        let response = try await database.records(matching: query, resultsLimit: 1)

        if let record = response.matchResults.compactMap({ _, result in try? result.get() }).first {
            network = CareNetwork(record: record)
        } else {
            let newNetwork = CareNetwork(babyId: babyId, caregivers: [
                Caregiver(name: "Primary caregiver", role: .primary)
            ])
            try await save(newNetwork)
        }
    }

    private func save(_ network: CareNetwork) async throws {
        let record = CKRecord(recordType: "CareNetwork")
        record["id"] = network.id.uuidString as NSString
        record["babyId"] = network.babyId.uuidString as NSString
        let data = try JSONEncoder().encode(network.caregivers)
        record["caregiversJSON"] = String(data: data, encoding: .utf8)! as NSString
        _ = try await database.save(record)
        self.network = network
    }
}

private extension CareNetwork {
    init(record: CKRecord) {
        let id = UUID(uuidString: record["id"] as? String ?? "") ?? UUID()
        let babyId = UUID(uuidString: record["babyId"] as? String ?? "") ?? UUID()
        let caregiversJSON = record["caregiversJSON"] as? String ?? "[]"
        let caregivers = caregiversJSON
            .data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([Caregiver].self, from: $0) } ?? []
        self.init(id: id, babyId: babyId, caregivers: caregivers)
    }
}

private extension BabyEvent {
    convenience init(record: CKRecord) throws {
        let id = UUID(uuidString: record["id"] as? String ?? "") ?? UUID()
        let category = BabyEventCategory(rawValue: record["category"] as? String ?? "") ?? .system
        let severity = BabyEventSeverity(rawValue: record["severity"] as? String ?? "") ?? .info
        let metadataJSON = record["metadataJSON"] as? String ?? "{}"
        let metadata = metadataJSON
            .data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        self.init(
            id: id,
            timestamp: record["timestamp"] as? Date ?? .now,
            category: category,
            severity: severity,
            title: record["title"] as? String ?? "Cloud event",
            detail: record["detail"] as? String ?? "",
            confidence: (record["confidence"] as? NSNumber)?.doubleValue ?? 0,
            metadata: metadata
        )
    }
}
