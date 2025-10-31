import Foundation
import Combine

// MARK: - API Service
protocol APIService {
    func fetchPlayers() async throws -> [Player]
    func fetchPlayer(id: UUID) async throws -> Player
    func updatePlayer(_ player: Player) async throws -> Player
    func deletePlayer(id: UUID) async throws
    func fetchMessages() async throws -> [Chat]
    func sendMessage(_ message: String, to chatId: UUID) async throws
}

// MARK: - Mock API Service (pour développement)
class MockAPIService: APIService {
    private let delay: TimeInterval = 1.0
    
    func fetchPlayers() async throws -> [Player] {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        // Simuler une erreur parfois (25% de chance)
        if Bool.random() && Bool.random() {
            throw AppError.network
        }
        
        return MockData.samplePlayers
    }
    
    func fetchPlayer(id: UUID) async throws -> Player {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        guard let player = MockData.samplePlayers.first(where: { $0.id == id }) else {
            throw AppError.userNotFound
        }
        
        return player
    }
    
    func updatePlayer(_ player: Player) async throws -> Player {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return player
    }
    
    func deletePlayer(id: UUID) async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    
    func fetchMessages() async throws -> [Chat] {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return MockData.sampleChats
    }
    
    func sendMessage(_ message: String, to chatId: UUID) async throws {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

// MARK: - Cache Manager
class CacheManager: ObservableObject {
    private var playersCache: [UUID: Player] = [:]
    private var playersCacheTime: Date?
    private let cacheTimeout: TimeInterval = 300 // 5 minutes
    
    func cachePlayer(_ player: Player) {
        playersCache[player.id] = player
    }
    
    func getCachedPlayer(id: UUID) -> Player? {
        return playersCache[id]
    }
    
    func cacheAllPlayers(_ players: [Player]) {
        playersCache = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        playersCacheTime = Date()
    }
    
    func getCachedPlayers() -> [Player]? {
        guard let cacheTime = playersCacheTime,
              Date().timeIntervalSince(cacheTime) < cacheTimeout else {
            return nil
        }
        return Array(playersCache.values)
    }
    
    func clearCache() {
        playersCache.removeAll()
        playersCacheTime = nil
    }
}

// MARK: - Enhanced Player Manager
@MainActor
class EnhancedPlayerManager: ObservableObject {
    @Published var players: [Player] = []
    @Published var isLoading = false
    @Published var lastError: AppError?
    
    private let apiService: APIService
    private let cacheManager = CacheManager()
    private var cancellables = Set<AnyCancellable>()
    
    init(apiService: APIService = MockAPIService()) {
        self.apiService = apiService
    }
    
    func loadPlayers(forceRefresh: Bool = false) async {
        // Essayer le cache d'abord
        if !forceRefresh, let cachedPlayers = cacheManager.getCachedPlayers() {
            players = cachedPlayers
            return
        }
        
        isLoading = true
        lastError = nil
        
        do {
            let fetchedPlayers = try await apiService.fetchPlayers()
            players = fetchedPlayers
            cacheManager.cacheAllPlayers(fetchedPlayers)
        } catch {
            if let appError = error as? AppError {
                lastError = appError
            } else {
                // Erreur générique réseau
                lastError = .network
            }
        }
        
        isLoading = false
    }
    
    func addPlayer(_ player: Player) async {
        players.append(player)
        cacheManager.cachePlayer(player)
        
        // TODO: Sync avec l'API en arrière-plan
    }
    
    func updatePlayer(_ updatedPlayer: Player) async {
        if let index = players.firstIndex(where: { $0.id == updatedPlayer.id }) {
            players[index] = updatedPlayer
            cacheManager.cachePlayer(updatedPlayer)
        }
        
        do {
            _ = try await apiService.updatePlayer(updatedPlayer)
        } catch {
            // Handle error - peut-être rollback les changements
            lastError = .network
        }
    }
    
    func deletePlayer(_ player: Player) async {
        players.removeAll { $0.id == player.id }
        
        do {
            try await apiService.deletePlayer(id: player.id)
        } catch {
            // Rollback si échec
            players.append(player)
            lastError = .network
        }
    }
    
    // MARK: - Search & Filter
    func searchPlayers(query: String) -> [Player] {
        if query.isEmpty {
            return players
        }
        
        return players.filter { player in
            player.name.localizedCaseInsensitiveContains(query) ||
            player.club.localizedCaseInsensitiveContains(query) ||
            player.position.localizedCaseInsensitiveContains(query)
        }
    }
    
    func filterPlayers(by status: Player.ContractStatus) -> [Player] {
        return players.filter { $0.contractStatus == status }
    }
    
    // MARK: - Statistics
    var totalPlayersValue: Double {
        players.reduce(0.0) { acc, player in
            acc + player.marketValueDouble
        }
    }
    
    var contractStatusCounts: [Player.ContractStatus: Int] {
        Dictionary(grouping: players, by: \.contractStatus)
            .mapValues { $0.count }
    }
    
    var averageAge: Double {
        guard !players.isEmpty else { return 0 }
        let totalAge = players.map(\.age).reduce(0, +)
        return Double(totalAge) / Double(players.count)
    }
}

// MARK: - Mock Data
struct MockData {
    static let samplePlayers: [Player] = [
        Player(
            name: "Lucas Silva",
            email: "lucas.silva@email.com",
            position: "Milieu offensif",
            age: 24,
            club: "AS Monaco",
            contractStatus: .underContract,
            marketValue: "12M €",
            avatar: "👤",
            inviteCode: "LSV24",
            documents: sampleDocuments()
        ),
        Player(
            name: "Karim Ben Ali", 
            email: "karim.benali@email.com",
            position: "Attaquant",
            age: 22,
            club: "Libre",
            contractStatus: .free,
            marketValue: "8M €",
            avatar: "👤",
            inviteCode: "KBA22",
            documents: sampleDocuments()
        )
    ]
    
    static let sampleChats: [Chat] = [
        // Mock chats data
    ]
    
    private static func sampleDocuments() -> [Document] {
        return [
            Document(
                name: "Contrat principal 2024",
                category: .contract,
                uploadDate: Date().addingTimeInterval(-86400 * 30),
                size: "2.4 MB",
                url: "contract_2024.pdf"
            )
        ]
    }
}

// MARK: - Player helpers
extension Player {
    // Convertit "12M €" -> 12.0, "800k €" -> 0.8, "3.5 €" -> 3.5 (démo simple)
    var marketValueDouble: Double {
        let s = marketValue
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .lowercased()
        if s.contains("m") {
            let n = s.replacingOccurrences(of: "m", with: "")
            return Double(n.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        } else if s.contains("k") {
            let n = s.replacingOccurrences(of: "k", with: "")
            let val = Double(n.replacingOccurrences(of: ",", with: ".")) ?? 0.0
            return val / 1000.0
        } else {
            return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0.0
        }
    }
}
