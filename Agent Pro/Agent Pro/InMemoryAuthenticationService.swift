// Services/Implementations/Mock/InMemoryAuthenticationService.swift
import Foundation

final class InMemoryAuthenticationService: AuthenticationServiceProtocol {
    private var mockUsers: [String: [String: Any]] = [:]
    private var session: UserSession?

    init() {
        loadMockData()
    }

    private func loadMockData() {
        mockUsers = [
            "agent@test.com": [
                "name": "Agent Test",
                "email": "agent@test.com",
                "agency": "Test Agency",
                "userType": "agent",
                "id": "agent123"
            ],
            "player@test.com": [
                "name": "Joueur Test",
                "email": "player@test.com",
                "position": "Attaquant",
                "age": 25,
                "club": "Test FC",
                "contractStatus": "underContract",
                "marketValue": "5M €",
                "avatar": "👤",
                "inviteCode": "TEST01",
                "userType": "player",
                "id": "player123"
            ]
        ]
    }

    func currentSession() async -> UserSession? {
        session
    }

    func login(email: String, password: String) async throws -> UserSession {
        try await Task.sleep(nanoseconds: 500_000_000)
        if let userData = mockUsers[email] {
            return try await buildSession(from: userData)
        }
        // Auto-provision démo
        if email.contains("agent") {
            let userData: [String: Any] = [
                "name": "Agent Demo",
                "email": email,
                "agency": "Demo Agency",
                "userType": "agent",
                "id": UUID().uuidString
            ]
            mockUsers[email] = userData
            return try await buildSession(from: userData)
        } else {
            let userData: [String: Any] = [
                "name": "Joueur Demo",
                "email": email,
                "position": "Milieu",
                "age": 23,
                "club": "Demo FC",
                "contractStatus": "free",
                "marketValue": "3M €",
                "avatar": "👤",
                "inviteCode": String(format: "%06d", Int.random(in: 100000...999999)),
                "userType": "player",
                "id": UUID().uuidString
            ]
            mockUsers[email] = userData
            return try await buildSession(from: userData)
        }
    }

    func registerAgent(name: String, email: String, agency: String, password: String) async throws -> UserSession {
        try await Task.sleep(nanoseconds: 300_000_000)
        let userData: [String: Any] = [
            "name": name,
            "email": email,
            "agency": agency,
            "userType": "agent",
            "id": UUID().uuidString
        ]
        mockUsers[email] = userData
        return try await buildSession(from: userData)
    }

    func registerPlayer(name: String, email: String, position: String, password: String) async throws -> UserSession {
        try await Task.sleep(nanoseconds: 300_000_000)
        let userData: [String: Any] = [
            "name": name,
            "email": email,
            "position": position,
            "age": 20,
            "club": "Libre",
            "contractStatus": "free",
            "marketValue": "0 €",
            "avatar": "👤",
            "inviteCode": String(format: "%06d", Int.random(in: 100000...999999)),
            "userType": "player",
            "id": UUID().uuidString
        ]
        mockUsers[email] = userData
        return try await buildSession(from: userData)
    }

    func logout() async {
        session = nil
    }

    // MARK: - Helpers

    private func buildSession(from userData: [String: Any]) async throws -> UserSession {
        let type = (userData["userType"] as? String) ?? ""
        if type == "agent" {
            let agent = Agent(
                id: (userData["id"] as? String) ?? "",
                name: (userData["name"] as? String) ?? "",
                email: (userData["email"] as? String) ?? "",
                agency: (userData["agency"] as? String) ?? ""
            )
            let session = UserSession(userType: .agent, agent: agent, player: nil)
            self.session = session
            return session
        } else if type == "player" {
            let player = Player(
                name: (userData["name"] as? String) ?? "",
                email: (userData["email"] as? String) ?? "",
                position: (userData["position"] as? String) ?? "",
                age: (userData["age"] as? Int) ?? 20,
                club: (userData["club"] as? String) ?? "Libre",
                contractStatus: Player.ContractStatus(rawValue: (userData["contractStatus"] as? String) ?? "free") ?? .free,
                marketValue: (userData["marketValue"] as? String) ?? "0 €",
                avatar: (userData["avatar"] as? String) ?? "👤",
                inviteCode: (userData["inviteCode"] as? String) ?? "",
                documents: []
            )
            let session = UserSession(userType: .player, agent: nil, player: player)
            self.session = session
            return session
        }
        throw AppError.unknown("Type d’utilisateur inconnu")
    }
}
