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
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        
        switch components.path {
        case "/player":
            if let playerIdString = components.queryItems?.first(where: { $0.name == "id" })?.value,
               let playerId = UUID(uuidString: playerIdString) {
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
    // Ces EnvironmentObjects sont utilisés par les vues réelles si elles sont présentes dans le projet
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            ForEach(NavigationCoordinator.MainTab.allCases, id: \.self) { tab in
                NavigationStack(path: $coordinator.navigationPath) {
                    destinationView(for: tab)
                        .navigationDestination(for: UUID.self) { playerId in
                            // Placeholder de navigation vers un joueur
                            PlayerDetailsPlaceholder(playerId: playerId)
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
        .alert(item: $coordinator.alertInfo) { info in
            buildAlert(from: info)
        }
    }
    
    // MARK: - Destinations par onglet
    @ViewBuilder
    private func destinationView(for tab: NavigationCoordinator.MainTab) -> some View {
        switch tab {
        case .home:
            // Placeholder HomeView pour éviter la dépendance à une vue non fournie
            HomePlaceholderView()
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
    
    // MARK: - Feuilles
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
    
    // MARK: - Helpers
    private func buildAlert(from info: NavigationCoordinator.AlertInfo) -> Alert {
        // Si deux boutons fournis
        if let primary = info.primaryButton, let secondary = info.secondaryButton {
            return Alert(
                title: Text(info.title),
                message: Text(info.message),
                primaryButton: mapAlertButton(primary),
                secondaryButton: mapAlertButton(secondary)
            )
        }
        // Si un seul bouton fourni
        if let primary = info.primaryButton {
            return Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: mapAlertButton(primary)
            )
        }
        // Sinon, bouton OK par défaut
        return Alert(
            title: Text(info.title),
            message: Text(info.message),
            dismissButton: .default(Text("OK"))
        )
    }
    
    private func mapAlertButton(_ button: NavigationCoordinator.AlertInfo.AlertButton) -> Alert.Button {
        switch button.style {
        case .default:
            return .default(Text(button.title), action: button.action)
        case .cancel:
            return .cancel(Text(button.title), action: button.action)
        case .destructive:
            return .destructive(Text(button.title), action: button.action)
        }
    }
}

// Placeholder views pour éviter les dépendances manquantes

struct HomePlaceholderView: View {
    var body: some View {
        Text("Accueil")
            .font(.title)
            .padding()
            .navigationTitle("Accueil")
    }
}

struct PlayerDetailsPlaceholder: View {
    let playerId: UUID
    var body: some View {
        VStack(spacing: 12) {
            Text("Détail Joueur")
                .font(.title2)
            Text(playerId.uuidString)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .navigationTitle("Joueur")
    }
}

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
            .navigationTitle(player.name)
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
