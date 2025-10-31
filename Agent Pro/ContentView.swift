import SwiftUI
import UIKit
import UserNotifications

// ÉTAPE 1: LES MODÈLES DE DONNÉES
// Ce sont les structures qui définissent vos données

// Enum pour définir si c'est un agent ou un joueur
enum UserType: String, CaseIterable, Codable {
    case agent = "agent"
    case player = "player"
    
    var displayName: String {
        switch self {
        case .agent: return "Agent"
        case .player: return "Joueur"
        }
    }
    
    var icon: String {
        switch self {
        case .agent: return "briefcase.fill"
        case .player: return "sportscourt.fill"
        }
    }
}

// Modèle pour un joueur
struct Player: Identifiable, Codable {
    var id = UUID()
    let name: String
    let email: String
    let position: String
    let age: Int
    let club: String
    let contractStatus: ContractStatus
    let marketValue: String
    let avatar: String
    let inviteCode: String
    let documents: [Document]

    enum ContractStatus: String, CaseIterable, Codable {
        case underContract = "Sous contrat"
        case negotiating = "En négociation"
        case free = "Libre"
    }

    private enum CodingKeys: String, CodingKey {
        case name, email, position, age, club, contractStatus, marketValue, avatar, inviteCode, documents
    }
}

// Modèle pour un document
struct Document: Identifiable, Codable {
    var id = UUID()
    let name: String
    let category: DocumentCategory
    let uploadDate: Date
    let size: String
    let url: String

    enum DocumentCategory: String, CaseIterable, Codable {
        case contract = "Contrats"
        case medical = "Médical"
        case identity = "Identité"
        case performance = "Performance"
    }

    private enum CodingKeys: String, CodingKey {
        case name, category, uploadDate, size, url
    }
}

// Modèle pour un message
struct Message: Identifiable, Codable, Hashable {
    var id = UUID()
    let text: String
    let sender: MessageSender
    let timestamp: Date
    let isRead: Bool
    let attachmentURL: String?

    enum MessageSender: String, Codable {
        case agent = "agent"
        case player = "player"
    }

    private enum CodingKeys: String, CodingKey {
        case text, sender, timestamp, isRead, attachmentURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

// Modèle pour une conversation
struct Chat: Identifiable, Codable, Hashable {
    var id = UUID()
    let playerId: UUID
    let playerName: String
    let playerAvatar: String
    var messages: [Message]
    var lastMessage: String
    var lastMessageTime: Date
    // Deux compteurs séparés: ce que chaque côté n’a PAS encore lu
    var unreadForAgent: Int
    var unreadForPlayer: Int

    var formattedLastMessageTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: lastMessageTime)
    }

    private enum CodingKeys: String, CodingKey {
        case playerId, playerName, playerAvatar, messages, lastMessage, lastMessageTime, unreadForAgent, unreadForPlayer
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Chat, rhs: Chat) -> Bool {
        lhs.id == rhs.id
    }
}

// Modèle pour les statistiques d'un joueur
struct PlayerStats: Identifiable, Codable {
    var id = UUID()
    let playerId: UUID
    let goals: Int
    let assists: Int
    let minutesPlayed: Int
    let matchesPlayed: Int
    let averageRating: Double
    let season: String

    private enum CodingKeys: String, CodingKey {
        case playerId, goals, assists, minutesPlayed, matchesPlayed, averageRating, season
    }
}

// MANAGER POUR LES NOTIFICATIONS
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var hasPermission = false
    @Published var badgeCount = 0
    
    static let shared = NotificationManager()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // Demander la permission pour les notifications
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            await MainActor.run {
                hasPermission = granted
            }
        } catch {
            print("Erreur demande permission notifications: \(error)")
        }
    }
    
    // Programmer une notification pour un contrat qui expire
    func scheduleContractReminder(for player: Player, daysBeforeExpiry: Int = 30) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Contrat à renouveler"
        content.body = "Le contrat de \(player.name) expire dans \(daysBeforeExpiry) jours"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(daysBeforeExpiry * 24 * 60 * 60),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "contract-\(player.id.uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erreur programmation notification: \(error)")
            }
        }
    }
    
    // Programmer une notification pour un nouveau message
    func scheduleMessageNotification(from sender: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "💬 Nouveau message"
        content.body = "\(sender): \(message)"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "message-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MANAGER POUR L'AUTHENTIFICATION (connexion/déconnexion)
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var showOnboarding = true
    @Published var showUserTypeSelection = false
    @Published var userType: UserType?
    @Published var currentAgent: Agent?
    @Published var currentPlayer: Player?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Structure pour un Agent
    struct Agent {
        let id: String
        let name: String
        let email: String
        let agency: String
    }
    
    // Données de test (en mode démo)
    private var mockUsers: [String: [String: Any]] = [:]
    
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
    
    // Fonction de connexion
    @MainActor
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        // Simulation d'une attente (comme un appel serveur)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 seconde
        
        if let userData = mockUsers[email] {
            await loadUserData(userData: userData)
        } else {
            // Créer un utilisateur temporaire pour les tests
            let inferredType = email.contains("agent") ? "agent" : "player"
            let userData: [String: Any] = [
                "name": "Demo User",
                "email": email,
                // On enregistre quand même un type par défaut; il pourra être écrasé par userType pré-sélectionné
                "userType": inferredType,
                "id": UUID().uuidString
            ]
            mockUsers[email] = userData
            await loadUserData(userData: userData)
        }
        
        isLoading = false
    }
    
    // Charger les données utilisateur après connexion
    @MainActor
    private func loadUserData(userData: [String: Any]) async {
        // Utiliser le type déjà choisi si présent, sinon le type venant des données mock
        let resolvedType: UserType = {
            if let preselected = userType {
                return preselected
            }
            if let raw = userData["userType"] as? String,
               let fromData = UserType(rawValue: raw) {
                return fromData
            }
            return .player // défaut
        }()
        
        switch resolvedType {
        case .agent:
            currentAgent = Agent(
                id: userData["id"] as? String ?? "",
                name: userData["name"] as? String ?? "",
                email: userData["email"] as? String ?? "",
                agency: userData["agency"] as? String ?? "Agence"
            )
            currentPlayer = nil
            userType = .agent
            
        case .player:
            currentPlayer = Player(
                name: userData["name"] as? String ?? "",
                email: userData["email"] as? String ?? "",
                position: userData["position"] as? String ?? "Poste",
                age: userData["age"] as? Int ?? 20,
                club: userData["club"] as? String ?? "Libre",
                contractStatus: Player.ContractStatus(rawValue: userData["contractStatus"] as? String ?? "free") ?? .free,
                marketValue: userData["marketValue"] as? String ?? "0 €",
                avatar: userData["avatar"] as? String ?? "👤",
                inviteCode: userData["inviteCode"] as? String ?? "",
                documents: []
            )
            currentAgent = nil
            userType = .player
        }
        
        isAuthenticated = true
        showOnboarding = false
        showUserTypeSelection = false
    }
    
    // Déconnexion
    @MainActor
    func logout() {
        currentAgent = nil
        currentPlayer = nil
        userType = nil
        isAuthenticated = false
        showUserTypeSelection = true
    }
    
    // Choisir le type d'utilisateur
    func selectUserType(_ type: UserType) {
        userType = type
        showUserTypeSelection = false
    }
    
    // Terminer l'onboarding
    func completeOnboarding() {
        showOnboarding = false
        showUserTypeSelection = true
    }
    
    // AJOUT: état d’auth au démarrage (pour corriger l’appel dans ContentView)
    func checkAuthenticationStatus() {
        // Démo: démarrer sur l’onboarding
        showOnboarding = true
        isAuthenticated = false
        showUserTypeSelection = false
        userType = nil
    }
}

// MANAGER POUR GÉRER LES JOUEURS
class PlayerManager: ObservableObject {
    @Published var players: [Player] = []
    
    init() {
        loadSamplePlayers()
    }
    
