import SwiftUI
import UserNotifications

// MARK: - Enhanced Notification Manager
@MainActor
class EnhancedNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var hasPermission = false
    @Published var badgeCount = 0
    @Published var pendingNotifications: [PendingNotification] = []
    
    static let shared = EnhancedNotificationManager()
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        loadPendingNotifications()
    }
    
    // MARK: - Permission Management
    func requestPermission() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional, .criticalAlert]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            hasPermission = granted
            
            if granted {
                await registerForRemoteNotifications()
            }
        } catch {
            print("Erreur demande permission notifications: \(error)")
        }
    }
    
    @MainActor
    private func registerForRemoteNotifications() async {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    // MARK: - Smart Notifications
    func scheduleSmartContractReminder(for player: Player) {
        let daysUntilExpiry = calculateDaysUntilContractExpiry(for: player)
        
        // Notifications échelonnées
        let notificationSchedule = [
            (days: 30, title: "⚠️ Contrat à renouveler bientôt"),
            (days: 14, title: "🔔 Renouvellement de contrat urgent"),
            (days: 7, title: "🚨 Contrat expire dans une semaine"),
            (days: 1, title: "🔥 URGENT: Contrat expire demain!")
        ]
        
        for schedule in notificationSchedule {
            if daysUntilExpiry > schedule.days {
                scheduleNotification(
                    id: "contract-\(player.id.uuidString)-\(schedule.days)",
                    title: schedule.title,
                    body: "Le contrat de \(player.name) expire dans \(schedule.days) jour(s)",
                    timeInterval: TimeInterval((daysUntilExpiry - schedule.days) * 24 * 60 * 60),
                    category: .contractReminder,
                    userInfo: ["playerId": player.id.uuidString, "type": "contract", "daysRemaining": schedule.days]
                )
            }
        }
    }
    
    func schedulePerformanceAlert(for player: Player, achievement: String) {
        scheduleNotification(
            id: "performance-\(UUID().uuidString)",
            title: "⚽ Performance exceptionnelle!",
            body: "\(player.name): \(achievement)",
            timeInterval: 1,
            category: .performance,
            userInfo: ["playerId": player.id.uuidString, "type": "performance"]
        )
    }
    
    func scheduleMarketValueUpdate(for player: Player, oldValue: String, newValue: String) {
        let isIncrease = extractValue(from: newValue) > extractValue(from: oldValue)
        let emoji = isIncrease ? "📈" : "📉"
        
        scheduleNotification(
            id: "market-value-\(player.id.uuidString)",
            title: "\(emoji) Valeur marchande mise à jour",
            body: "\(player.name): \(oldValue) → \(newValue)",
            timeInterval: 1,
            category: .marketUpdate,
            userInfo: ["playerId": player.id.uuidString, "type": "market_value"]
        )
    }
    
    // MARK: - Interactive Notifications
    private func setupNotificationCategories() {
        let contractCategory = UNNotificationCategory(
            identifier: NotificationCategory.contractReminder.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_CONTRACT",
                    title: "Voir contrat",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "SCHEDULE_MEETING",
                    title: "Programmer RDV",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "REMIND_LATER",
                    title: "Rappel + tard",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let messageCategory = UNNotificationCategory(
            identifier: NotificationCategory.message.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: "REPLY",
                    title: "Répondre",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "MARK_READ",
                    title: "Marquer lu",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let performanceCategory = UNNotificationCategory(
            identifier: NotificationCategory.performance.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_STATS",
                    title: "Voir stats",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "SHARE",
                    title: "Partager",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            contractCategory,
            messageCategory,
            performanceCategory
        ])
    }
    
    private func scheduleNotification(
        id: String,
        title: String,
        body: String,
        timeInterval: TimeInterval,
        category: NotificationCategory,
        userInfo: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: badgeCount + 1)
        content.categoryIdentifier = category.rawValue
        content.userInfo = userInfo
        
        // Ajouter un attachment si approprié
        if category == .performance {
            if let attachment = createImageAttachment(for: "trophy") {
                content.attachments = [attachment]
            }
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeInterval), repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erreur programmation notification: \(error)")
            } else {
                DispatchQueue.main.async {
                    self.addPendingNotification(PendingNotification(
                        id: id,
                        title: title,
                        body: body,
                        scheduledDate: Date().addingTimeInterval(timeInterval),
                        category: category
                    ))
                }
            }
        }
    }
    
    // MARK: - Notification Management
    private func loadPendingNotifications() {
        Task {
            let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let notifications = requests.map { request in
                PendingNotification(
                    id: request.identifier,
                    title: request.content.title,
                    body: request.content.body,
                    scheduledDate: (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() ?? Date(),
                    category: NotificationCategory(rawValue: request.content.categoryIdentifier) ?? .general
                )
            }
            
            await MainActor.run {
                self.pendingNotifications = notifications.sorted { $0.scheduledDate < $1.scheduledDate }
            }
        }
    }
    
    private func addPendingNotification(_ notification: PendingNotification) {
        pendingNotifications.append(notification)
        pendingNotifications.sort { $0.scheduledDate < $1.scheduledDate }
    }
    
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        pendingNotifications.removeAll { $0.id == id }
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        pendingNotifications.removeAll()
    }
    
    // MARK: - Utility Functions
    private func calculateDaysUntilContractExpiry(for player: Player) -> Int {
        // Logique pour calculer les jours avant expiration
        // Pour l'exemple, on simule
        switch player.contractStatus {
        case .underContract: return 60
        case .negotiating: return 15
        case .free: return 0
        }
    }
    
    private func extractValue(from marketValue: String) -> Double {
        let cleaned = marketValue
            .replacingOccurrences(of: "M €", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0.0
    }
    
    private func createImageAttachment(for imageName: String) -> UNNotificationAttachment? {
        guard let imageURL = Bundle.main.url(forResource: imageName, withExtension: "png") else {
            return nil
        }
        
        do {
            return try UNNotificationAttachment(identifier: imageName, url: imageURL, options: nil)
        } catch {
            print("Erreur création attachment: \(error)")
            return nil
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        
        switch actionIdentifier {
        case "VIEW_CONTRACT":
            if let playerId = userInfo["playerId"] as? String {
                // Navigation vers le contrat du joueur
                NotificationCenter.default.post(
                    name: .openPlayerContract,
                    object: nil,
                    userInfo: ["playerId": playerId]
                )
            }
            
        case "SCHEDULE_MEETING":
            NotificationCenter.default.post(name: .openCalendar, object: nil)
            
        case "REPLY":
            NotificationCenter.default.post(name: .openMessages, object: nil)
            
        case "VIEW_STATS":
            if let playerId = userInfo["playerId"] as? String {
                NotificationCenter.default.post(
                    name: .openPlayerStats,
                    object: nil,
                    userInfo: ["playerId": playerId]
                )
            }
            
        case UNNotificationDefaultActionIdentifier:
            // Action par défaut (tap sur la notification)
            handleDefaultNotificationAction(userInfo: userInfo)
            
        default:
            break
        }
        
        // Supprimer la notification des pending si elle a été traitée
        if let id = userInfo["notificationId"] as? String {
            cancelNotification(id: id)
        }
        
        completionHandler()
    }
    
    private func handleDefaultNotificationAction(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        
        switch type {
        case "contract":
            NotificationCenter.default.post(name: .openPlayers, object: nil)
        case "message":
            NotificationCenter.default.post(name: .openMessages, object: nil)
        case "performance":
            if let playerId = userInfo["playerId"] as? String {
                NotificationCenter.default.post(
                    name: .openPlayerStats,
                    object: nil,
                    userInfo: ["playerId": playerId]
                )
            }
        case "market_value":
            NotificationCenter.default.post(name: .openPlayers, object: nil)
        default:
            break
        }
    }
}

// MARK: - Supporting Types
enum NotificationCategory: String, CaseIterable {
    case contractReminder = "CONTRACT_REMINDER"
    case message = "MESSAGE"
    case performance = "PERFORMANCE"
    case marketUpdate = "MARKET_UPDATE"
    case general = "GENERAL"
    
    var displayName: String {
        switch self {
        case .contractReminder: return "Rappels de contrat"
        case .message: return "Messages"
        case .performance: return "Performances"
        case .marketUpdate: return "Valeurs marchandes"
        case .general: return "Général"
        }
    }
}

struct PendingNotification: Identifiable {
    let id: String
    let title: String
    let body: String
    let scheduledDate: Date
    let category: NotificationCategory
}

// MARK: - Notification Names Extension
extension Notification.Name {
    static let openPlayerContract = Notification.Name("openPlayerContract")
    static let openPlayerStats = Notification.Name("openPlayerStats")
    static let openMessages = Notification.Name("openMessages")
    static let openPlayers = Notification.Name("openPlayers")
    static let openCalendar = Notification.Name("openCalendar")
}

// MARK: - Notification Settings View
struct NotificationSettingsView: View {
    @ObservedObject var notificationManager = EnhancedNotificationManager.shared
    @State private var contractReminders = true
    @State private var messageNotifications = true
    @State private var performanceAlerts = true
    @State private var marketUpdates = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Types de notifications")) {
                    NotificationToggleRow(
                        icon: "doc.text.fill",
                        title: "Rappels de contrat",
                        subtitle: "Alertes avant expiration des contrats",
                        isOn: $contractReminders,
                        color: .orange
                    )
                    
                    NotificationToggleRow(
                        icon: "message.fill",
                        title: "Messages",
                        subtitle: "Nouveaux messages des joueurs",
                        isOn: $messageNotifications,
                        color: .blue
                    )
                    
                    NotificationToggleRow(
                        icon: "star.fill",
                        title: "Performances",
                        subtitle: "Performances exceptionnelles",
                        isOn: $performanceAlerts,
                        color: .green
                    )
                    
                    NotificationToggleRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Valeurs marchandes",
                        subtitle: "Changements de valeur marchande",
                        isOn: $marketUpdates,
                        color: .purple
                    )
                }
                
                Section(header: Text("Notifications programmées")) {
                    if notificationManager.pendingNotifications.isEmpty {
                        Text("Aucune notification programmée")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(notificationManager.pendingNotifications) { notification in
                            PendingNotificationRow(
                                notification: notification,
                                onCancel: {
                                    notificationManager.cancelNotification(id: notification.id)
                                }
                            )
                        }
                    }
                }
                
                Section {
                    Button("Effacer toutes les notifications") {
                        notificationManager.cancelAllNotifications()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Notifications")
        }
    }
}

struct PendingNotificationRow: View {
    let notification: PendingNotification
    let onCancel: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(notification.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Text(notification.scheduledDate, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Annuler") {
                onCancel()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}