//
//  BabyMontApp.swift
//  BabyMont
//
//  Created by Christopher Appiah-Thompson  on 19/7/2026.
//

import SwiftUI
import SwiftData

@main
struct BabyMontApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BabyEvent.self,
        ])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
