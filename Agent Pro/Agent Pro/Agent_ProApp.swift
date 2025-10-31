//
//  Agent_ProApp.swift
//  Agent Pro
//
//  Created by Jean-Berké Akdogan on 09/09/2025.
//

import SwiftUI


struct Agent_ProApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