    private func loadSamplePlayers() {
        players = [
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
    }
    
    private func sampleDocuments() -> [Document] {
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
    
    func addPlayer(_ player: Player) {
        players.append(player)
    }
}

// MANAGER POUR LES MESSAGES
class MessageManager: ObservableObject {
    @Published var chats: [Chat] = []
    
    init() {
        loadSampleChats()
    }
    
    private func loadSampleChats() {
        let sampleMessages = [
            Message(
                text: "Bonjour, j'ai reçu la proposition de contrat.",
                sender: .player,
                timestamp: Date().addingTimeInterval(-3600),
                isRead: false,
                attachmentURL: nil
            )
        ]
        
        chats = [
            Chat(
                playerId: UUID(),
                playerName: "Lucas Silva",
                playerAvatar: "👤",
                messages: sampleMessages,
                lastMessage: "Bonjour, j'ai reçu la proposition...",
                lastMessageTime: Date().addingTimeInterval(-3600),
                unreadForAgent: 1,      // message joueur non lu côté agent
                unreadForPlayer: 0
            )
        ]
    }
    
    // Démarrer une nouvelle conversation avec un joueur (agent -> joueur)
    func startChat(with player: Player) -> Chat {
        if let existing = chats.first(where: { $0.playerId == player.id }) {
            return existing
        }
        let newChat = Chat(
            playerId: player.id,
            playerName: player.name,
            playerAvatar: player.avatar,
            messages: [],
            lastMessage: "",
            lastMessageTime: Date(),
            unreadForAgent: 0,
            unreadForPlayer: 0
        )
        chats.insert(newChat, at: 0)
        return newChat
    }
    
    // Envoyer un message depuis l'agent ou le joueur et mettre à jour les compteurs
    func sendMessage(_ text: String, from sender: Message.MessageSender, to chatId: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatId }) else { return }
        
        let newMessage = Message(
            text: text,
            sender: sender,
            timestamp: Date(),
            isRead: false,
            attachmentURL: nil
        )
        
        chats[chatIndex].messages.append(newMessage)
        chats[chatIndex].lastMessage = text
        chats[chatIndex].lastMessageTime = newMessage.timestamp
        
        // Incrémente le compteur pour l’autre partie
        switch sender {
        case .agent:
            chats[chatIndex].unreadForPlayer += 1
        case .player:
            chats[chatIndex].unreadForAgent += 1
        }
        
        // Notifier (optionnel)
        let senderName = (sender == .agent) ? "Agent" : "Joueur"
        NotificationManager.shared.scheduleMessageNotification(from: senderName, message: text)
    }
    
    // Marquer une conversation comme lue pour un côté
    func markChatAsRead(chatId: UUID, for userType: UserType) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatId }) else { return }
        switch userType {
        case .agent:
            chats[chatIndex].unreadForAgent = 0
        case .player:
            chats[chatIndex].unreadForPlayer = 0
        }
    }
    
    // Marquer toutes les conversations comme lues pour un côté
    func markAllAsRead(for userType: UserType) {
        for index in chats.indices {
            switch userType {
            case .agent:
                chats[index].unreadForAgent = 0
            case .player:
                chats[index].unreadForPlayer = 0
            }
        }
    }
}
// ÉTAPE 3: DESIGN SYSTEM ET COMPOSANTS UI
// Ici on définit les couleurs, styles et composants réutilisables

// DÉFINITION DES COULEURS ET STYLES
struct AppTheme {
    // Couleurs principales
    static let primaryBlue = Color(red: 0.067, green: 0.345, blue: 0.718)
    static let secondaryBlue = Color(red: 0.133, green: 0.463, blue: 0.863)
    static let accentGold = Color(red: 0.976, green: 0.761, blue: 0.227)
    static let darkNavy = Color(red: 0.047, green: 0.169, blue: 0.322)
    static let lightGray = Color(red: 0.969, green: 0.976, blue: 0.988)
    static let mediumGray = Color(red: 0.859, green: 0.886, blue: 0.925)
    static let darkGray = Color(red: 0.384, green: 0.439, blue: 0.522)
    
    // Couleurs pour les statuts
    static let successGreen = Color(red: 0.125, green: 0.698, blue: 0.314)
    static let warningOrange = Color(red: 1.0, green: 0.584, blue: 0.0)
    static let errorRed = Color(red: 0.898, green: 0.224, blue: 0.208)
    
    // Dégradés
    static let primaryGradient = LinearGradient(
        colors: [primaryBlue, secondaryBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let backgroundGradient = LinearGradient(
        colors: [lightGray, Color.white],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Ombres
    static let cardShadow = Color.black.opacity(0.08)
    static let buttonShadow = Color.black.opacity(0.15)
}

// COMPOSANT : CHAMP DE TEXTE STYLISÉ
struct PremiumTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        HStack(spacing: 16) {
            // Icône à gauche
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.darkGray)
                .frame(width: 20)
            
            // Champ de texte
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium))
                .keyboardType(keyboardType)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(text.isEmpty ? AppTheme.mediumGray : AppTheme.primaryBlue, lineWidth: 1.5)
        )
    }
}

// COMPOSANT : CHAMP DE MOT DE PASSE STYLISÉ
struct PremiumSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.darkGray)
                .frame(width: 20)
            
            SecureField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium))
                .textContentType(.password)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(text.isEmpty ? AppTheme.mediumGray : AppTheme.primaryBlue, lineWidth: 1.5)
        )
    }
}

// COMPOSANT : STYLE DE BOUTON PREMIUM
struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .padding(.vertical, 18)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.primaryGradient)
                    .shadow(color: AppTheme.buttonShadow, radius: 12, x: 0, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// COMPOSANT : BADGE DE STATUT (pour les contrats)
struct StatusBadge: View {
    let status: Player.ContractStatus
    
    var statusColor: Color {
        switch status {
        case .underContract:
            return AppTheme.successGreen
        case .negotiating:
            return AppTheme.warningOrange
        case .free:
            return AppTheme.errorRed
        }
    }
    
    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.1))
            .foregroundColor(statusColor)
            .cornerRadius(10)
    }
}

// COMPOSANT : CARTE D'ACTION RAPIDE
struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(color)
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
        }
        .frame(width: 140, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 6)
        )
    }
}

// COMPOSANT : CARTE DE STATISTIQUE
struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                
                Spacer()
                
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 12, height: 12)
            }
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.darkGray)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: .infinity)
    }
}

// AJOUT: alias StatsCard pour compat avec les usages existants
struct StatsCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        StatCard(title: title, value: value, subtitle: subtitle, color: color)
    }
}

// EXEMPLE D'UTILISATION DE CES COMPOSANTS
struct ExampleUsageView: View {
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Utilisation du champ de texte personnalisé
            PremiumTextField(
                placeholder: "Adresse email",
                text: $email,
                icon: "envelope.fill",
                keyboardType: .emailAddress
            )
            
            // Utilisation du champ de mot de passe personnalisé
            PremiumSecureField(
                placeholder: "Mot de passe",
                text: $password,
                icon: "lock.fill"
            )
            
            // Utilisation du bouton personnalisé
            Button("Se connecter") {
                // Action de connexion
            }
            .buttonStyle(PremiumButtonStyle())
            
            // Utilisation d'une carte de statistique
            StatCard(
                title: "Joueurs",
                value: "12",
                subtitle: "Total",
                color: AppTheme.primaryBlue
            )
        }
        .padding()
        .background(AppTheme.backgroundGradient)
    }
}
// ÉTAPE 4: APPLICATION PRINCIPALE ET NAVIGATION
// C'est ici qu'on assemble tout et qu'on définit la navigation

// POINT D'ENTRÉE DE L'APPLICATION
@main
struct AgentProApp: App {
    // Création des managers (une seule fois pour toute l'app)
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var playerManager = PlayerManager()
    @StateObject private var messageManager = MessageManager()
    @StateObject private var notificationManager = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                // On partage les managers avec toutes les vues
                .environmentObject(authManager)
                .environmentObject(playerManager)
                .environmentObject(messageManager)
                .environmentObject(notificationManager)
                .onAppear {
                    // Demander la permission pour les notifications au démarrage
                    Task {
                        await notificationManager.requestPermission()
                    }
                }
        }
    }
}

