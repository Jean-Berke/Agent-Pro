// Services/Protocols/AuthenticationServiceProtocol.swift
import Foundation

protocol AuthenticationServiceProtocol {
    func currentSession() async -> UserSession?
    func login(email: String, password: String) async throws -> UserSession
    func registerAgent(name: String, email: String, agency: String, password: String) async throws -> UserSession
    func registerPlayer(name: String, email: String, position: String, password: String) async throws -> UserSession
    func logout() async
}
