import SwiftUI

struct BabyMonitorDashboardView: View {
    @ObservedObject var viewModel: BabyMonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                controls
                readinessPanel
                cameraPreview
                signalGrid
                alertRules
                eventTimeline
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("BabyMont")
        .accessibilityIdentifier("screen.monitor")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BabyMont Nursery Command")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(viewModel.isMonitoring ? Color.green.opacity(0.16) : Color.gray.opacity(0.14))
                        .frame(width: 54, height: 54)
                    Image(systemName: viewModel.isMonitoring ? "sensor.tag.radiowaves.forward.fill" : "sensor.tag.radiowaves.forward")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(viewModel.isMonitoring ? .green : .secondary)
                }
            }

            HStack(spacing: 10) {
                BadgeLabel(title: "Private", systemImage: "lock.shield", tint: .green)
                BadgeLabel(title: "APNs", systemImage: "bell.badge", tint: .indigo)
                BadgeLabel(title: "Watch", systemImage: "applewatch.radiowaves.left.and.right", tint: .orange)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.green.opacity(0.08), Color.indigo.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if viewModel.isMonitoring {
                        viewModel.stopMonitoring()
                    } else {
                        await viewModel.startMonitoring()
                    }
                }
            } label: {
                Label(viewModel.isMonitoring ? "Pause" : "Start", systemImage: viewModel.isMonitoring ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("button.monitor.toggle")

            Button {
                Task { await viewModel.requestNotificationReadiness() }
            } label: {
                Label("APNs", systemImage: "bell.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("button.apns.readiness")

            Button {
                Task { await viewModel.simulateCriticalAlert() }
            } label: {
                Label("Test", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("button.test.alert")
        }
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Production Readiness")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.refreshCloudEvents() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("button.cloud.sync")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ReadinessTile(
                    title: "Camera",
                    value: viewModel.snapshot.camera.state.title,
                    detail: "\(viewModel.snapshot.camera.capturedFrameCount) frames",
                    systemImage: "video.fill",
                    tint: viewModel.snapshot.camera.state == .active ? .green : .secondary
                )
                ReadinessTile(
                    title: "Audio",
                    value: viewModel.snapshot.audio.state.title,
                    detail: viewModel.snapshot.audio.classification.title,
                    systemImage: "waveform",
                    tint: viewModel.snapshot.audio.state == .active ? .orange : .secondary
                )
                ReadinessTile(
                    title: "CloudKit",
                    value: viewModel.cloudIsAvailable ? "Ready" : "Offline",
                    detail: viewModel.cloudStatusMessage,
                    systemImage: "icloud.fill",
                    tint: viewModel.cloudIsAvailable ? .blue : .secondary,
                    identifier: "readiness.cloud"
                )
                ReadinessTile(
                    title: "HomeKit",
                    value: viewModel.homeAutomationIsAvailable ? "Ready" : "Optional",
                    detail: viewModel.homeAutomationStatusMessage,
                    systemImage: "homekit",
                    tint: viewModel.homeAutomationIsAvailable ? .purple : .secondary,
                    identifier: "readiness.home"
                )
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Stream")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.captureSnapshot()
                } label: {
                    Label("Snapshot", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            }

            if let session = viewModel.cameraSession {
                CameraPreviewView(session: session)
                    .frame(height: 210)
                    .overlay(alignment: .bottomLeading) {
                        Text("Occupancy \(Int(viewModel.snapshot.camera.occupancyConfidence * 100))%")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("Camera unavailable", systemImage: "video.slash")
                    .frame(height: 180)
                    .accessibilityIdentifier("camera.unavailable")
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var signalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            SignalCard(
                title: "Camera",
                value: "\(Int(viewModel.snapshot.camera.occupancyConfidence * 100))%",
                detail: "\(viewModel.snapshot.camera.state.title) - \(Int(viewModel.snapshot.camera.frameRate)) fps",
                systemImage: "video.fill",
                tint: .indigo,
                progress: max(viewModel.snapshot.camera.occupancyConfidence, min(viewModel.snapshot.camera.frameRate / 30, 1) * 0.15)
            )

            SignalCard(
                title: "Audio",
                value: viewModel.snapshot.audio.classification.title,
                detail: "\(Int(viewModel.snapshot.audio.classificationConfidence * 100))% - \(Int(viewModel.snapshot.audio.sustainedNoiseSeconds)) sec",
                systemImage: "waveform",
                tint: .orange,
                progress: max(viewModel.snapshot.audio.decibels, viewModel.snapshot.audio.classificationConfidence)
            )

            SignalCard(
                title: "Motion",
                value: "\(Int(viewModel.snapshot.motion.activityScore * 100))%",
                detail: "\(Int(viewModel.snapshot.motion.sustainedStillnessSeconds)) sec still",
                systemImage: "figure.child",
                tint: .teal,
                progress: viewModel.snapshot.motion.activityScore
            )

            SignalCard(
                title: "Humidity",
                value: viewModel.snapshot.humidity.relativePercent.map { "\(Int($0))%" } ?? "--",
                detail: viewModel.snapshot.humidity.relativePercent == nil ? "No sensor paired" : "relative humidity",
                systemImage: "humidity.fill",
                tint: .cyan,
                progress: min((viewModel.snapshot.humidity.relativePercent ?? 0) / 100, 1)
            )

            SignalCard(
                title: "Alerts",
                value: "\(viewModel.activeAlerts.count)",
                detail: "rule matches",
                systemImage: "shield.lefthalf.filled.badge.checkmark",
                tint: viewModel.activeAlerts.isEmpty ? .green : .red,
                progress: viewModel.activeAlerts.isEmpty ? 0.15 : 1
            )
        }
    }

    private var alertRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alert Rules")
                .font(.headline)

            VStack(spacing: 12) {
                SliderRow(
                    title: "Noise threshold",
                    value: $viewModel.alertConfiguration.noiseThreshold,
                    range: 0.1...1,
                    identifier: "slider.noise.threshold"
                )
                SliderRow(
                    title: "Stillness threshold",
                    value: $viewModel.alertConfiguration.stillnessThreshold,
                    range: 0...0.5,
                    identifier: "slider.stillness.threshold"
                )
                SliderRow(
                    title: "Low humidity",
                    value: $viewModel.alertConfiguration.lowHumidityPercent,
                    range: 15...45,
                    format: .wholeNumber,
                    identifier: "slider.humidity.low"
                )
                SliderRow(
                    title: "High humidity",
                    value: $viewModel.alertConfiguration.highHumidityPercent,
                    range: 55...80,
                    format: .wholeNumber,
                    identifier: "slider.humidity.high"
                )
                Toggle("Low light attention alerts", isOn: $viewModel.alertConfiguration.lowLightEscalates)
                    .accessibilityIdentifier("toggle.lowLight")
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var eventTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Event Store")
                .font(.headline)

            if viewModel.recentEvents.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "tray", description: Text("Start monitoring to store local events on this device."))
                    .accessibilityIdentifier("events.empty")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.recentEvents) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BadgeLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct ReadinessTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    var identifier: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "readiness.\(title.lowercased())")
    }
}

