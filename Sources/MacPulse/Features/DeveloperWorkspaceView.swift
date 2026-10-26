import SwiftUI

struct DeveloperView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var readings: [DeveloperToolReading] = []
    @State private var checking = false
    @State private var error: String?
    @State private var inspectionTask: Task<Void, Never>?
    @State private var processService = DeveloperProcessService()
    @State private var processes: [DeveloperProcessReading] = []
    @State private var processTask: Task<Void, Never>?
    @State private var checkingProcesses = false
    @State private var didCheckProcesses = false
    @State private var selectedProcess: DeveloperProcessReading?

    var body: some View {
        PageScrollView {
            pageHeader(.developerIntegration, subtitle: .developerIntegrationDetails)
            SurfaceCard {
                AdaptiveStack {
                    Text(localization.workflow(.developerVersions)).font(.headline).frame(
                        maxWidth: .infinity, alignment: .leading)
                    Button(localization.workflow(.refreshVersions)) { checkVersions() }
                        .buttonStyle(.borderedProminent).disabled(checking)
                        .accessibilityIdentifier("developer.check-versions")
                    if checking {
                        Button(localization.workflow(.cancelWork)) { inspectionTask?.cancel() }.buttonStyle(.bordered)
                    }
                }
                if checking { ProgressView(localization.workflow(.developerChecking)) }
                if let error { InfoNote(text: error, symbol: "exclamationmark.triangle") }
                InfoNote(text: localization.workflow(.developerReadOnly), symbol: "lock.shield")
            }
            LazyVStack(spacing: 12) {
                ForEach(DeveloperToolID.allCases) { tool in
                    DeveloperReadingRow(tool: tool, reading: readings.first { $0.id == tool })
                }
            }
            processContent
            Button(localization.workflow(.viewStorage)) { model.selectedSection = "Storage" }.buttonStyle(.bordered)
            InfoNote(text: localization.text(.developerIntegrationLimitations))
        }
        .navigationTitle(localization.text(.developerTools))
        .onDisappear {
            inspectionTask?.cancel()
            processTask?.cancel()
        }
        .onChange(of: model.operation) { old, new in
            if old == .applying && new == .idle && didCheckProcesses { inspectProcesses() }
        }
        .confirmationDialog(
            localization.workflow(.stopProcess),
            isPresented: Binding(
                get: { selectedProcess != nil }, set: { if !$0 { selectedProcess = nil } }
            ), titleVisibility: .visible
        ) {
            Button(localization.workflow(.stopProcess), role: .destructive) {
                if let selectedProcess { model.requestDeveloperStop(selectedProcess) }
                selectedProcess = nil
            }
            Button(localization.text(.cancel), role: .cancel) { selectedProcess = nil }
        } message: {
            Text(localization.workflow(.stopProcessWarning))
        }
    }

    private func checkVersions() {
        guard !checking else { return }
        checking = true
        error = nil
        inspectionTask = Task {
            defer {
                checking = false
                inspectionTask = nil
            }
            do { readings = try await DeveloperInspectionService().inspect() } catch is CancellationError {
                error = localization.workflow(.operationCancelled)
            } catch { self.error = error.localizedDescription }
        }
    }

    private var processContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                AdaptiveStack {
                    Text(localization.workflow(.developerProcesses)).font(.headline).frame(
                        maxWidth: .infinity, alignment: .leading)
                    Button(localization.workflow(.inspectProcesses)) { inspectProcesses() }
                        .buttonStyle(.bordered).disabled(checkingProcesses)
                }
                InfoNote(text: localization.workflow(.cpuPerCore))
                if checkingProcesses {
                    ProgressView()
                    Button(localization.workflow(.cancelWork)) { processTask?.cancel() }
                }
            }
            if model.operation == .applying { ExecutionProgressCard() }
            if didCheckProcesses && processes.isEmpty && !checkingProcesses {
                InfoNote(text: localization.workflow(.noDeveloperProcesses))
            }
            ForEach(processes) { process in
                SurfaceCard(padding: 16) {
                    AdaptiveStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(process.name) · PID \(process.pid)").font(.headline)
                            Text(
                                "\(formatBytes(process.memoryBytes)) · CPU \(process.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")"
                            )
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(localization.workflow(.stopProcess)) { selectedProcess = process }
                            .buttonStyle(.bordered).disabled(model.isBusy)
                    }
                    Text(process.executablePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func inspectProcesses() {
        guard !checkingProcesses else { return }
        checkingProcesses = true
        processTask = Task {
            defer {
                checkingProcesses = false
                processTask = nil
            }
            do {
                processes = try await processService.inspect()
                didCheckProcesses = true
            } catch is CancellationError { error = localization.workflow(.operationCancelled) } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct DeveloperReadingRow: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    let tool: DeveloperToolID
    let reading: DeveloperToolReading?

    var body: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                IconTile(symbol: tool == .docker ? "shippingbox" : "terminal", size: 36)
                Text(tool.displayName).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text(status).font(.caption).foregroundStyle(reading?.status == .available ? .green : .secondary)
            }
            if let version = reading?.version { Text(version).font(.callout.monospaced()).textSelection(.enabled) }
            if let path = reading?.executablePath {
                Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button(localization.workflow(.revealFinder)) { model.reveal(URL(fileURLWithPath: path)) }.buttonStyle(
                    .borderless)
            }
            if let detail = reading?.detail, !detail.isEmpty {
                DisclosureGroup(localization.workflow(.details)) { Text(detail).font(.caption).textSelection(.enabled) }
            }
            if let docker = reading?.docker {
                Divider()
                if docker.isRunning {
                    LabeledContent(
                        localization.workflow(.runningContainers), value: String(docker.runningContainers ?? 0))
                    LabeledContent(
                        localization.workflow(.stoppedContainers), value: String(docker.stoppedContainers ?? 0))
                    LabeledContent(localization.workflow(.dockerImages), value: String(docker.images ?? 0))
                    if let memory = docker.memoryBytes {
                        LabeledContent(localization.text(.memoryState), value: formatBytes(memory))
                    }
                } else {
                    InfoNote(text: localization.workflow(.developerUnavailable))
                    if let detail = docker.detail, !detail.isEmpty {
                        DisclosureGroup(localization.workflow(.details)) {
                            Text(detail).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var status: String {
        guard let reading else { return localization.workflow(.notChecked) }
        switch reading.status {
        case .available: return localization.text(.available)
        case .notFound: return localization.text(.notFound)
        case .timedOut: return localization.workflow(.developerTimeout)
        case .failed: return localization.workflow(.developerUnavailable)
        }
    }
}
