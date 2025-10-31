// Core/AppError.swift
import Foundation

enum AppError: Error, LocalizedError, Equatable {
    case invalidCredentials
    case userNotFound
    case network
    case decoding
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Identifiants invalides."
        case .userNotFound: return "Utilisateur introuvable."
        case .network: return "Problème réseau. Réessayez."
        case .decoding: return "Erreur de lecture des données."
        case .unknown(let msg): return msg
        }
    }

    var userMessage: String {
        errorDescription ?? "Une erreur est survenue."
    }
}
