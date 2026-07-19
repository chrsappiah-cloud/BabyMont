//
//  ContentView.swift
//  BabyMont
//
//  Created by Christopher Appiah-Thompson  on 19/7/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = BabyMonitorViewModel()
    @State private var didConfigure = false

    var body: some View {
        TabView {
            NavigationStack {
                BabyMonitorDashboardView(viewModel: viewModel)
            }
            .tabItem {
                Label("Monitor", systemImage: "sensor.tag.radiowaves.forward")
            }
            .accessibilityIdentifier("tab.monitor")

            NavigationStack {
                EventHistoryView(viewModel: viewModel)
            }
            .tabItem {
                Label("Events", systemImage: "list.bullet.rectangle")
            }
            .accessibilityIdentifier("tab.events")

            NavigationStack {
                AlertRulesView(configuration: $viewModel.alertConfiguration)
            }
            .tabItem {
                Label("Rules", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("tab.rules")

            NavigationStack {
                MonitorSettingsView(viewModel: viewModel)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("tab.settings")
        }
        .accessibilityIdentifier("root.tabView")
        .onAppear {
            guard !didConfigure else { return }
            didConfigure = true
            let dependencies: AppDependencies = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? .preview
                : .live(modelContext: modelContext)
            viewModel.configure(dependencies: dependencies)
        }
    }
}

#Preview {
    do {
        let container = try ModelContainer(
            for: BabyEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ContentView()
            .modelContainer(container)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