// VUE PRINCIPALE QUI DÉCIDE QUOI AFFICHER
struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // Utilisateur connecté - montrer l'interface selon son type
                if authManager.userType == .player {
                    PlayerMainTabView()   // Interface joueur
                } else {
                    AgentMainTabView()    // Interface agent
                }
            } else if authManager.showOnboarding {
                OnboardingView()          // Premier lancement - intro
            } else if authManager.showUserTypeSelection {
                UserTypeSelectionView()   // Choix agent ou joueur
            } else {
                LoginView()               // Écran de connexion
            }
        }
        // SUPPRIMÉ: ne pas réinitialiser l'état à chaque apparition
        // .onAppear {
        //     authManager.checkAuthenticationStatus()
        // }
    }
}

// NAVIGATION PRINCIPALE POUR LES AGENTS (TabView avec onglets)
struct AgentMainTabView: View {
    @EnvironmentObject var messageManager: MessageManager
    
    var totalUnread: Int {
        messageManager.chats.reduce(0) { $0 + $1.unreadForAgent }
    }
    
    var body: some View {
        TabView {
            AgentHomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Accueil")
                }
            
            MessagesView()
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("Messages")
                }
                .badgeIf(totalUnread)
            
            PlayersView()
                .tabItem {
                    Image(systemName: "person.3.fill")
                    Text("Joueurs")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Paramètres")
                }
        }
        .accentColor(AppTheme.primaryBlue)
    }
}

// NAVIGATION PRINCIPALE POUR LES JOUEURS
struct PlayerMainTabView: View {
    @EnvironmentObject var messageManager: MessageManager
    
    var totalUnread: Int {
        messageManager.chats.reduce(0) { $0 + $1.unreadForPlayer }
    }
    
    var body: some View {
        TabView {
            PlayerHomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Accueil")
                }
            
            PlayerStatsView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Stats")
                }
            
            PlayerMessagesView()
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("Messages")
                }
                .badgeIf(totalUnread)
            
            PlayerDocumentsView()
                .tabItem {
                    Image(systemName: "doc.fill")
                    Text("Documents")
                }
            
            PlayerProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profil")
                }
        }
        .accentColor(AppTheme.primaryBlue)
    }
}

// ÉCRAN D'ONBOARDING (introduction pour nouveaux utilisateurs)
struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var currentPage = 0
    
    private let pages = [
        OnboardingPage(
            title: "Gérez vos talents",
            subtitle: "Suivez vos joueurs et leurs carrières en temps réel",
            imageName: "person.3.fill"
        ),
        OnboardingPage(
            title: "Communication directe",
            subtitle: "Restez en contact permanent avec vos joueurs",
            imageName: "message.fill"
        ),
        OnboardingPage(
            title: "Documents centralisés",
            subtitle: "Tous vos contrats et documents au même endroit"
        , imageName: "doc.fill")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Pages qui défilent
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            
            // Boutons de navigation
            VStack(spacing: 20) {
                if currentPage == pages.count - 1 {
                    Button("Commencer") {
                        authManager.completeOnboarding()
                    }
                    .buttonStyle(PremiumButtonStyle())
                } else {
                    Button("Suivant") {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(PremiumButtonStyle())
                }
                
                Button("Passer") {
                    authManager.completeOnboarding()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppTheme.darkGray)
            }
            .padding(32)
        }
        .background(AppTheme.backgroundGradient)
    }
}

// STRUCTURE POUR UNE PAGE D'ONBOARDING
struct OnboardingPage {
    let title: String
    let subtitle: String
    let imageName: String
}

// VUE POUR UNE PAGE D'ONBOARDING
struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icône avec effet visuel
            ZStack {
                Circle()
                    .fill(AppTheme.primaryGradient)
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                    .opacity(0.3)
                
                Image(systemName: page.imageName)
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(AppTheme.primaryGradient)
            }
            
            // Texte
            VStack(spacing: 20) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.darkNavy)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .lineSpacing(4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// ÉCRAN DE SÉLECTION DU TYPE D'UTILISATEUR
struct UserTypeSelectionView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedType: UserType?
    
    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                VStack(spacing: 20) {
                    Text("Qui êtes-vous ?")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.darkNavy)
                        .multilineTextAlignment(.center)
                    
                    Text("Choisissez votre profil pour accéder à l'interface adaptée")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                
                VStack(spacing: 20) {
                    UserTypeCard(
                        type: .agent,
                        isSelected: selectedType == .agent,
                        onTap: { selectedType = .agent }
                    )
                    
                    UserTypeCard(
                        type: .player,
                        isSelected: selectedType == .player,
                        onTap: { selectedType = .player }
                    )
                }
                
                if selectedType != nil {
                    Button("Continuer") {
                        if let type = selectedType {
                            authManager.selectUserType(type)
                        }
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }
                
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedType)
    }
}

// CARTE POUR CHOISIR LE TYPE D'UTILISATEUR
struct UserTypeCard: View {
    let type: UserType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AppTheme.primaryBlue : AppTheme.lightGray)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isSelected ? .white : AppTheme.darkGray)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(type.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppTheme.darkNavy)
                    
                    Text(getDescription(for: type))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.successGreen)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(
                        color: isSelected ? AppTheme.primaryBlue.opacity(0.3) : AppTheme.cardShadow,
                        radius: isSelected ? 15 : 8,
                        x: 0,
                        y: isSelected ? 8 : 4
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        isSelected ? AppTheme.primaryBlue : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func getDescription(for type: UserType) -> String {
        switch type {
        case .agent:
            return "Gérez vos joueurs, négociez des contrats et suivez leurs performances"
        case .player:
            return "Consultez vos statistiques, communiquez avec votre agent et gérez votre carrière"
        }
    }
}

// ÉCRAN DE CONNEXION
struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Logo et titre
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.primaryGradient)
                                .frame(width: 120, height: 120)
                                .shadow(color: AppTheme.buttonShadow, radius: 20, x: 0, y: 10)
                            
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.system(size: 50, weight: .medium))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 12) {
                            Text("Agent Pro")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.darkNavy)
                            
                            if let userType = authManager.userType {
                                Text("Connexion \(userType.displayName)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.primaryBlue)
                            } else {
                                Text("Votre plateforme de gestion professionnelle")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.darkGray)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    
                    // Formulaire de connexion
                    VStack(spacing: 20) {
                        PremiumTextField(
                            placeholder: "Adresse email",
                            text: $email,
                            icon: "envelope.fill",
                            keyboardType: .emailAddress
                        )
                        
                        PremiumSecureField(
                            placeholder: "Mot de passe",
                            text: $password,
                            icon: "lock.fill"
                        )
                        
                        Button("Se connecter") {
                            Task {
                                await authManager.login(email: email, password: password)
                            }
                        }
                        .buttonStyle(PremiumButtonStyle())
                        .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                    }
                    
                    Spacer()
                    
                    // Liens en bas
                    VStack(spacing: 16) {
                        Button("Créer un compte") {
                            showRegister = true
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.primaryBlue)
                        
                        Button("Changer de profil") {
                            authManager.showUserTypeSelection = true
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 40)
                
                // Indicateur de chargement
                if authManager.isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(AppTheme.primaryBlue)
                        
                        Text("Connexion en cours...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.darkNavy)
                    }
                    .padding(40)
                    .background(Color.white)
                    .cornerRadius(20)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showRegister) {
            RegisterView()
        }
    }
}

// ÉCRAN D'INSCRIPTION (PLACEHOLDER)
struct RegisterView: View {
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Écran d'inscription")
                    .font(.title)
                
                Text("(À implémenter)")
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Inscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
// ÉTAPE 5: ÉCRANS PRINCIPAUX POUR LES AGENTS
// Ici on crée les vues que les agents vont voir

// ÉCRAN D'ACCUEIL POUR LES AGENTS
struct AgentHomeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var playerManager: PlayerManager
    @EnvironmentObject var messageManager: MessageManager
    @EnvironmentObject var notificationManager: NotificationManager
    
