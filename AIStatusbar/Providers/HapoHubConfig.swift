import Foundation

struct HapoHubConfig: Codable, Equatable {
    let id: String
    let displayName: String
    let baseURL: String
    let authHeaderTemplate: String
    let jsonPath: String

    static let mock = HapoHubConfig(
        id: "hapo",
        displayName: "Hapo AI Hub (mock)",
        baseURL: "TODO_BOSS",
        authHeaderTemplate: "Bearer {token}",
        jsonPath: "data.quota.remaining"
    )
}
