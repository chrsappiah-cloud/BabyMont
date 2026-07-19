import Foundation

struct Caregiver: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var email: String?
    var role: CaregiverRole
    var apnsDeviceToken: String?

    init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        role: CaregiverRole,
        apnsDeviceToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.apnsDeviceToken = apnsDeviceToken
    }
}

enum CaregiverRole: String, Codable, CaseIterable, Identifiable {
    case primary
    case partner
    case family
    case professional

    var id: String { rawValue }
}

struct CareNetwork: Identifiable, Codable, Hashable {
    var id: UUID
    var babyId: UUID
    var caregivers: [Caregiver]

    init(id: UUID = UUID(), babyId: UUID, caregivers: [Caregiver] = []) {
        self.id = id
        self.babyId = babyId
        self.caregivers = caregivers
    }
}
