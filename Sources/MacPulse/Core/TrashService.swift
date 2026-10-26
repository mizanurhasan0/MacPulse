import AppKit
import Darwin
import Foundation

enum CacheProtectionReason: Sendable {
    case systemManaged, runningApplication, ownApplication, unknownApplication, incompleteScan, missingIdentity,
        outsideCacheRoot, unsafePath

    var message: String {
        switch self {
        case .systemManaged: "macOS-managed cache folders are protected."
        case .runningApplication: "Quit the related application before cleaning this cache."
        case .ownApplication: "MacPulse's own cache is protected."
        case .unknownApplication: "The application that owns this cache could not be identified. Review it in Finder."
        case .incompleteScan: "This folder could not be scanned completely. It cannot be cleaned."
        case .missingIdentity: "Scan this folder again before cleaning it."
        case .outsideCacheRoot: "Only immediate folders inside your user Caches directory can be cleaned."
        case .unsafePath: "The folder changed, is locked, or is no longer eligible. Scan again."
        }
    }
}

enum CacheProtectionPolicy {
    static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(
            "Library/Caches", isDirectory: true)
    }

    static func rejectionReason(
        candidate: CleanupCandidate, runningBundleIDs: Set<String>,
        cacheRoot: URL = defaultRoot,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        revalidateIdentity: Bool = true
    ) -> CacheProtectionReason? {
        let root = FilePathPolicy.normalized(cacheRoot)
        let url = FilePathPolicy.normalized(candidate.url)
        guard url.deletingLastPathComponent().path == root.path else { return .outsideCacheRoot }
        let name = url.lastPathComponent.lowercased()
        if name == "com.apple" || name.hasPrefix("com.apple.") { return .systemManaged }
        if name == "macpulse" || name.hasPrefix("com.macpulse.")
            || ownBundleIdentifier.map({ identifiersOverlap(name, $0.lowercased()) }) == true
        {
            return .ownApplication
        }
        if runningBundleIDs.contains(where: { identifiersOverlap(name, $0.lowercased()) }) {
            return .runningApplication
        }
        // Some applications group caches under a vendor folder instead of their bundle identifier.
        let vendorAliases: [(String, [String])] = [
            ("com.google.", ["google", "chromium", "chrome"]),
            ("org.mozilla.", ["mozilla", "firefox"]),
            ("com.microsoft.", ["microsoft"]),
            ("com.brave.", ["bravesoftware", "brave"]),
        ]
        for (bundlePrefix, aliases) in vendorAliases where aliases.contains(name) {
            if runningBundleIDs.contains(where: { $0.lowercased().hasPrefix(bundlePrefix) }) {
                return .runningApplication
            }
        }
        if runningBundleIDs.contains(where: {
            let tail = $0.lowercased().split(separator: ".").last.map(String.init) ?? ""
            return tail.count >= 4 && tail == name.replacingOccurrences(of: " ", with: "")
        }) {
            return .runningApplication
        }
        let identityParts = name.split(separator: ".")
        guard identityParts.count >= 2, identityParts.first?.contains(where: \.isLetter) == true else {
            return .unknownApplication
        }
        guard candidate.isComplete else { return .incompleteScan }
        guard let stamp = candidate.stamp, candidate.inventoryFingerprint != nil else { return .missingIdentity }
        // Presentation can use the scan snapshot; execution always uses the default strict validation.
        if !revalidateIdentity { return nil }
        do {
            let current = try FilePathPolicy.validate(url: url, within: root, expectedStamp: stamp)
            guard current.isDirectory else { return .unsafePath }
        } catch { return .unsafePath }
        return nil
    }

    private static func identifiersOverlap(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + ".") || rhs.hasPrefix(lhs + ".")
    }
}

enum TrashCategory: Sendable { case cache, reviewedFile }

struct TrashTarget: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let root: URL
    let stamp: FileStamp
    let category: TrashCategory
    let estimatedBytes: UInt64
    let keeperURL: URL?
    let keeperStamp: FileStamp?
    let scanIsComplete: Bool
    let cacheFingerprint: String?

    init(
        url: URL, root: URL, stamp: FileStamp, category: TrashCategory,
        estimatedBytes: UInt64? = nil, keeperURL: URL? = nil, keeperStamp: FileStamp? = nil,
        scanIsComplete: Bool = true, cacheFingerprint: String? = nil
    ) {
        self.url = FilePathPolicy.normalized(url)
        self.root = FilePathPolicy.normalized(root)
        self.stamp = stamp
        self.category = category
        self.estimatedBytes = estimatedBytes ?? stamp.allocatedBytes
        self.keeperURL = keeperURL.map(FilePathPolicy.normalized)
        self.keeperStamp = keeperStamp
        self.scanIsComplete = scanIsComplete
        self.cacheFingerprint = cacheFingerprint
    }

    static func cache(_ candidate: CleanupCandidate, root: URL = CacheProtectionPolicy.defaultRoot) throws
        -> TrashTarget
    {
        guard let stamp = candidate.stamp else { throw FileSafetyError.changed }
        return TrashTarget(
            url: candidate.url, root: root, stamp: stamp, category: .cache,
            estimatedBytes: candidate.allocatedBytes, scanIsComplete: candidate.isComplete,
            cacheFingerprint: candidate.inventoryFingerprint)
    }
}

