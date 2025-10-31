import Foundation
import SwiftUI
import os.log

// MARK: - Analytics Events
enum AnalyticsEvent {
    case screenView(screenName: String)
    case userAction(action: String, parameters: [String: Any]?)
    case error(error: Error, context: String)
    case performance(metric: String, value: Double)
    case userFlow(step: String, flowName: String)
    
    var eventName: String {
        switch self {
        case .screenView: return "screen_view"
        case .userAction: return "user_action"
        case .error: return "error"
        case .performance: return "performance"
        case .userFlow: return "user_flow"
        }
    }
    
    var parameters: [String: Any] {
        switch self {
        case .screenView(let screenName):
            return ["screen_name": screenName]
        case .userAction(let action, let parameters):
            var params: [String: Any] = ["action": action]
            if let additionalParams = parameters {
                params.merge(additionalParams) { _, new in new }
            }
            return params
        case .error(let error, let context):
            return [
                "error_description": error.localizedDescription,
                "context": context,
                "error_type": String(describing: type(of: error))
            ]
        case .performance(let metric, let value):
            return [
                "metric": metric,
                "value": value
            ]
        case .userFlow(let step, let flowName):
            return [
                "step": step,
                "flow_name": flowName
            ]
        }
    }
}

// MARK: - Analytics Manager
class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()
    
    // Utiliser explicitement os.Logger pour éviter un conflit de nom
    private let logger = os.Logger(subsystem: "com.agentpro.app", category: "Analytics")
    private var sessionId: String = UUID().uuidString
    private var sessionStartTime: Date = Date()
    
    private init() {
        startSession()
    }
    
    // MARK: - Session Management
    private func startSession() {
        sessionId = UUID().uuidString
        sessionStartTime = Date()
        track(.userAction(action: "session_start", parameters: [
            "session_id": sessionId,
            "timestamp": sessionStartTime.timeIntervalSince1970
        ]))
    }
    
    func endSession() {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        track(.performance(metric: "session_duration", value: sessionDuration))
        track(.userAction(action: "session_end", parameters: [
            "session_id": sessionId,
            "duration": sessionDuration
        ]))
    }
    
    // MARK: - Event Tracking
    func track(_ event: AnalyticsEvent) {
        var parameters = event.parameters
        parameters["session_id"] = sessionId
        parameters["timestamp"] = Date().timeIntervalSince1970
        
        // Log locally for debugging
        logger.info("\(event.eventName): \(String(describing: parameters))")
        
        // Send to analytics service (implementation dépendant du service choisi)
        sendToAnalyticsService(eventName: event.eventName, parameters: parameters)
    }
    
    private func sendToAnalyticsService(eventName: String, parameters: [String: Any]) {
        // TODO: Intégrer avec Firebase Analytics, Mixpanel, etc.
        // Pour l'instant, on log juste
        print("📊 Analytics: \(eventName) - \(parameters)")
    }
    
    // MARK: - Convenience Methods
    func trackScreenView(_ screenName: String) {
        track(.screenView(screenName: screenName))
    }
    
    func trackUserAction(_ action: String, parameters: [String: Any]? = nil) {
        track(.userAction(action: action, parameters: parameters))
    }
    
    func trackError(_ error: Error, context: String) {
        track(.error(error: error, context: context))
    }
    
    func trackPerformance(metric: String, value: Double) {
        track(.performance(metric: metric, value: value))
    }
    
    // MARK: - User Properties
    func setUserProperty(_ value: String, forName name: String) {
        // TODO: Set user property in analytics service
        print("👤 User Property: \(name) = \(value)")
    }
    func setUserId(_ userId: String) {
        // TODO: Set user ID in analytics service
        print("👤 User ID: \(userId)")
    }
}

// MARK: - Performance Monitor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    private var timers: [String: Date] = [:]
    
    private init() {}
    
    func startTimer(for operation: String) {
        timers[operation] = Date()
    }
    
    func endTimer(for operation: String) {
        guard let startTime = timers[operation] else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        timers.removeValue(forKey: operation)
        
        AnalyticsManager.shared.trackPerformance(
            metric: "\(operation)_duration",
            value: duration
        )
        
        // Log slow operations
        if duration > 2.0 { // Plus de 2 secondes
            print("⚠️ Slow operation: \(operation) took \(duration)s")
        }
    }
    
    func measure<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        startTimer(for: operation)
        defer { endTimer(for: operation) }
        return try block()
    }
    
    func measureAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
        startTimer(for: operation)
        defer { endTimer(for: operation) }
        return try await block()
    }
}

// MARK: - ViewModifier for Screen Tracking
struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AnalyticsManager.shared.trackScreenView(screenName)
            }
    }
}

extension View {
    func trackScreen(_ screenName: String) -> some View {
        modifier(ScreenTrackingModifier(screenName: screenName))
    }
}