    // Nouveaux états pour l’UX agent
    @State private var showComposeSheet = false
    @State private var showFABMenu = false
    @State private var quickSearch = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Arrière-plan avec dégradé
                LinearGradient(
                    colors: [AppTheme.lightGray, Color.white, AppTheme.lightGray.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        // En-tête avec salutation + recherche rapide
                        headerSection
                        
                        // Vue d'ensemble du portefeuille
                        portfolioOverview
                        
                        // Contrats à échéance
                        contractsSection
                        
                        // Actions rapides
                        quickActionsSection
                        
                        // Statistiques temps réel
                        statisticsSection
                        
                        // Activité récente
                        recentActivitySection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100) // laisser la place au FAB
                }
                
                // Bouton d’action flottant
                FloatingActionMenu(isOpen: $showFABMenu) {
                    // 1. Nouveau message
                    Button {
                        showComposeSheet = true
                        showFABMenu = false
                    } label: {
                        Label("Nouveau message", systemImage: "square.and.pencil")
                    }
                    // 2. Nouveau joueur
                    Button {
                        showFABMenu = false
                        // Placeholder action
                    } label: {
                        Label("Nouveau joueur", systemImage: "person.crop.circle.badge.plus")
                    }
                    // 3. Nouveau document
                    Button {
                        showFABMenu = false
                        // Placeholder action
                    } label: {
                        Label("Nouveau document", systemImage: "doc.badge.plus")
                    }
                    // 4. RDV
                    Button {
                        showFABMenu = false
                        // Placeholder action
                    } label: {
                        Label("Planifier RDV", systemImage: "calendar.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showComposeSheet) {
                ComposeMessageSheet(
                    players: playerManager.players,
                    onSend: { player, text in
                        let chat = messageManager.startChat(with: player)
                        messageManager.sendMessage(text, from: .agent, to: chat.id)
                    }
                )
            }
            .navigationBarHidden(true)
        }
    }
    
    // EN-TÊTE AVEC SALUTATION, RECHERCHE, AVATAR
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(getGreeting())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                    
                    Text(authManager.currentAgent?.name ?? "Agent")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.darkNavy)
                    
                    Text(authManager.currentAgent?.agency ?? "")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.primaryBlue)
                }
                
                Spacer()
                
                // Avatar et notifications
                HStack(spacing: 20) {
                    Button(action: {}) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 44, height: 44)
                                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(AppTheme.primaryBlue)
                            
                            // Badge de notification
                            let totalUnread = messageManager.chats.reduce(0, { $0 + $1.unreadForAgent })
                            if totalUnread > 0 {
                                Circle()
                                    .fill(AppTheme.errorRed)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 12, y: -12)
                            }
                        }
                    }
                    
                    // Avatar de l'utilisateur
                    ZStack {
                        Circle()
                            .fill(AppTheme.primaryGradient)
                            .frame(width: 52, height: 52)
                        
                        let initial = authManager.currentAgent?.name.prefix(1) ?? "A"
                        Text(String(initial))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: AppTheme.buttonShadow, radius: 10, x: 0, y: 5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 12)
            .background(Color.white.opacity(0.95))
            
            // Barre de recherche rapide
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.darkGray)
                TextField("Recherche rapide (nom, club, poste)", text: $quickSearch)
                    .textInputAutocapitalization(.words)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 24)
            
            // Résultats rapides (si recherche)
            if !quickSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                let results = playerManager.players.filter { p in
                    p.name.localizedCaseInsensitiveContains(quickSearch)
                    || p.club.localizedCaseInsensitiveContains(quickSearch)
                    || p.position.localizedCaseInsensitiveContains(quickSearch)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(results) { player in
                            NavigationLink(destination: PlayerDetailView(player: player)) {
                                HStack(spacing: 10) {
                                    Text(player.avatar)
                                        .font(.system(size: 18))
                                        .frame(width: 32, height: 32)
                                        .background(AppTheme.lightGray)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(player.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppTheme.darkNavy)
                                        Text(player.club)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(AppTheme.darkGray)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                        .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
    
    // VUE D'ENSEMBLE DU PORTEFEUILLE
    private var portfolioOverview: some View {
        VStack(spacing: 20) {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VALEUR TOTALE DU PORTEFEUILLE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.darkGray)
                            .tracking(1.2)
                        
                        Text("€ \(calculateTotalValue())")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.darkNavy)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                            Text("+12.5%")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(AppTheme.successGreen)
                    }
                    
                    Spacer()
                    
                    // Mini graphique
                    MiniChart()
                }
                
                // Indicateurs rapides
                HStack(spacing: 16) {
                    MiniIndicator(
                        icon: "person.3.fill",
                        value: "\(playerManager.players.count)",
                        label: "Joueurs"
                    )
                    
                    MiniIndicator(
                        icon: "doc.text.fill",
                        value: "8",
                        label: "Contrats"
                    )
                    
                    MiniIndicator(
                        icon: "calendar",
                        value: "3",
                        label: "RDV"
                    )
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, AppTheme.lightGray.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: AppTheme.cardShadow, radius: 20, x: 0, y: 10)
            )
        }
    }
    
    // SECTION CONTRATS À ÉCHÉANCE (simulation basée sur le statut)
    private var contractsSection: some View {
        let urgent = playerManager.players.filter { $0.contractStatus == .negotiating || $0.contractStatus == .free }
        let watchlist = playerManager.players.filter { $0.contractStatus == .underContract }
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Contrats à échéance")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                Spacer()
                if !urgent.isEmpty {
                    Text("\(urgent.count) urgents")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(AppTheme.errorRed).cornerRadius(12)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(urgent) { player in
                        PlayerContractCard(player: player, urgencyColor: player.contractStatus == .free ? AppTheme.errorRed : AppTheme.warningOrange)
                    }
                    ForEach(watchlist) { player in
                        PlayerContractCard(player: player, urgencyColor: AppTheme.successGreen.opacity(0.8))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // ACTIONS RAPIDES
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Actions rapides")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Test notification
                    Button(action: {
                        if let firstPlayer = playerManager.players.first {
                            notificationManager.scheduleContractReminder(for: firstPlayer, daysBeforeExpiry: 1)
                        }
                    }) {
                        QuickActionCard(
                            icon: "bell.badge",
                            title: "Test Notification",
                            subtitle: "Tester les alertes",
                            color: AppTheme.warningOrange
                        )
                    }
                    
                    Button(action: {
                        showComposeSheet = true
                    }) {
                        QuickActionCard(
                            icon: "square.and.pencil",
                            title: "Message",
                            subtitle: "Écrire à un joueur",
                            color: AppTheme.primaryBlue
                        )
                    }
                    
                    QuickActionCard(
                        icon: "doc.badge.plus",
                        title: "Document",
                        subtitle: "Ajouter un fichier",
                        color: AppTheme.warningOrange
                    )
                    
                    QuickActionCard(
                        icon: "calendar.badge.plus",
                        title: "Rendez-vous",
                        subtitle: "Planifier un RDV",
                        color: AppTheme.accentGold
                    )
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // SECTION STATISTIQUES
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistiques")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(
                    title: "Messages",
                    value: "\(messageManager.chats.reduce(0) { $0 + $1.unreadForAgent })",
                    subtitle: "non lus",
                    color: AppTheme.errorRed
                )
                
                StatCard(
                    title: "Documents",
                    value: "24",
                    subtitle: "ce mois",
                    color: AppTheme.primaryBlue
                )
                
                StatCard(
                    title: "Négociations",
                    value: "\(playerManager.players.filter { $0.contractStatus == .negotiating }.count)",
                    subtitle: "en cours",
                    color: AppTheme.warningOrange
                )
                
                StatCard(
                    title: "Joueurs libres",
                    value: "\(playerManager.players.filter { $0.contractStatus == .free }.count)",
                    subtitle: "à placer",
                    color: AppTheme.successGreen
                )
            }
        }
    }
    
    // ACTIVITÉ RÉCENTE
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activité récente")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                
                Spacer()
                
                Button("Tout voir") {}
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryBlue)
            }
            
            VStack(spacing: 12) {
                ActivityRow(
                    icon: "message.fill",
                    title: "Lucas Silva",
                    subtitle: "Nouveau message reçu",
                    time: "Il y a 5 min",
                    color: AppTheme.primaryBlue
                )
                
                ActivityRow(
                    icon: "doc.badge.plus",
                    title: "Contrat signé",
                    subtitle: "Antoine Dubois - OM",
                    time: "Il y a 2h",
                    color: AppTheme.successGreen
                )
                
                ActivityRow(
                    icon: "calendar",
                    title: "Rendez-vous prévu",
                    subtitle: "Réunion avec PSG - Demain 14h",
                    time: "Il y a 3h",
                    color: AppTheme.warningOrange
                )
            }
        }
    }
    
    // FONCTIONS UTILITAIRES
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }
    
    private func calculateTotalValue() -> String {
        let total = playerManager.players.reduce(0) { sum, player in
            let cleaned = player.marketValue
                .replacingOccurrences(of: "M €", with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: ",", with: ".")
            return sum + (Double(cleaned) ?? 0.0)
        }
        return String(format: "%.1f M", total)
    }
}