enum TrashItemStatus: String, Sendable { case moved, failed, cancelled }

struct TrashItemResult: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let status: TrashItemStatus
    let trashURL: URL?
    let message: String
    let estimatedBytes: UInt64
}

struct TrashBatchResult: Sendable {
    let items: [TrashItemResult]
    var movedCount: Int { items.filter { $0.status == .moved }.count }
    var failedCount: Int { items.filter { $0.status == .failed }.count }
    var cancelled: Bool { items.contains { $0.status == .cancelled } }
    var movedEstimatedBytes: UInt64 {
        items.filter { $0.status == .moved }.reduce(0) {
            let sum = $0.addingReportingOverflow($1.estimatedBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
}

protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws -> URL
}

struct SystemTrashMover: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw FileSafetyError.unavailable }
        return result as URL
    }
}

struct TrashService: Sendable {
    let cacheRoot: URL
    let mover: any TrashMoving

    init(cacheRoot: URL = CacheProtectionPolicy.defaultRoot, mover: any TrashMoving = SystemTrashMover()) {
        self.cacheRoot = FilePathPolicy.normalized(cacheRoot)
        self.mover = mover
    }

    func move(
        targets: [TrashTarget], runningBundleIDs: Set<String> = [],
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> TrashBatchResult {
        let worker = Task.detached(priority: .utility) {
            var seen = Set<URL>()
            let targets = targets.filter { seen.insert($0.url).inserted }
            let selected = Set(targets.map(\.url))
            var results: [TrashItemResult] = []
            for (index, target) in targets.enumerated() {
                if Task.isCancelled {
                    results += targets[index...].map {
                        TrashItemResult(
                            url: $0.url, status: .cancelled, trashURL: nil,
                            message: "Cancelled before this item was moved.", estimatedBytes: 0)
                    }
                    break
                }
                do {
                    let currentIDs = await MainActor.run {
                        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                    }
                    try self.validate(target, selected: selected, runningBundleIDs: runningBundleIDs.union(currentIDs))
                    try Task.checkCancellation()
                    let destination = try self.stageAndMove(target)
                    results.append(
                        TrashItemResult(
                            url: target.url, status: .moved, trashURL: destination,
                            message: "Moved to Trash.", estimatedBytes: target.estimatedBytes))
                } catch is CancellationError {
                    results.append(
                        TrashItemResult(
                            url: target.url, status: .cancelled, trashURL: nil,
                            message: "Cancelled before this item was moved.", estimatedBytes: 0))
                } catch {
                    results.append(
                        TrashItemResult(
                            url: target.url, status: .failed, trashURL: nil,
                            message: error.localizedDescription, estimatedBytes: 0))
                }
                progress(index + 1, targets.count)
            }
            return TrashBatchResult(items: results)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func validate(_ target: TrashTarget, selected: Set<URL>, runningBundleIDs: Set<String>) throws {
        let stamp = try FilePathPolicy.validate(url: target.url, within: target.root, expectedStamp: target.stamp)
        switch target.category {
        case .cache:
            guard target.root == cacheRoot else { throw FileSafetyError.outsideRoot }
            let candidate = CleanupCandidate(
                url: target.url, displayName: target.url.lastPathComponent,
                allocatedBytes: target.estimatedBytes, explanation: "", risk: "Review required",
                isComplete: target.scanIsComplete, stamp: target.stamp,
                inventoryFingerprint: target.cacheFingerprint)
            if let reason = CacheProtectionPolicy.rejectionReason(
                candidate: candidate, runningBundleIDs: runningBundleIDs,
                cacheRoot: cacheRoot)
            {
                throw NSError(
                    domain: "MacPulse.CacheProtection", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: reason.message])
            }
            let inventory = try SafeStorageScanner.inventory(at: target.url)
            guard inventory.isComplete, inventory.fingerprint == target.cacheFingerprint else {
                throw FileSafetyError.changed
            }
        case .reviewedFile:
            guard stamp.isRegularFile else { throw FileSafetyError.unsupportedFile }
            if FilePathPolicy.isProtectedReviewedFile(target.url) { throw FileSafetyError.protectedLocation }
        }
        if let keeper = target.keeperURL {
            guard let keeperStamp = target.keeperStamp, keeper != target.url, !selected.contains(keeper) else {
                throw FileSafetyError.duplicateKeeper
            }
            let current = try FilePathPolicy.validate(url: keeper, within: target.root, expectedStamp: keeperStamp)
            guard current.isRegularFile, current.logicalBytes == stamp.logicalBytes,
                current.device != stamp.device || current.inode != stamp.inode
            else { throw FileSafetyError.duplicateKeeper }
            guard try Self.identicalContents(target.url, stamp: stamp, keeper, otherStamp: current) else {
                throw FileSafetyError.duplicateMismatch
            }
        } else if target.keeperStamp != nil {
            throw FileSafetyError.duplicateKeeper
        }
    }

    /// Pin the parent directory, rename the selected entry into a private sibling staging directory,
    /// then recheck its identity. This prevents a replaced path from being blindly trashed. Failures
    /// restore the entry without overwriting an item another application has created in its place.
    private func stageAndMove(_ target: TrashTarget) throws -> URL {
        let parent = target.url.deletingLastPathComponent()
        let parentFD = try FilePathPolicy.openDirectory(parent)
        defer { close(parentFD) }
        let pinnedParent = try FileStamp.read(descriptor: parentFD)
        let name = target.url.lastPathComponent
        let sourceFD = name.withCString {
            openat(parentFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (target.stamp.isDirectory ? O_DIRECTORY : 0))
        }
        guard sourceFD >= 0 else { throw FileSafetyError.changed }
        defer { close(sourceFD) }
        guard try FileStamp.read(descriptor: sourceFD) == target.stamp else { throw FileSafetyError.changed }

        let stageName = ".MacPulse-\(UUID().uuidString)"
        guard stageName.withCString({ mkdirat(parentFD, $0, 0o700) }) == 0 else { throw FileSafetyError.unavailable }
        defer { _ = stageName.withCString { unlinkat(parentFD, $0, AT_REMOVEDIR) } }
        let stageFD = stageName.withCString { openat(parentFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard stageFD >= 0 else { throw FileSafetyError.unavailable }
        defer { close(stageFD) }
        let stageURL = parent.appendingPathComponent(stageName, isDirectory: true)
        let stagedItem = stageURL.appendingPathComponent(name, isDirectory: target.stamp.isDirectory)
        guard
            name.withCString({ source in
                name.withCString { destination in
                    renameatx_np(parentFD, source, stageFD, destination, UInt32(RENAME_EXCL))
                }
            }) == 0
        else { throw FileSafetyError.changed }

        do {
            let stagedStamp = try FileStamp.read(stagedItem)
            guard stagedStamp.hasSameContentIdentity(as: target.stamp) else { throw FileSafetyError.changed }
            let nowParent = try FileStamp.read(parent)
            guard nowParent.device == pinnedParent.device, nowParent.inode == pinnedParent.inode else {
                throw FileSafetyError.changed
            }
            _ = try FilePathPolicy.validate(url: stagedItem, within: target.root, expectedStamp: stagedStamp)
            return try mover.moveToTrash(stagedItem)
        } catch {
            // Recheck through the pinned directory before a no-overwrite restoration.
            var info = stat()
            if name.withCString({ fstatat(stageFD, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 {
                guard FileStamp(info).hasSameContentIdentity(as: target.stamp) else {
                    throw NSError(
                        domain: "MacPulse.Trash", code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The item changed while being moved. It remains at \(stagedItem.path); no existing file was overwritten."
                        ])
                }
                let restored = name.withCString { source in
                    name.withCString { destination in
                        renameatx_np(stageFD, source, parentFD, destination, UInt32(RENAME_EXCL))
                    }
                }
                if restored != 0 {
                    throw NSError(
                        domain: "MacPulse.Trash", code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "The item could not be moved to Trash or restored because its original path changed. It remains at \(stagedItem.path)."
                        ])
                }
            }
            throw error
        }
    }

    private static func identicalContents(_ lhs: URL, stamp: FileStamp, _ rhs: URL, otherStamp: FileStamp) throws
        -> Bool
    {
        let leftFD = lhs.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard leftFD >= 0 else { throw FileSafetyError.unavailable }
        let left = FileHandle(fileDescriptor: leftFD, closeOnDealloc: true)
        defer { try? left.close() }
        let rightFD = rhs.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard rightFD >= 0 else { throw FileSafetyError.unavailable }
        let right = FileHandle(fileDescriptor: rightFD, closeOnDealloc: true)
        defer { try? right.close() }
        guard try FileStamp.read(descriptor: leftFD) == stamp,
            try FileStamp.read(descriptor: rightFD) == otherStamp
        else { throw FileSafetyError.changed }
        while true {
            try Task.checkCancellation()
            let a = try left.read(upToCount: 256 * 1024) ?? Data()
            let b = try right.read(upToCount: 256 * 1024) ?? Data()
            if a != b { return false }
            if a.isEmpty { break }
        }
        guard try FileStamp.read(descriptor: leftFD) == stamp,
            try FileStamp.read(descriptor: rightFD) == otherStamp
        else { throw FileSafetyError.changed }
        return true
    }
}
