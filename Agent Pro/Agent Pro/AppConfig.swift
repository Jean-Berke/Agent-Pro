// Core/AppConfig.swift
import Foundation

enum BackendFlavor {
    case mock
    case firebase
}

enum AppConfig {
    // On garde mock pour l’instant. On passera à .firebase plus tard.
    static var backend: BackendFlavor = .mock
}