// COMPOSANTS SUPPLÉMENTAIRES POUR L'ACCUEIL

// Mini graphique pour le portefeuille
struct MiniChart: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.primaryGradient.opacity(0.1))
                .frame(width: 100, height: 60)
            
            Path { path in
                path.move(to: CGPoint(x: 10, y: 40))
                path.addCurve(
                    to: CGPoint(x: 90, y: 20),
                    control1: CGPoint(x: 30, y: 35),
                    control2: CGPoint(x: 60, y: 25)
                )
            }
            .stroke(AppTheme.primaryGradient, lineWidth: 3)
            .frame(width: 100, height: 60)
        }
    }
}

// Mini indicateur avec icône et valeur
struct MiniIndicator: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.primaryBlue)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.darkNavy)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.darkGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.6))
        )
    }
}

// Ligne d'activité récente
struct ActivityRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let time: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.darkNavy)
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
            
            Spacer()
            
            Text(time)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.mediumGray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow.opacity(0.5), radius: 8, x: 0, y: 4)
        )
    }
}

// ÉCRAN DE LISTE DES JOUEURS
struct PlayersView: View {
    @EnvironmentObject var playerManager: PlayerManager
    @State private var searchText: String = ""
    @State private var selectedStatus: Player.ContractStatus? = nil
    
    private var filteredPlayers: [Player] {
        var list = playerManager.players
        if let status = selectedStatus {
            list = list.filter { $0.contractStatus == status }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter { p in
                p.name.localizedCaseInsensitiveContains(searchText)
                || p.club.localizedCaseInsensitiveContains(searchText)
                || p.position.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Filtres de statut
                    Picker("Statut", selection: $selectedStatus) {
                        Text("Tous").tag(Player.ContractStatus?.none)
                        ForEach(Player.ContractStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(Player.ContractStatus?.some(status))
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    List(filteredPlayers) { player in
                        NavigationLink(destination: PlayerDetailView(player: player)) {
                            PlayerRowView(player: player)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.clear)
                }
            }
            .navigationTitle("Mes joueurs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Ajouter") {
                        // Action d'ajout
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryBlue)
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Rechercher un joueur")
    }
}

// VUE D'UNE LIGNE JOUEUR
struct PlayerRowView: View {
    let player: Player
    
    var body: some View {
        HStack(spacing: 16) {
            Text(player.avatar)
                .font(.system(size: 28))
                .frame(width: 70, height: 70)
                .background(AppTheme.lightGray)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(player.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.darkNavy)
                    
                    Spacer()
                    
                    StatusBadge(status: player.contractStatus)
                }
                
                HStack(spacing: 8) {
                    Text(player.position)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                    
                    Text("•")
                        .foregroundColor(AppTheme.mediumGray)
                    
                    Text(player.club)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                }
                
                Text("Valeur: \(player.marketValue)")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.successGreen.opacity(0.1))
                    .foregroundColor(AppTheme.successGreen)
                    .cornerRadius(8)
            }
            
            VStack(spacing: 4) {
                Text("\(player.documents.count)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.primaryBlue)
                
                Text("docs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
            .padding(12)
            .background(AppTheme.lightGray)
            .cornerRadius(12)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// ÉCRAN DES MESSAGES
struct MessagesView: View {
    @EnvironmentObject var messageManager: MessageManager
    @EnvironmentObject var playerManager: PlayerManager
    @State private var showCompose = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if messageManager.chats.isEmpty {
                        // Écran vide
                        VStack(spacing: 24) {
                            Image(systemName: "message.circle")
                                .font(.system(size: 80, weight: .thin))
                                .foregroundColor(AppTheme.primaryBlue.opacity(0.5))
                            
                            VStack(spacing: 12) {
                                Text("Aucun message")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(AppTheme.darkNavy)
                                
                                Text("Vos conversations avec les joueurs apparaîtront ici")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.darkGray)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Button {
                                showCompose = true
                            } label: {
                                Label("Nouveau message", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(messageManager.chats) { chat in
                            NavigationLink(value: chat) {
                                ChatRowView(chat: chat)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.clear)
                        .refreshable {
                            // Simulation d’un refresh (backend plus tard)
                            try? await Task.sleep(nanoseconds: 800_000_000)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if messageManager.chats.contains(where: { $0.unreadForAgent > 0 }) {
                        Button("Tout marquer lu") {
                            messageManager.markAllAsRead(for: .agent)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCompose = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(AppTheme.primaryBlue)
                    }
                }
            }
            .navigationDestination(for: Chat.self) { chat in
                if let index = messageManager.chats.firstIndex(where: { $0.id == chat.id }) {
                    ChatDetailView(chat: $messageManager.chats[index])
                } else {
                    Text("Conversation introuvable")
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeMessageSheet(
                players: playerManager.players,
                onSend: { player, text in
                    let chat = messageManager.startChat(with: player)
                    messageManager.sendMessage(text, from: .agent, to: chat.id)
                }
            )
        }
    }
}

// VUE D'UNE LIGNE DE CONVERSATION (côté Agent)
struct ChatRowView: View {
    let chat: Chat
    
    var body: some View {
        HStack(spacing: 16) {
            Text(chat.playerAvatar)
                .font(.system(size: 24))
                .frame(width: 60, height: 60)
                .background(AppTheme.lightGray)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(chat.playerName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.darkNavy)
                    
                    Spacer()
                    
                    Text(chat.formattedLastMessageTime)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                }
                
                Text(chat.lastMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                    .lineLimit(2)
            }
            
            VStack {
                if chat.unreadForAgent > 0 {
                    Text("\(chat.unreadForAgent)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(AppTheme.errorRed)
                        .clipShape(Circle())
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// ÉCRAN DE DÉTAIL D'UNE CONVERSATION (synchronisé via Binding) – côté Agent
struct ChatDetailView: View {
    @Binding var chat: Chat
    @State private var messageText = ""
    @EnvironmentObject var messageManager: MessageManager
    @State private var readTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Liste des messages
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(chat.messages) { message in
                        MessageBubbleView(message: message)
                    }
                }
                .padding()
            }
            .background(AppTheme.backgroundGradient)
            
            // Barre de saisie
            HStack(spacing: 16) {
                Button(action: {}) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.primaryBlue)
                }
                
                HStack(spacing: 12) {
                    TextField("Tapez votre message...", text: $messageText)
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    
                    Button(action: { sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(messageText.isEmpty ? AppTheme.mediumGray : AppTheme.primaryBlue)
                    }
                    .disabled(messageText.isEmpty)
                }
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.white)
                        .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                )
            }
            .padding(16)
            .background(AppTheme.lightGray)
        }
        .navigationTitle(chat.playerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if chat.unreadForAgent > 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Marquer lu") {
                        messageManager.markChatAsRead(chatId: chat.id, for: .agent)
                    }
                }
            }
        }
        .onAppear {
            // Marquer comme lu côté Agent avec un léger délai (debounce)
            readTask?.cancel()
            readTask = Task { [chatId = chat.id] in
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
                await MainActor.run {
                    messageManager.markChatAsRead(chatId: chatId, for: .agent)
                }
            }
        }
        .onDisappear {
            readTask?.cancel()
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messageManager.sendMessage(messageText, from: .agent, to: chat.id)
        messageText = ""
    }
}

// BULLE DE MESSAGE
struct MessageBubbleView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.sender == .agent {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.sender == .agent ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 16, weight: .medium))
                    .padding(16)
                    .background(
                        Group {
                            if message.sender == .agent {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(AppTheme.primaryGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                            }
                        }
                        .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3)
                    )
                    .foregroundColor(message.sender == .agent ? .white : AppTheme.darkNavy)
                
                Text(timeFormatter.string(from: message.timestamp))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
            
            if message.sender == .player {
                Spacer(minLength: 60)
            }
        }
    }
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// ÉCRAN DES PARAMÈTRES
struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showLogoutAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient
                    .ignoresSafeArea()
                
                List {
                    // Section Profil
                    Section(header: Text("Profil")) {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(AppTheme.primaryGradient)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text(getInitials())
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(getName())
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.darkNavy)
                                
                                Text(getSubtitle())
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(AppTheme.darkGray)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.white)
                    }
                    
                    // Section Paramètres
                    Section(header: Text("Paramètres")) {
                        SettingsRow(icon: "bell.fill", title: "Notifications", color: AppTheme.warningOrange)
                        SettingsRow(icon: "lock.fill", title: "Confidentialité", color: AppTheme.primaryBlue)
                        SettingsRow(icon: "folder.fill", title: "Stockage", color: AppTheme.successGreen)
                        SettingsRow(icon: "questionmark.circle.fill", title: "Aide", color: AppTheme.primaryBlue)
                    }
                    .listRowBackground(Color.white)
                    
                    // Section Application
                    Section(header: Text("Application")) {
                        SettingsRow(icon: "info.circle.fill", title: "À propos", color: AppTheme.darkGray)
                        
                        Button(action: {
                            showLogoutAlert = true
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "power")
                                    .foregroundColor(AppTheme.errorRed)
                                    .frame(width: 24)
                                    .font(.system(size: 18, weight: .medium))
                                
                                Text("Déconnexion")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppTheme.errorRed)
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.white)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Déconnexion", isPresented: $showLogoutAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Déconnexion", role: .destructive) {
                authManager.logout()
            }
        } message: {
            Text("Êtes-vous sûr de vouloir vous déconnecter ?")
        }
    }
    
    private func getInitials() -> String {
        return String(authManager.currentAgent?.name.prefix(1) ?? "A")
    }
    
    private func getName() -> String {
        return authManager.currentAgent?.name ?? "Agent"
    }
    
    private func getSubtitle() -> String {
        return authManager.currentAgent?.agency ?? "Agence"
    }
}

