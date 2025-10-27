import SwiftUI

// MARK: - Navigation Coordinator
@MainActor
class NavigationCoordinator: ObservableObject {
    @Published var selectedTab: MainTab = .home
    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: Sheet?
    @Published var showingAlert = false
    @Published var alertInfo: AlertInfo?
    
    enum MainTab: String, CaseIterable {
        case home = "Accueil"
        case messages = "Messages"
        case players = "Joueurs"
        case calendar = "Agenda"
        case settings = "Paramètres"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .messages: return "message.fill"
            case .players: return "person.3.fill"
            case .calendar: return "calendar.fill"
            case .settings: return "gear"
            }
        }
    }
    
    enum Sheet: Identifiable {
        case addPlayer
        case editPlayer(Player)
        case addDocument
        case settings
        case profile
        
        var id: String {
            switch self {
            case .addPlayer: return "addPlayer"
            case .editPlayer(let player): return "editPlayer-\(player.id)"
            case .addDocument: return "addDocument"
            case .settings: return "settings"
            case .profile: return "profile"
            }
        }
    }
    
    struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let primaryButton: AlertButton?
        let secondaryButton: AlertButton?
        
        struct AlertButton {
            let title: String
            let action: () -> Void
            let style: ButtonStyle
            
            enum ButtonStyle {
                case `default`
                case cancel
                case destructive
            }
        }
    }
    
    // MARK: - Navigation Actions
    func navigate(to destination: any Hashable) {
        navigationPath.append(destination)
    }
    
    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    func navigateToRoot() {
        navigationPath = NavigationPath()
    }
    
    func presentSheet(_ sheet: Sheet) {
        presentedSheet = sheet
    }
    
    func dismissSheet() {
        presentedSheet = nil
    }
    
    func showAlert(title: String, message: String, primaryButton: AlertInfo.AlertButton? = nil, secondaryButton: AlertInfo.AlertButton? = nil) {
        alertInfo = AlertInfo(
            title: title,
            message: message,
            primaryButton: primaryButton,
            secondaryButton: secondaryButton
        )
        showingAlert = true
    }
    
    // MARK: - Deep Links
    func handleDeepLink(_ url: URL) {
        // Gérer les liens profonds
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        
        switch components.path {
        case "/player":
            if let playerIdString = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let playerId = UUID(uuidString: playerIdString) {
                // Navigation vers le joueur spécifique
                navigate(to: playerId)
            }
        case "/messages":
            selectedTab = .messages
        case "/calendar":
            selectedTab = .calendar
        default:
            break
        }
    }
}

// MARK: - Enhanced TabView
struct EnhancedTabView: View {
    @StateObject private var coordinator = NavigationCoordinator()
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var errorManager: ErrorManager
    
    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            ForEach(NavigationCoordinator.MainTab.allCases, id: \.self) { tab in
                NavigationStack(path: $coordinator.navigationPath) {
                    destinationView(for: tab)
                        .navigationDestination(for: UUID.self) { playerId in
                            // Navigation vers profil joueur
                            if let player = findPlayer(by: playerId) {
                                PlayerProfileView(player: player)
                            }
                        }
                }
                .tabItem {
                    Image(systemName: tab.icon)
                    Text(tab.rawValue)
                }
                .tag(tab)
            }
        }
        .environmentObject(coordinator)
        .sheet(item: $coordinator.presentedSheet) { sheet in
            sheetView(for: sheet)
        }
        .alert(item: $coordinator.alertInfo) { alertInfo in
            Alert(
                title: Text(alertInfo.title),
                message: Text(alertInfo.message),
                primaryButton: alertInfo.primaryButton.map { button in
                    switch button.style {
                    case .default:
                        return .default(Text(button.title), action: button.action)
                    case .cancel:
                        return .cancel(Text(button.title), action: button.action)
                    case .destructive:
                        return .destructive(Text(button.title), action: button.action)
                    }
                } ?? .default(Text("OK")),
                secondaryButton: alertInfo.secondaryButton.map { button in
                    switch button.style {
                    case .default:
                        return .default(Text(button.title), action: button.action)
                    case .cancel:
                        return .cancel(Text(button.title), action: button.action)
                    case .destructive:
                        return .destructive(Text(button.title), action: button.action)
                    }
                }
            )
        }
    }
    
    @ViewBuilder
    private func destinationView(for tab: NavigationCoordinator.MainTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .messages:
            MessagesView()
        case .players:
            PlayersView()
        case .calendar:
            CalendarView()
        case .settings:
            SettingsView()
        }
    }
    
    @ViewBuilder
    private func sheetView(for sheet: NavigationCoordinator.Sheet) -> some View {
        switch sheet {
        case .addPlayer:
            AddPlayerView()
        case .editPlayer(let player):
            EditPlayerView(player: player)
        case .addDocument:
            AddDocumentView()
        case .settings:
            SettingsView()
        case .profile:
            ProfileView()
        }
    }
    
    private func findPlayer(by id: UUID) -> Player? {
        // Implementation pour trouver un joueur par ID
        return nil
    }
}

// Placeholder views
struct CalendarView: View {
    var body: some View {
        Text("Calendar View")
            .navigationTitle("Agenda")
    }
}

struct AddPlayerView: View {
    var body: some View {
        Text("Add Player View")
    }
}

struct EditPlayerView: View {
    let player: Player
    var body: some View {
        Text("Edit Player View")
    }
}

struct AddDocumentView: View {
    var body: some View {
        Text("Add Document View")
    }
}

struct ProfileView: View {
    var body: some View {
        Text("Profile View")
    }
}