private struct SignalCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(.headline)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            ProgressView(value: progress)
                .tint(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SliderRow: View {
    enum ValueFormat {
        case percent
        case wholeNumber
    }

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: ValueFormat = .percent
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(displayValue)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Slider(value: $value, in: range)
                .accessibilityIdentifier(identifier ?? "slider.\(title)")
        }
    }

    private var displayValue: String {
        switch format {
        case .percent:
            "\(Int(value * 100))%"
        case .wholeNumber:
            "\(Int(value))%"
        }
    }
}

private struct EventRow: View {
    let event: BabyEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("event.row.\(event.category.rawValue).\(event.severity.rawValue)")
    }

    private var color: Color {
        switch event.severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }

    private var iconName: String {
        switch event.category {
        case .camera: "video"
        case .audio: "waveform"
        case .motion: "figure.child"
        case .temperature: "thermometer.medium"
        case .humidity: "humidity"
        case .alert: "exclamationmark.triangle"
        case .watch: "applewatch"
        case .system: "gearshape"
        }
    }
}

struct EventHistoryView: View {
    @ObservedObject var viewModel: BabyMonitorViewModel

    var body: some View {
        List {
            if viewModel.recentEvents.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "tray", description: Text("Start monitoring to store local events on this device."))
                    .accessibilityIdentifier("events.history.empty")
            } else {
                ForEach(viewModel.recentEvents) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(event.title)
                                .font(.headline)
                            Spacer()
                            Text(event.severity.title)
                                .font(.caption.weight(.semibold))
                        }
                        Text(event.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(event.category.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("events.history.row.\(event.category.rawValue).\(event.severity.rawValue)")
                }
            }
        }
        .navigationTitle("Events")
        .accessibilityIdentifier("screen.events")
    }
}