// LIGNE DES PARAMÈTRES
struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
                .font(.system(size: 18, weight: .medium))
            
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.darkNavy)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(AppTheme.mediumGray)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 4)
    }
}
// ÉTAPE 6 FINALE: INTERFACE COMPLÈTE POUR LES JOUEURS
// Voici tous les écrans spécifiques aux joueurs

// ÉCRAN D'ACCUEIL POUR LES JOUEURS
struct PlayerHomeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var messageManager: MessageManager
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.lightGray, Color.white, AppTheme.lightGray.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        playerHeaderSection
                        careerOverview
                        quickActionsForPlayer
                        recentPerformanceSection
                        upcomingMatchesSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private var playerHeaderSection: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(getGreeting())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                    
                    Text(authManager.currentPlayer?.name ?? "Joueur")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.darkNavy)
                    
                    HStack(spacing: 8) {
                        Text(authManager.currentPlayer?.club ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primaryBlue)
                        Text("•").foregroundColor(AppTheme.mediumGray)
                        Text(authManager.currentPlayer?.position ?? "")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.darkGray)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: {}) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 44, height: 44)
                                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(AppTheme.primaryBlue)
                        }
                    }
                    
                    ZStack {
                        Circle()
                            .fill(AppTheme.primaryGradient)
                            .frame(width: 52, height: 52)
                        let initial = authManager.currentPlayer?.name.prefix(1) ?? "J"
                        Text(String(initial))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: AppTheme.buttonShadow, radius: 10, x: 0, y: 5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 24)
            .background(Color.white.opacity(0.95))
        }
    }
    
    private var careerOverview: some View {
        VStack(spacing: 20) {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VALEUR MARCHANDE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.darkGray)
                            .tracking(1.2)
                        
                        Text(authManager.currentPlayer?.marketValue ?? "€ 0M")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.darkNavy)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                            Text("+8.2%")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(AppTheme.successGreen)
                    }
                    Spacer()
                    PlayerValueChart()
                }
                
                HStack(spacing: 16) {
                    MiniIndicator(
                        icon: "calendar",
                        value: "\(authManager.currentPlayer?.age ?? 0)",
                        label: "Ans"
                    )
                    MiniIndicator(
                        icon: "doc.text.fill",
                        value: getContractStatus(),
                        label: "Contrat"
                    )
                    MiniIndicator(
                        icon: "message.fill",
                        value: "\(messageManager.chats.reduce(0, { $0 + $1.unreadForPlayer }))",
                        label: "Messages"
                    )
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [Color.white, AppTheme.lightGray.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: AppTheme.cardShadow, radius: 20, x: 0, y: 10)
            )
        }
    }
    
    private var quickActionsForPlayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Actions rapides")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    QuickActionCard(
                        icon: "message.fill",
                        title: "Contacter agent",
                        subtitle: "Envoyer un message",
                        color: AppTheme.primaryBlue
                    )
                    QuickActionCard(
                        icon: "doc.badge.plus",
                        title: "Documents",
                        subtitle: "Voir mes fichiers",
                        color: AppTheme.warningOrange
                    )
                    QuickActionCard(
                        icon: "chart.bar.fill",
                        title: "Statistiques",
                        subtitle: "Mes performances",
                        color: AppTheme.successGreen
                    )
                    QuickActionCard(
                        icon: "calendar",
                        title: "Planning",
                        subtitle: "Mes matchs",
                        color: AppTheme.accentGold
                    )
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private var recentPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performances récentes")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                PerformanceCard(title: "Note moyenne", value: "7.2", subtitle: "Derniers matchs", color: AppTheme.accentGold)
                PerformanceCard(title: "Buts", value: "12", subtitle: "Cette saison", color: AppTheme.successGreen)
                PerformanceCard(title: "Minutes", value: "1 840", subtitle: "Jouées", color: AppTheme.primaryBlue)
                PerformanceCard(title: "Passes", value: "86%", subtitle: "Réussies", color: AppTheme.warningOrange)
            }
        }
    }
    
    private var upcomingMatchesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Prochains matchs")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                Spacer()
                Button("Calendrier") {}
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryBlue)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    MatchCard(opponent: "Paris SG", date: "15 DÉC", time: "21:00", venue: "Domicile")
                    MatchCard(opponent: "Marseille", date: "22 DÉC", time: "17:00", venue: "Extérieur")
                    MatchCard(opponent: "Lyon", date: "29 DÉC", time: "20:45", venue: "Domicile")
                }
            }
        }
    }
    
    private func getGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Bonjour"
        case 12..<18: return "Bon après-midi"
        default: return "Bonsoir"
        }
    }
    
    private func getContractStatus() -> String {
        switch authManager.currentPlayer?.contractStatus {
        case .underContract: return "Actif"
        case .negotiating: return "Négo"
        case .free: return "Libre"
        case .none: return "N/A"
        }
    }
}

// COMPOSANTS SPÉCIFIQUES AUX JOUEURS

struct PlayerValueChart: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.primaryGradient.opacity(0.1))
                .frame(width: 100, height: 60)
            Path { path in
                path.move(to: CGPoint(x: 10, y: 45))
                path.addCurve(to: CGPoint(x: 90, y: 15),
                              control1: CGPoint(x: 35, y: 40),
                              control2: CGPoint(x: 65, y: 20))
            }
            .stroke(AppTheme.successGreen, lineWidth: 3)
            .frame(width: 100, height: 60)
        }
    }
}

