// Core/AppContainer.swift
import Foundation

final class AppContainer {
    let authService: AuthenticationServiceProtocol

    init(backend: BackendFlavor = AppConfig.backend) {
        switch backend {
        case .mock:
            self.authService = InMemoryAuthenticationService()
        case .firebase:
            // À brancher plus tard: self.authService = FirebaseAuthenticationService()
            self.authService = InMemoryAuthenticationService()
        }
    }
}
