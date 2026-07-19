import SwiftUI

struct BabyMonitorDashboardView: View {
    @ObservedObject var viewModel: BabyMonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                controls
                cameraPreview
                signalGrid
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
                MonitorStateDial(isMonitoring: viewModel.isMonitoring)
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
                colors: [Color(.systemBackground), Color.indigo.opacity(0.10), Color.green.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.indigo.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        VStack(spacing: 12) {
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
            .buttonStyle(ProductionActionButtonStyle(tint: viewModel.isMonitoring ? .orange : .green, isProminent: true))
            .accessibilityIdentifier("button.monitor.toggle")
        }
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Stream")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.captureSnapshot() }
                } label: {
                    Label("Snapshot", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("button.camera.snapshot")
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
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
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
            .accessibilityIdentifier("signal.humidity")

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

struct BackendOperationsView: View {
    @ObservedObject var viewModel: BabyMonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                backendHero
                serviceCommandPanel
                backendOperationsPanel
                readinessPanel
                integrationSummary
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Backend")
        .accessibilityIdentifier("screen.backend")
    }

    private var backendHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: "server.rack")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 52, height: 52)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Service Control Center")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Camera, audio, motion, location, notifications and cloud services coordinated through the local-first architecture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.indigo.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var serviceCommandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operations")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button {
                    Task { await viewModel.requestNotificationReadiness() }
                } label: {
                    Label("Prepare", systemImage: "bell.badge.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .indigo))
                .accessibilityIdentifier("settings.notifications")

                Button {
                    Task { await viewModel.refreshCloudEvents() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .blue))
                .accessibilityIdentifier("backend.sync")

                Button {
                    Task { await viewModel.captureLocationCheckpoint() }
                } label: {
                    Label("Locate", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .mint))
                .accessibilityIdentifier("button.location.checkpoint")

                Button {
                    Task { await viewModel.captureSnapshot() }
                } label: {
                    Label("Snapshot", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .cyan))
                .accessibilityIdentifier("settings.snapshot")
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button(role: .destructive) {
                    Task { await viewModel.simulateCriticalAlert() }
                } label: {
                    Label("Critical", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .red))
                .accessibilityIdentifier("settings.manualCritical")

                Button {
                    Task { await viewModel.simulateAudioAlert() }
                } label: {
                    Label("Audio", systemImage: "waveform.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .orange))
                .accessibilityIdentifier("settings.audioAlert")

                Button {
                    Task { await viewModel.simulateMotionAlert() }
                } label: {
                    Label("Motion", systemImage: "figure.child.and.lock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .teal))
                .accessibilityIdentifier("settings.motionAlert")

                Button {
                    Task { await viewModel.simulateHumidityAlert() }
                } label: {
                    Label("Humidity", systemImage: "humidity.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ProductionActionButtonStyle(tint: .cyan))
                .accessibilityIdentifier("settings.humidityAlert")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("panel.backend.commands")
    }

    private var backendOperationsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Backend Operations")
                        .font(.headline)
                    Text("Local-first service mesh")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BackendStatusPill(
                    title: viewModel.cloudIsAvailable ? "Online" : "Offline",
                    systemImage: viewModel.cloudIsAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    tint: viewModel.cloudIsAvailable ? .green : .orange
                )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                BackendFunctionTile(
                    title: "APNs",
                    value: viewModel.pushAuthorizationState.title,
                    detail: viewModel.deviceTokenSummary,
                    systemImage: "bell.and.waves.left.and.right.fill",
                    tint: .indigo,
                    identifier: "backend.apns"
                )
                BackendFunctionTile(
                    title: "CloudKit",
                    value: viewModel.cloudIsAvailable ? "Ready" : "Offline",
                    detail: viewModel.cloudStatusMessage,
                    systemImage: "icloud.fill",
                    tint: .blue,
                    identifier: "readiness.cloud"
                )
                BackendFunctionTile(
                    title: "Watch",
                    value: viewModel.watchState.title,
                    detail: "Escalation channel",
                    systemImage: "applewatch.radiowaves.left.and.right",
                    tint: .orange,
                    identifier: "backend.watch"
                )
                BackendFunctionTile(
                    title: "HomeKit",
                    value: viewModel.homeAutomationIsAvailable ? "Ready" : "Optional",
                    detail: viewModel.homeAutomationStatusMessage,
                    systemImage: "homekit",
                    tint: .purple,
                    identifier: "backend.homekit"
                )
                BackendFunctionTile(
                    title: "Date & Time",
                    value: viewModel.currentDateTimeSummary,
                    detail: "Apple device clock",
                    systemImage: "clock.fill",
                    tint: .pink,
                    identifier: "backend.datetime"
                )
                BackendFunctionTile(
                    title: "Location",
                    value: viewModel.snapshot.location.state.title,
                    detail: viewModel.locationDetail,
                    systemImage: "location.fill",
                    tint: .mint,
                    identifier: "backend.location"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
        .accessibilityIdentifier("panel.backend.operations")
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Readiness")
                .font(.headline)

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
                    identifier: "readiness.cloud.status"
                )
                ReadinessTile(
                    title: "HomeKit",
                    value: viewModel.homeAutomationIsAvailable ? "Ready" : "Optional",
                    detail: viewModel.homeAutomationStatusMessage,
                    systemImage: "homekit",
                    tint: viewModel.homeAutomationIsAvailable ? .purple : .secondary,
                    identifier: "readiness.home"
                )
                ReadinessTile(
                    title: "Location",
                    value: viewModel.snapshot.location.state.title,
                    detail: viewModel.locationDetail,
                    systemImage: "location.fill",
                    tint: viewModel.snapshot.location.state == .active ? .mint : .secondary,
                    identifier: "readiness.location"
                )
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var integrationSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Integration State")
                .font(.headline)
            LabeledContent("Status", value: viewModel.statusMessage)
            LabeledContent("Monitoring", value: viewModel.isMonitoring ? "Running" : "Paused")
            LabeledContent("Device token", value: viewModel.deviceTokenSummary)
            LabeledContent("CloudKit", value: viewModel.cloudStatusMessage)
            Text(viewModel.cloudStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.cloud.status")
            LabeledContent("Location", value: viewModel.locationSummary)
            Text(viewModel.locationDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.location.status")
        }
        .font(.subheadline)
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
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

private struct MonitorStateDial: View {
    let isMonitoring: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isMonitoring ? Color.green.opacity(0.16) : Color.gray.opacity(0.14))
                .frame(width: 58, height: 58)
            Circle()
                .strokeBorder(isMonitoring ? Color.green.opacity(0.45) : Color.secondary.opacity(0.18), lineWidth: 1)
                .frame(width: 58, height: 58)
            Image(systemName: isMonitoring ? "sensor.tag.radiowaves.forward.fill" : "sensor.tag.radiowaves.forward")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(isMonitoring ? .green : .secondary)
        }
        .accessibilityIdentifier("monitor.state.dial")
    }
}

private struct BackendStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct BackendFunctionTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer(minLength: 4)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

private struct ProductionActionButtonStyle: ButtonStyle {
    let tint: Color
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .foregroundStyle(isProminent ? .white : tint)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isProminent ? tint : tint.opacity(0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(isProminent ? 0 : 0.20), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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
        case .location: "location"
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
            Section("Preferences") {
                Toggle("Low light attention alerts", isOn: $viewModel.alertConfiguration.lowLightEscalates)
                LabeledContent("Noise threshold", value: "\(Int(viewModel.alertConfiguration.noiseThreshold * 100))%")
                LabeledContent("Stillness threshold", value: "\(Int(viewModel.alertConfiguration.stillnessThreshold * 100))%")
                LabeledContent("Humidity range", value: "\(Int(viewModel.alertConfiguration.lowHumidityPercent))-\(Int(viewModel.alertConfiguration.highHumidityPercent))%")
            }

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
                LabeledContent("Date & time", value: viewModel.currentDateTimeSummary)
                LabeledContent("Location", value: viewModel.locationSummary)
                Text(viewModel.locationDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.location.status")
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