struct PerformanceCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.successGreen)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.darkNavy)
                Text("\(subtitle) • \(title)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
    }
}

struct MatchCard: View {
    let opponent: String
    let date: String
    let time: String
    let venue: String
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(date)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primaryBlue)
                Text(time)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
            VStack(spacing: 8) {
                Text("vs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                Text(opponent)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Text(venue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.successGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.successGreen.opacity(0.1))
                .cornerRadius(8)
        }
        .frame(width: 140, height: 160)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 5)
        )
    }
}

// ÉCRAN DES STATISTIQUES POUR LES JOUEURS
struct PlayerStatsView: View {
    @State private var selectedSeason = "2024"
    let seasons = ["2024", "2023", "2022"]
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        seasonSelector
                        overallStatsSection
                        performanceChart
                        detailedStatsSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Mes Statistiques")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var seasonSelector: some View {
        HStack {
            Text("Saison")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            Spacer()
            Menu {
                ForEach(seasons, id: \.self) { season in
                    Button(season) {
                        selectedSeason = season
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedSeason).font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AppTheme.primaryBlue)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(AppTheme.primaryBlue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var overallStatsSection: some View {
        VStack(spacing: 20) {
            Text("Vue d'ensemble")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                // Utilisation de StatsCard (alias de StatCard) pour corriger l’erreur
                StatsCard(title: "Buts", value: "12", subtitle: "Cette saison", color: AppTheme.successGreen)
                StatsCard(title: "Passes D.", value: "8", subtitle: "Assists", color: AppTheme.primaryBlue)
                StatsCard(title: "Matchs", value: "23", subtitle: "Joués", color: AppTheme.warningOrange)
                StatsCard(title: "Note moy.", value: "7.4", subtitle: "Performance", color: AppTheme.accentGold)
            }
        }
    }
    
    private var performanceChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Évolution des performances")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            VStack(spacing: 16) {
                HStack {
                    Text("Note par match")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                    Spacer()
                }
                PlayerPerformanceChart().frame(height: 200)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 6)
            )
        }
    }
    
    private var detailedStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistiques détaillées")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.darkNavy)
            VStack(spacing: 12) {
                DetailedStatRow(title: "Minutes jouées", value: "1840'", percentage: 85)
                DetailedStatRow(title: "Tirs cadrés", value: "42", percentage: 68)
                DetailedStatRow(title: "Passes réussies", value: "324", percentage: 86)
                DetailedStatRow(title: "Duels gagnés", value: "156", percentage: 72)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 6)
            )
        }
    }
}

struct PlayerPerformanceChart: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack {
                    ForEach(0..<5) { _ in
                        Rectangle().fill(AppTheme.mediumGray.opacity(0.3)).frame(height: 1)
                        Spacer()
                    }
                }
                Path { path in
                    let points: [(CGFloat, CGFloat)] = [(0.1,0.7),(0.2,0.6),(0.3,0.8),(0.4,0.75),(0.5,0.9),(0.6,0.85),(0.7,0.95),(0.8,0.8),(0.9,0.85)]
                    for (i, point) in points.enumerated() {
                        let x = point.0 * geometry.size.width
                        let y = (1 - point.1) * geometry.size.height
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(AppTheme.primaryBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}

struct DetailedStatRow: View {
    let title: String
    let value: String
    let percentage: Int
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(AppTheme.darkGray)
                Spacer()
                Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(AppTheme.darkNavy)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.lightGray).frame(height: 6).cornerRadius(3)
                    Rectangle().fill(AppTheme.primaryBlue)
                        .frame(width: geometry.size.width * CGFloat(percentage) / 100, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
    }
}

// ÉCRAN DES MESSAGES POUR LES JOUEURS
struct PlayerMessagesView: View {
    @EnvironmentObject var messageManager: MessageManager
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    if messageManager.chats.isEmpty {
                        emptyMessagesView
                    } else {
                        List(messageManager.chats) { chat in
                            if let index = messageManager.chats.firstIndex(where: { $0.id == chat.id }) {
                                NavigationLink(destination: PlayerChatView(chat: $messageManager.chats[index])) {
                                    AgentChatRowView(chat: messageManager.chats[index])
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.clear)
                        .refreshable {
                            // Simulation d’un refresh
                            try? await Task.sleep(nanoseconds: 800_000_000)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if messageManager.chats.contains(where: { $0.unreadForPlayer > 0 }) {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Tout marquer lu") {
                            messageManager.markAllAsRead(for: .player)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyMessagesView: some View {
        VStack(spacing: 24) {
            Image(systemName: "message.circle")
                .font(.system(size: 80, weight: .thin))
                .foregroundColor(AppTheme.primaryBlue.opacity(0.5))
            VStack(spacing: 12) {
                Text("Aucun message")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                Text("Votre agent vous contactera bientôt")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentChatRowView: View {
    let chat: Chat
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(AppTheme.primaryGradient).frame(width: 60, height: 60)
                Text("A").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mon Agent").font(.system(size: 18, weight: .bold)).foregroundColor(AppTheme.darkNavy)
                    Spacer()
                    Text(chat.formattedLastMessageTime).font(.system(size: 12, weight: .medium)).foregroundColor(AppTheme.darkGray)
                }
                Text(chat.lastMessage).font(.system(size: 15, weight: .medium)).foregroundColor(AppTheme.darkGray).lineLimit(2)
            }
            if chat.unreadForPlayer > 0 {
                Text("\(chat.unreadForPlayer)").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .padding(8).background(AppTheme.errorRed).clipShape(Circle())
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4))
        .padding(.horizontal, 16).padding(.vertical, 4)
    }
}

struct PlayerChatView: View {
    @Binding var chat: Chat
    @State private var messageText = ""
    @EnvironmentObject var messageManager: MessageManager
    @State private var readTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(chat.messages) { message in
                        PlayerMessageBubbleView(message: message)
                    }
                }
                .padding()
            }
            .background(AppTheme.backgroundGradient)
            
            HStack(spacing: 16) {
                TextField("Tapez votre message...", text: $messageText)
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 25).fill(Color.white))
                
                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(messageText.isEmpty ? AppTheme.mediumGray : AppTheme.primaryBlue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding(16)
            .background(AppTheme.lightGray)
        }
        .navigationTitle("Mon Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if chat.unreadForPlayer > 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Marquer lu") {
                        messageManager.markChatAsRead(chatId: chat.id, for: .player)
                    }
                }
            }
        }
        .onAppear {
            // Marquer comme lu côté Joueur avec un léger délai
            readTask?.cancel()
            readTask = Task { [chatId = chat.id] in
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
                await MainActor.run {
                    messageManager.markChatAsRead(chatId: chatId, for: .player)
                }
            }
        }
        .onDisappear {
            readTask?.cancel()
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messageManager.sendMessage(messageText, from: .player, to: chat.id)
        messageText = ""
    }
}

struct PlayerMessageBubbleView: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.sender == .player { Spacer(minLength: 60) }
            VStack(alignment: message.sender == .player ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .font(.system(size: 16, weight: .medium))
                    .padding(16)
                    .background(
                        Group {
                            if message.sender == .player {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(AppTheme.primaryGradient)
                            } else {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white)
                            }
                        }
                        .shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3)
                    )
                    .foregroundColor(message.sender == .player ? .white : AppTheme.darkNavy)
                Text(timeFormatter.string(from: message.timestamp))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
            }
            if message.sender == .agent { Spacer(minLength: 60) }
        }
    }
    
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()
}

