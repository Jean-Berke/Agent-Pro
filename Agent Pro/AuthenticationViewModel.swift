// Features/Auth/AuthenticationViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class AuthenticationViewModel: ObservableObject {
    // États observables (mêmes noms qu’avant pour ne rien casser dans l’UI)
    @Published var isAuthenticated = false
    @Published var showOnboarding = true
    @Published var showUserTypeSelection = false
    @Published var userType: UserType?
    @Published var currentAgent: Agent?
    @Published var currentPlayer: Player?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: AuthenticationServiceProtocol

    init(service: AuthenticationServiceProtocol) {
        self.service = service
    }

    func checkAuthenticationStatus() {
        // Mode démo: toujours déconnecté au démarrage
        showOnboarding = true
        isAuthenticated = false
        showUserTypeSelection = false
        userType = nil
    }

    func completeOnboarding() {
        showOnboarding = false
        showUserTypeSelection = true
    }

    func selectUserType(_ type: UserType) {
        userType = type
        showUserTypeSelection = false
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await service.login(email: email, password: password)
            apply(session: session)
        } catch {
            Logger.error("Login error: \(error.localizedDescription)", category: "auth")
            errorMessage = (error as? AppError)?.userMessage ?? "Échec de la connexion."
            isAuthenticated = false
        }
        isLoading = false
    }

    func register(name: String, email: String, agency: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await service.registerAgent(name: name, email: email, agency: agency, password: password)
            apply(session: session)
        } catch {
            Logger.error("Register agent error: \(error.localizedDescription)", category: "auth")
            errorMessage = (error as? AppError)?.userMessage ?? "Échec de l’inscription."
        }
        isLoading = false
    }

    func loginPlayer(email: String, password: String) async {
        await login(email: email, password: password)
    }

    func registerPlayer(name: String, email: String, position: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let session = try await service.registerPlayer(name: name, email: email, position: position, password: password)
            apply(session: session)
        } catch {
            Logger.error("Register player error: \(error.localizedDescription)", category: "auth")
            errorMessage = (error as? AppError)?.userMessage ?? "Échec de l’inscription."
        }
        isLoading = false
    }

    func logout() {
        Task { await service.logout() }
        currentAgent = nil
        currentPlayer = nil
        userType = nil
        isAuthenticated = false
        showUserTypeSelection = true
    }

    // MARK: - Helpers

    private func apply(session: UserSession) {
        self.userType = session.userType
        self.currentAgent = session.agent
        self.currentPlayer = session.player
        self.isAuthenticated = true
        self.showOnboarding = false
        self.showUserTypeSelection = false
    }
}
