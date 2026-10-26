import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var largeFileFolders: [FolderFileGroup] = []
    @State private var duplicateFileFolders: [DuplicateFolderGroup] = []
    private var tab: StorageTab { StorageTab(rawValue: model.storageMode) ?? .caches }

    var body: some View {
        PageScrollView {
            pageHeader(.storageAnalysis, subtitle: .storageIntro)
            if let storage = model.snapshot?.storage, storage.totalBytes > 0 {
                StorageCapacityCard(storage: storage) { model.openTrash() }
            }
            StorageCategoryPicker(selection: $model.storageMode)
            if let notice = model.workflowNotice { InfoNote(text: localization.workflow(notice)) }
            if model.operation == .applying { ExecutionProgressCard() }
            if tab == .caches { cacheContent } else { fileContent }
        }
        .navigationTitle(localization.text(.storage))
        .onChange(of: model.fileResult?.scanID, initial: true) { _, _ in
            guard let result = model.fileResult else {
                largeFileFolders = []
                duplicateFileFolders = []
                return
            }
            largeFileFolders = groupScannedFilesByParent(result.largeFiles)
            duplicateFileFolders = groupDuplicateFilesByParent(result.duplicateGroups)
        }
    }

    private var cacheContent: some View {
        Group {
            SurfaceCard {
                AdaptiveStack {
                    StorageScanHeading(
                        title: localization.text(.cacheScan), detail: localization.workflow(.storageCacheIntro),
                        symbol: "folder.badge.gearshape")
                    Button {
                        model.startCacheScan()
                    } label: {
                        Label(
                            localization.text(model.isScanning ? .scanning : .scanCaches),
                            systemImage: "magnifyingglass")
                    }.buttonStyle(StoragePrimaryButtonStyle()).disabled(model.isBusy)
                        .accessibilityIdentifier("storage.scan-caches")
                }
                if model.isScanning {
                    Divider()
                    Text(localization.text(.scanning)).font(.callout).foregroundStyle(.secondary)
                    ScanCancellationRow()
                } else if model.cacheCandidates.isEmpty {
                    StorageEmptyState(
                        title: model.cacheScanCompleted ? localization.workflow(.scanEmpty) : localization.workflow(.storageReadyTitle),
                        detail: model.cacheScanCompleted ? localization.workflow(.storageReadOnly) : localization.workflow(.storageReadyDetail),
                        symbol: model.cacheScanCompleted ? "checkmark.circle" : "externaldrive")
                }
                InfoNote(text: localization.workflow(.storageProtectedHint), symbol: "lock.shield")
            }
            if !model.cacheCandidates.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(localization.workflow(.storageResults)).font(.headline)
                    Spacer(minLength: 12)
                    Text(localization.workflow(.storageCacheSummaryCount, model.cacheCandidates.count,
                        formatBytes(model.cacheCandidates.reduce(UInt64.zero) { $0 + $1.allocatedBytes })))
                        .font(.caption).foregroundStyle(.secondary)
                }
                SelectionReviewBar(count: model.selectedCaches.count, disabled: model.isBusy) {
                    model.prepareCacheCleanup()
                }
                LazyVStack(spacing: 12) {
                    ForEach(model.cacheCandidates) { candidate in
                        CacheSelectionRow(candidate: candidate, selection: $model.selectedCaches)
                    }
                }
            }
            InfoNote(text: localization.workflow(.trashWarning), symbol: "lock.shield")
        }
    }

    private var fileContent: some View {
        Group {
            SurfaceCard {
                StorageScanHeading(
                    title: localization.workflow(tab == .large ? .scanLargeFiles : .scanDuplicates),
                    detail: localization.workflow(tab == .large ? .storageLargeIntro : .storageDuplicateIntro),
                    symbol: tab.symbol)
                if let root = model.scanRoot {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.workflow(.storageFolderLabel)).font(.caption).foregroundStyle(.secondary)
                            Text(root.path).font(.callout).textSelection(.enabled)
                                .lineLimit(2).truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                } else {
                    StorageEmptyState(title: localization.workflow(.chooseFolder),
                        detail: localization.workflow(.folderPrompt), symbol: "folder.badge.plus")
                }
                AdaptiveStack(breakpoint: 760, spacing: 12) {
                    Button(localization.workflow(.chooseFolder)) { Task { await model.chooseScanFolder() } }
                        .buttonStyle(.bordered).controlSize(.large).disabled(model.isBusy)
                        .accessibilityIdentifier("storage.choose-folder")
                    if tab == .large {
                        Picker(
                            localization.workflow(.largeThreshold),
                            selection: Binding(
                                get: { model.minimumLargeFileMiB }, set: { model.updateLargeThreshold($0) }
                            )
                        ) {
                            ForEach([10, 50, 100, 500, 1024], id: \.self) { Text("\($0) MiB").tag($0) }
                        }.disabled(model.isBusy).controlSize(.large)
                    }
                    Button(localization.workflow(tab == .large ? .scanLargeFiles : .scanDuplicates)) {
                        model.startFileScan()
                    }
                    .buttonStyle(StoragePrimaryButtonStyle()).disabled(model.scanRoot == nil || model.isBusy)
                    .accessibilityIdentifier("storage.scan-files")
                }
                if model.operation == .fileScan {
                    if let progress = model.fileScanProgress {
                        FileAnalysisProgress(progress: progress)
                    }
                    ScanCancellationRow()
                }
            }
            if let result = model.fileResult {
                Text(localization.workflow(.scannedSummary, result.scannedCount, result.skippedCount))
                    .font(.caption).foregroundStyle(.secondary)
                if result.stoppedAtLimit && model.operation != .fileScan {
                    InfoNote(
                        text: localization.workflow(.fileLimitReached, FileDiscoveryService.fileLimit),
                        symbol: "exclamationmark.triangle")
                } else if !result.isComplete && model.operation != .fileScan {
                    InfoNote(text: localization.workflow(.scanSkipped), symbol: "exclamationmark.triangle")
                }
                if model.operation == .fileScan && tab == .large && model.activeFileScanMode == .combined {
                    InfoNote(text: localization.workflow(.largeResultsReady))
                }
                if tab == .large { largeResults(result) } else { duplicateResults(result) }
            }
            InfoNote(text: localization.workflow(.fileCleanupWarning), symbol: "hand.raised")
        }
    }

    private func largeResults(_ result: FileDiscoveryResult) -> some View {
        let keepers = Set(result.duplicateGroups.map { model.duplicateKeeper(for: $0).url })
        return VStack(spacing: 12) {
            SelectionReviewBar(count: model.selectedLargeFiles.count, disabled: model.isBusy) {
                model.prepareFileCleanup(duplicates: false)
            }
            if result.largeFiles.isEmpty {
                Text(localization.workflow(.noLargeFiles)).foregroundStyle(.secondary).padding(24)
            }
            if !largeFileFolders.isEmpty {
                Text(localization.workflow(.bulkSelectionKeepsCopy))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                folderAggregate(largeFileFolders)
                InfoNote(text: localization.workflow(.folderSelectionHint), symbol: "folder")
            }
            LazyVStack(spacing: 10) {
                ForEach(largeFileFolders) { folder in
                    FolderFileGroupCard(
                        group: folder, selection: model.selectedLargeFiles, excluded: keepers,
                        disabled: model.isBusy,
                        onSetSelected: { selected in model.setLargeFileGroup(folder.files, selected: selected) }
                    ) {
                        ForEach(folder.files) { file in
                            FileSelectionRow(file: file, selection: $model.selectedLargeFiles, retained: false)
                            if file.id != folder.files.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func duplicateResults(_ result: FileDiscoveryResult) -> some View {
        if !result.duplicatesScanned {
            InfoNote(
                text: localization.workflow(
                    model.operation == .fileScan ? .duplicateVerificationPending : .duplicateScanNeeded),
                symbol: "doc.text.magnifyingglass")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                InfoNote(text: localization.workflow(.keepAtLeastOne), symbol: "doc.on.doc")
                SelectionReviewBar(count: model.selectedDuplicates.count, disabled: model.isBusy) {
                    model.prepareFileCleanup(duplicates: true)
                }
                if result.duplicateGroups.isEmpty {
                    Text(localization.workflow(.noDuplicates)).foregroundStyle(.secondary).padding(24)
                }
                folderAggregate(duplicateFileFolders.map(\.folderGroup))
                InfoNote(text: localization.workflow(.folderSelectionHint), symbol: "folder")
                LazyVStack(spacing: 12) {
                    ForEach(duplicateFileFolders) { folder in
                        let keepers = Set(folder.duplicateGroups.map { model.duplicateKeeper(for: $0).url })
                        FolderFileGroupCard(
                            group: folder.folderGroup, selection: model.selectedDuplicates, excluded: keepers,
                            disabled: model.isBusy,
                            onSetSelected: { selected in
                                let eligible = folder.folderGroup.files.filter { !$0.isProtected && !keepers.contains($0.url) }
                                if selected {
                                    model.selectedDuplicates.formUnion(eligible.map(\.url))
                                } else {
                                    model.selectedDuplicates.subtract(eligible.map(\.url))
                                }
                            }
                        ) {
                            ForEach(folder.folderGroup.files) { file in
                                FileSelectionRow(file: file, selection: $model.selectedDuplicates,
                                    retained: keepers.contains(file.url))
                                if let group = folder.duplicateGroupByFile[file.url],
                                   model.duplicateKeeper(for: group).url != file.url {
                                    Button(localization.workflow(.keepThisCopy)) {
                                        model.keepDuplicate(file, in: group)
                                    }
                                    .buttonStyle(.borderless).disabled(model.isBusy)
                                }
                                if file.id != folder.folderGroup.files.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func folderAggregate(_ folders: [FolderFileGroup]) -> some View {
        let fileCount = folders.reduce(0) { $0 + $1.files.count }
        let bytes = folders.reduce(UInt64.zero) { total, folder in
            let sum = total.addingReportingOverflow(folder.totalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
        return HStack {
            Text(localization.workflow(.storageResults)).font(.headline)
            Spacer(minLength: 12)
            Text(localization.workflow(.storageFolderFilesAggregate, folders.count, fileCount, formatBytes(bytes)))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

}

private struct FileAnalysisProgress: View {
    @EnvironmentObject private var localization: LocalizationStore
    let progress: FileDiscoveryProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(localization.workflow(stageKey)).font(.callout.weight(.medium))
            if progress.stage != .enumerating {
                Text(localization.workflow(.parallelWorkers, progress.workerLimit))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let name = progress.currentFileName {
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Text(localization.workflow(.listedSummary, progress.scannedCount, progress.skippedCount))
                .font(.caption).foregroundStyle(.secondary)
            if progress.stage == .fingerprinting && progress.candidateFiles > 0 {
                ProgressView(value: Double(progress.completedCandidates), total: Double(progress.candidateFiles))
                Text(localization.workflow(.candidatesProgress, progress.completedCandidates, progress.candidateFiles))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else if progress.stage == .hashing && progress.totalHashBytes > 0 {
                ProgressView(
                    value: Double(min(progress.hashedBytes + progress.reusedHashBytes, progress.totalHashBytes)),
                    total: Double(progress.totalHashBytes))
                Text(
                    localization.workflow(
                        .reusedHashProgress, formatBytes(progress.hashedBytes), formatBytes(progress.reusedHashBytes),
                        formatBytes(progress.totalHashBytes))
                )
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else if progress.stage == .verifying {
                Text(localization.workflow(.comparedBytesProgress, formatBytes(progress.verifiedBytes)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if progress.stoppedAtLimit {
                InfoNote(
                    text: localization.workflow(.fileLimitReached, FileDiscoveryService.fileLimit),
                    symbol: "exclamationmark.triangle")
            }
        }
    }

    private var stageKey: WorkflowKey {
        switch progress.stage {
        case .enumerating: .scanEnumerating
        case .fingerprinting: .precheckingFiles
        case .hashing: .scanHashing
        case .verifying: .scanVerifying
        }
    }
}

struct CacheSelectionRow: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    let candidate: CleanupCandidate
    @Binding var selection: Set<URL>

    var body: some View {
        let rejection = model.cacheRejection(candidate)
        SurfaceCard(padding: 16) {
            Toggle(
                isOn: Binding(
                    get: { selection.contains(candidate.url) },
                    set: {
                        if $0 { selection.insert(candidate.url) } else { selection.remove(candidate.url) }
                    })
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(candidate.displayName).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(formatBytes(candidate.allocatedBytes)).font(.callout.monospacedDigit())
                }
            }.toggleStyle(.checkbox).disabled(rejection != nil || model.isBusy)
                .accessibilityIdentifier("cache.select.\(candidate.displayName)")
            if let rejection {
                InfoNote(text: localization.workflow(cacheRejectionKey(rejection)), symbol: "lock.shield")
            } else {
                InfoNote(text: localization.text(.cacheCandidateDetail))
            }
            Button(localization.workflow(.revealFinder)) { model.reveal(candidate.url) }.buttonStyle(.borderless)
        }
    }
}

struct FileSelectionRow: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    let file: ScannedFile
    @Binding var selection: Set<URL>
    let retained: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { !retained && selection.contains(file.url) },
                    set: {
                        if $0 && !retained { selection.insert(file.url) } else { selection.remove(file.url) }
                    })
            ) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.url.lastPathComponent).font(.headline).lineLimit(2)
                    Text("\(formatBytes(file.logicalBytes)) · \(file.url.pathExtension.uppercased())")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }.toggleStyle(.checkbox).disabled(retained || file.isProtected || model.isBusy)
                .accessibilityIdentifier("file.select.\(file.url.path)")
            if file.isProtected { InfoNote(text: localization.workflow(.protectedFile), symbol: "lock.shield") }
            Text(file.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                "\(localization.workflow(.modified)): \(Date(timeIntervalSince1970: Double(file.stamp.modificationSeconds)).formatted(date: .abbreviated, time: .shortened))"
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack {
                if retained { StatusPill(text: localization.workflow(.retainedCopy), color: .green) }
                Button(localization.workflow(.revealFinder)) { model.reveal(file.url) }.buttonStyle(.borderless)
            }
        }
    }
}

struct SelectionReviewBar: View {
    @EnvironmentObject private var localization: LocalizationStore
    let count: Int
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        SurfaceCard(padding: 16) {
            AdaptiveStack(breakpoint: 560, spacing: 12) {
                Label(localization.workflow(.selectedCount, count), systemImage: "checkmark.circle")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: action) {
                    Label(localization.workflow(.previewSelected), systemImage: "arrow.forward")
                }
                .accessibilityIdentifier("storage.review-selected")
                .buttonStyle(StoragePrimaryButtonStyle()).disabled(count == 0 || disabled)
            }
        }
    }
}

struct ScanCancellationRow: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    var body: some View {
        HStack {
            ProgressView().controlSize(.small)
            Spacer()
            Button(localization.workflow(.cancelWork)) { model.cancelOperation() }.buttonStyle(.bordered)
        }
    }
}

func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
}

func cacheRejectionKey(_ reason: CacheProtectionReason) -> WorkflowKey {
    switch reason {
    case .runningApplication: .appRunningCache
    case .incompleteScan: .incompleteCache
    case .missingIdentity, .unsafePath: .freshScanRequired
    default: .protectedCache
    }
}