// ÉCRAN DES DOCUMENTS POUR LES JOUEURS
struct PlayerDocumentsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    var playerDocuments: [Document] { authManager.currentPlayer?.documents ?? [] }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    if playerDocuments.isEmpty {
                        emptyDocumentsView
                    } else {
                        List(playerDocuments) { document in
                            PlayerDocumentRowView(document: document)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .listStyle(PlainListStyle())
                        .background(AppTheme.backgroundGradient)
                    }
                }
            }
            .navigationTitle("Mes Documents")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var emptyDocumentsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.circle")
                .font(.system(size: 80, weight: .thin))
                .foregroundColor(AppTheme.primaryBlue.opacity(0.5))
            VStack(spacing: 12) {
                Text("Aucun document")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                Text("Vos documents apparaîtront ici")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerDocumentRowView: View {
    let document: Document
    
    var categoryColor: Color {
        switch document.category {
        case .contract: return AppTheme.primaryBlue
        case .medical: return AppTheme.errorRed
        case .identity: return AppTheme.successGreen
        case .performance: return AppTheme.warningOrange
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(categoryColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(document.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Text(document.category.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(categoryColor.opacity(0.1))
                        .foregroundColor(categoryColor)
                        .cornerRadius(6)
                    
                    Text(document.size)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                    
                    Spacer()
                }
            }
            
            Button(action: {}) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.primaryBlue)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4))
        .padding(.horizontal, 16).padding(.vertical, 4)
    }
}

// ÉCRAN DE PROFIL POUR LES JOUEURS
struct PlayerProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showLogoutAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        profileHeader
                        profileStats
                        profileSections
                        logoutButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Mon Profil")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Déconnexion", isPresented: $showLogoutAlert) {
            Button("Annuler", role: .cancel) { }
            Button("Déconnexion", role: .destructive) { authManager.logout() }
        } message: {
            Text("Êtes-vous sûr de vouloir vous déconnecter ?")
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: AppTheme.buttonShadow, radius: 15, x: 0, y: 8)
                Text(String(authManager.currentPlayer?.name.prefix(1) ?? "J"))
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(spacing: 12) {
                Text(authManager.currentPlayer?.name ?? "Joueur")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.darkNavy)
                Text(authManager.currentPlayer?.position ?? "Position")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                HStack(spacing: 16) {
                    ProfileInfoChip(icon: "calendar", text: "\(authManager.currentPlayer?.age ?? 0) ans")
                    ProfileInfoChip(icon: "building.2", text: authManager.currentPlayer?.club ?? "Club")
                }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white).shadow(color: AppTheme.cardShadow, radius: 15, x: 0, y: 8))
    }
    
    private var profileStats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ProfileStatItem(title: "Valeur", value: authManager.currentPlayer?.marketValue ?? "0€", color: AppTheme.successGreen)
            ProfileStatItem(title: "Buts", value: "45", color: AppTheme.primaryBlue)
            ProfileStatItem(title: "Matchs", value: "87", color: AppTheme.warningOrange)
        }
    }
    
    private var profileSections: some View {
        VStack(spacing: 16) {
            ProfileSection(title: "Informations", icon: "person.fill") {
                ProfileRow(label: "Email", value: authManager.currentPlayer?.email ?? "", icon: "envelope")
                ProfileRow(label: "Position", value: authManager.currentPlayer?.position ?? "", icon: "location")
                ProfileRow(label: "Club", value: authManager.currentPlayer?.club ?? "", icon: "building.2")
            }
            ProfileSection(title: "Agent", icon: "briefcase.fill") {
                ProfileRow(label: "Agent", value: "Thomas Dubois", icon: "person.badge.shield.checkmark")
                ProfileRow(label: "Agence", value: "Sports Management Pro", icon: "building.columns")
            }
        }
    }
    
    private var logoutButton: some View {
        Button(action: { showLogoutAlert = true }) {
            HStack {
                Image(systemName: "power").font(.system(size: 18, weight: .medium))
                Text("Déconnexion").font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(AppTheme.errorRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(AppTheme.errorRed.opacity(0.1)))
        }
    }
}

// COMPOSANTS SUPPLÉMENTAIRES

struct ProfileInfoChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(AppTheme.primaryBlue)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(AppTheme.primaryBlue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ProfileStatItem: View {
    let title: String
    let value: String
    let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(AppTheme.darkGray)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4))
    }
}

struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundColor(AppTheme.primaryBlue)
                Text(title).font(.system(size: 18, weight: .bold)).foregroundColor(AppTheme.darkNavy)
            }
            VStack(spacing: 1) { content }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4))
        }
    }
}

struct ProfileRow: View {
    let label: String
    let value: String
    let icon: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundColor(AppTheme.primaryBlue).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(AppTheme.darkGray)
                Text(value).font(.system(size: 15, weight: .semibold)).foregroundColor(AppTheme.darkNavy)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - AJOUTS SPÉCIFIQUES AGENT

// Carte compacte pour les contrats à échéance
struct PlayerContractCard: View {
    let player: Player
    let urgencyColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(player.avatar)
                    .font(.system(size: 18))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.lightGray)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.darkNavy)
                    Text(player.club)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.darkGray)
                }
            }
            StatusBadge(status: player.contractStatus)
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .bold))
                Text(etaText(for: player.contractStatus))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(urgencyColor)
        }
        .padding(12)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
        )
    }
    
    private func etaText(for status: Player.ContractStatus) -> String {
        switch status {
        case .free: return "Action immédiate"
        case .negotiating: return "Échéance < 30j (estim.)"
        case .underContract: return "À surveiller"
        }
    }
}

// FAB (Floating Action Button) avec menu
struct FloatingActionMenu<Content: View>: View {
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if isOpen {
                    VStack(alignment: .trailing, spacing: 8) {
                        content()
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .padding(.bottom, 76)
                    .padding(.trailing, 24)
                }
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isOpen.toggle()
                    }
                } label: {
                    Image(systemName: isOpen ? "xmark" : "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(AppTheme.primaryGradient)
                                .shadow(color: AppTheme.buttonShadow, radius: 12, x: 0, y: 6)
                        )
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isOpen)
    }
}

// Feuille de composition de message (agent -> joueur)
struct ComposeMessageSheet: View {
    let players: [Player]
    var onSend: (Player, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlayer: Player?
    @State private var text: String = ""
    @State private var search: String = ""
    
    var filteredPlayers: [Player] {
        if search.trimmingCharacters(in: .whitespaces).isEmpty { return players }
        return players.filter { p in
            p.name.localizedCaseInsensitiveContains(search)
            || p.club.localizedCaseInsensitiveContains(search)
            || p.position.localizedCaseInsensitiveContains(search)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Sélecteur de joueur
                VStack(alignment: .leading, spacing: 8) {
                    Text("Destinataire")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.darkGray)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(AppTheme.darkGray)
                        TextField("Rechercher un joueur", text: $search)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.lightGray))
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredPlayers) { player in
                                Button {
                                    selectedPlayer = player
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(player.avatar)
                                            .font(.system(size: 20))
                                            .frame(width: 36, height: 36)
                                            .background(AppTheme.lightGray)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(player.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppTheme.darkNavy)
                                            Text("\(player.position) • \(player.club)")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(AppTheme.darkGray)
                                        }
                                        Spacer()
                                        if selectedPlayer?.id == player.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(AppTheme.successGreen)
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                // Champ message
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.darkGray)
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white).shadow(color: AppTheme.cardShadow, radius: 6, x: 0, y: 3))
                }
                
                Spacer()
            }
            .padding(16)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Nouveau message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Envoyer") {
                        if let player = selectedPlayer, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend(player, text)
                            dismiss()
                        }
                    }
                    .disabled(selectedPlayer == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - AJOUTS POUR RÉSOUDRE LES ERREURS

// 1) Appliquer un badge uniquement si > 0
extension View {
    @ViewBuilder
    func badgeIf(_ count: Int) -> some View {
        if count > 0 {
            self.badge(count)
        } else {
            self
        }
    }
}

// 2) Vue de détail joueur minimale pour satisfaire les NavigationLink
struct PlayerDetailView: View {
    let player: Player
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(player.avatar)
                    .font(.system(size: 60))
                    .frame(width: 120, height: 120)
                    .background(AppTheme.lightGray)
                    .clipShape(Circle())
                    .padding(.top, 24)
                
                Text(player.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppTheme.darkNavy)
                
                Text("\(player.position) • \(player.club)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.darkGray)
                
                StatusBadge(status: player.contractStatus)
                
                StatCard(title: "Valeur", value: player.marketValue, subtitle: "Estimation", color: AppTheme.successGreen)
            }
            .padding()
        }
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Détail joueur")
        .navigationBarTitleDisplayMode(.inline)
    }
}