struct AlertRulesView: View {
    @Binding var configuration: AlertRuleConfiguration

    var body: some View {
        Form {
            Section("Sound") {
                SliderRow(title: "Noise threshold", value: $configuration.noiseThreshold, range: 0.1...1, identifier: "rules.noise.threshold")
                SliderRow(title: "Stillness threshold", value: $configuration.stillnessThreshold, range: 0...0.5, identifier: "rules.stillness.threshold")
            }

            Section("Environment") {
                SliderRow(title: "Low humidity", value: $configuration.lowHumidityPercent, range: 15...45, format: .wholeNumber, identifier: "rules.humidity.low")
                SliderRow(title: "High humidity", value: $configuration.highHumidityPercent, range: 55...80, format: .wholeNumber, identifier: "rules.humidity.high")
                Text(configuration.lowLightEscalates ? "Low light alerts enabled" : "Low light alerts disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rules.lowLight.state")
                Toggle("Low light attention alerts", isOn: $configuration.lowLightEscalates)
                    .accessibilityIdentifier("rules.lowLight")
                Button {
                    configuration.lowLightEscalates.toggle()
                } label: {
                    Label(
                        configuration.lowLightEscalates ? "Disable low light alerts" : "Enable low light alerts",
                        systemImage: configuration.lowLightEscalates ? "eye.slash" : "eye"
                    )
                }
                .accessibilityIdentifier("rules.lowLight.button")
            }
        }
        .navigationTitle("Rules")
        .accessibilityIdentifier("screen.rules")
    }
}

struct MonitorSettingsView: View {
    @ObservedObject var viewModel: BabyMonitorViewModel

    var body: some View {
        Form {
            Section("Readiness") {
                LabeledContent("Status", value: viewModel.statusMessage)
                LabeledContent("Monitoring", value: viewModel.isMonitoring ? "Running" : "Paused")
                LabeledContent("Notifications", value: viewModel.pushAuthorizationState.title)
                LabeledContent("Device token", value: viewModel.deviceTokenSummary)
                LabeledContent("CloudKit", value: viewModel.cloudStatusMessage)
                Text(viewModel.cloudStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.cloud.status")
                LabeledContent("HomeKit", value: viewModel.homeAutomationStatusMessage)
                LabeledContent("Watch", value: viewModel.watchState.title)
            }

            Section("Actions") {
                Button {
                    Task { await viewModel.requestNotificationReadiness() }
                } label: {
                    Label("Prepare Notifications", systemImage: "bell.badge")
                }
                .accessibilityIdentifier("settings.notifications")

                Button {
                    Task { await viewModel.refreshCloudEvents() }
                } label: {
                    Label("Refresh Cloud Events", systemImage: "icloud.and.arrow.down")
                }
                .accessibilityIdentifier("settings.cloud.refresh")

                Button(role: .destructive) {
                    Task { await viewModel.simulateCriticalAlert() }
                } label: {
                    Label("Send Manual Critical Test", systemImage: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("settings.manualCritical")

                Button {
                    Task { await viewModel.simulateAudioAlert() }
                } label: {
                    Label("Send Audio Alert Test", systemImage: "waveform.badge.exclamationmark")
                }
                .accessibilityIdentifier("settings.audioAlert")

                Button {
                    Task { await viewModel.simulateMotionAlert() }
                } label: {
                    Label("Send Motion Alert Test", systemImage: "figure.child.and.lock")
                }
                .accessibilityIdentifier("settings.motionAlert")

                Button {
                    Task { await viewModel.simulateHumidityAlert() }
                } label: {
                    Label("Send Humidity Alert Test", systemImage: "humidity.fill")
                }
                .accessibilityIdentifier("settings.humidityAlert")
            }
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("screen.settings")
    }
}

#Preview {
    NavigationStack {
        BabyMonitorDashboardView(viewModel: BabyMonitorViewModel())
    }
}
