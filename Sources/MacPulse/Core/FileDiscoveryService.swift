import CryptoKit
import Darwin
import Foundation

struct ScannedFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let root: URL
    let stamp: FileStamp
    var logicalBytes: UInt64 { stamp.logicalBytes }
    var allocatedBytes: UInt64 { stamp.allocatedBytes }
    var isProtected: Bool {
        FilePathPolicy.isProtected(url) || FilePathPolicy.isProtectedReviewedFile(url)
            || stamp.isImmutable || stamp.isDataless
    }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    /// The first file is the suggested keeper. All removals still require explicit selection.
    let files: [ScannedFile]
    var keeper: ScannedFile { files[0] }
    var redundantBytes: UInt64 { files.dropFirst().reduce(0) { $0 + $1.logicalBytes } }
}

struct FileDiscoveryResult: Sendable {
    let root: URL
    let largeFiles: [ScannedFile]
    let duplicateGroups: [DuplicateGroup]
    let scannedCount: Int
    /// Counts encountered entries skipped, not the unknown number of children below a skipped folder.
    let skippedCount: Int
    let isComplete: Bool
    let stoppedAtLimit: Bool
    var duplicatesScanned = true
    var statistics = FileDiscoveryStatistics()
}

struct FileDiscoveryStatistics: Sendable {
    var hashedBytes: UInt64 = 0
    var verifiedBytes: UInt64 = 0
    var reusedHashBytes: UInt64 = 0
    var reusedFingerprints = 0
    var maximumWorkers = 1
}

enum FileDiscoveryMode: Equatable, Sendable { case largeFiles, combined }

enum FileDiscoveryStage: String, Sendable {
    case enumerating
    case fingerprinting
    case hashing
    case verifying
}

struct FileDiscoveryProgress: Sendable {
    let stage: FileDiscoveryStage
    let scannedCount: Int
    var hashedBytes: UInt64
    let skippedCount: Int
    var totalHashBytes: UInt64 = 0
    var candidateFiles = 0
    var completedCandidates = 0
    var verifiedBytes: UInt64 = 0
    var currentFileName: String? = nil
    var stoppedAtLimit = false
    var reusedHashBytes: UInt64 = 0
    var reusedFingerprints = 0
    var workerLimit = 1
}

enum FileDiscoveryError: LocalizedError {
    case unsafeRoot
    case fileChanged
    case cannotRead

    var errorDescription: String? {
        switch self {
        case .unsafeRoot:
            "Choose a specific folder you own, rather than a system folder, your whole home folder, or an application package."
        case .fileChanged: "The file changed during analysis. Run a new scan before taking action."
        case .cannotRead: "The file could not be read. It may be protected or no longer available."
        }
    }
}

/// Read-only discovery in one explicitly selected folder. Data is read in bounded chunks,
/// and all candidates carry the original filesystem identity for later action validation.
struct FileDiscoveryService: Sendable {
    static let defaultLargeFileThreshold: UInt64 = 100 * 1024 * 1024
    static let fileLimit = 100_000
    let workerPolicy: ScanWorkerPolicy
    let fingerprintCache: ScanFingerprintCache
    private let systemState: @Sendable () -> ScanSystemState
    private let volumeInfo: @Sendable (URL) -> ScanVolumeInfo

    init(
        workerPolicy: ScanWorkerPolicy = ScanWorkerPolicy(),
        fingerprintCache: ScanFingerprintCache = ScanFingerprintCache(),
        systemState: @Sendable @escaping () -> ScanSystemState = { .current() },
        volumeInfo: @Sendable @escaping (URL) -> ScanVolumeInfo = { .read($0) }
    ) {
        self.workerPolicy = workerPolicy
        self.fingerprintCache = fingerprintCache
        self.systemState = systemState
        self.volumeInfo = volumeInfo
    }

    func clearFingerprintCache() async { await fingerprintCache.clear() }

    func scan(
        root: URL, minimumLargeFileBytes: UInt64 = Self.defaultLargeFileThreshold,
        progress: @Sendable @escaping (FileDiscoveryProgress) async -> Void = { _ in }
    ) async throws -> FileDiscoveryResult {
        try await scan(
            root: root, minimumLargeFileBytes: minimumLargeFileBytes,
            mode: .combined, progress: progress)
    }

    func scan(
        root: URL,
        minimumLargeFileBytes: UInt64 = Self.defaultLargeFileThreshold,
        mode: FileDiscoveryMode,
        maximumFiles: Int = Self.fileLimit,
        reuseFingerprints: Bool = true,
        enumerated: @Sendable @escaping (FileDiscoveryResult) async -> Void = { _ in },
        progress: @Sendable @escaping (FileDiscoveryProgress) async -> Void = { _ in }
    ) async throws -> FileDiscoveryResult {
        let worker = Task.detached(priority: .utility) {
            try await Self.performScan(
                root: root, threshold: minimumLargeFileBytes, mode: mode,
                maximumFiles: max(1, min(Self.fileLimit, maximumFiles)),
                reuseFingerprints: reuseFingerprints, workerPolicy: workerPolicy,
                cache: fingerprintCache, systemState: systemState, volumeInfo: volumeInfo,
                enumerated: enumerated, progress: progress)
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func performScan(
        root inputRoot: URL,
        threshold: UInt64,
        mode: FileDiscoveryMode,
        maximumFiles: Int,
        reuseFingerprints: Bool, workerPolicy: ScanWorkerPolicy, cache: ScanFingerprintCache,
        systemState: @Sendable @escaping () -> ScanSystemState,
        volumeInfo: @Sendable (URL) -> ScanVolumeInfo,
        enumerated: @Sendable (FileDiscoveryResult) async -> Void,
        progress: @Sendable @escaping (FileDiscoveryProgress) async -> Void
    ) async throws -> FileDiscoveryResult {
        try Task.checkCancellation()
        let root = FilePathPolicy.normalized(inputRoot)
        let rootStamp = try FilePathPolicy.validateRoot(root)
        try validateScanRoot(root, stamp: rootStamp)
        let failures = DiscoveryFailureCounter()
        let keys: [URLResourceKey] = [
            .isPackageKey, .isAliasFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in
                    failures.increment()
                    return true
                }
            )
        else { throw FileDiscoveryError.cannotRead }

        var files: [ScannedFile] = []
        var seen: Set<DiscoveryIdentity> = []
        var skipped = 0
        var stoppedAtLimit = false
        var visitedEntries = 0
        let dependencyFolders: Set<String> = ["node_modules", "Pods", "Carthage", "DerivedData", "venv", "__pycache__"]
        while let next = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let url = FilePathPolicy.normalized(next)
            visitedEntries += 1
            if visitedEntries.isMultiple(of: 100) {
                await progress(
                    FileDiscoveryProgress(
                        stage: .enumerating, scannedCount: files.count,
                        hashedBytes: 0, skippedCount: skipped + failures.value))
            }
            guard !url.lastPathComponent.hasPrefix(".") else {
                enumerator.skipDescendants()
                skipped += 1
                continue
            }
            do {
                let stamp = try FileStamp.read(url)
                guard !stamp.isSymbolicLink, stamp.device == rootStamp.device, stamp.ownerID == geteuid(),
                    !stamp.isDataless
                else {
                    enumerator.skipDescendants()
                    skipped += 1
                    continue
                }
                if stamp.isDirectory && dependencyFolders.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    skipped += 1
                    continue
                }
                let values = try url.resourceValues(forKeys: Set(keys))
                let cloudPlaceholder =
                    values.isUbiquitousItem == true
                    && values.ubiquitousItemDownloadingStatus != .current
                    && values.ubiquitousItemDownloadingStatus != .downloaded
                guard values.isAliasFile != true, values.isPackage != true, !cloudPlaceholder else {
                    enumerator.skipDescendants()
                    skipped += 1
                    continue
                }
                if stamp.isDirectory { continue }
                guard stamp.isRegularFile else {
                    skipped += 1
                    continue
                }
                let identity = DiscoveryIdentity(device: stamp.device, inode: stamp.inode)
                guard seen.insert(identity).inserted else {
                    skipped += 1
                    continue
                }
                files.append(ScannedFile(url: url, root: root, stamp: stamp))
                if files.count >= maximumFiles {
                    stoppedAtLimit = true
                    break
                }
            } catch {
                skipped += 1
                enumerator.skipDescendants()
            }
        }
        await progress(
            FileDiscoveryProgress(
                stage: .enumerating, scannedCount: files.count,
                hashedBytes: 0, skippedCount: skipped + failures.value, stoppedAtLimit: stoppedAtLimit))
        try Task.checkCancellation()

        let largeFiles = files.filter { $0.logicalBytes >= threshold }.sorted {
            $0.logicalBytes == $1.logicalBytes ? $0.url.path < $1.url.path : $0.logicalBytes > $1.logicalBytes
        }
        let preliminary = FileDiscoveryResult(
            root: root, largeFiles: largeFiles, duplicateGroups: [],
            scannedCount: files.count, skippedCount: skipped + failures.value,
            isComplete: skipped + failures.value == 0 && !stoppedAtLimit, stoppedAtLimit: stoppedAtLimit,
            duplicatesScanned: false)
        await enumerated(preliminary)
        try Task.checkCancellation()
        if mode == .largeFiles { return preliminary }

        let volume = volumeInfo(root)
        let canReuse = reuseFingerprints && volume.permitsFingerprintReuse
        let cached = canReuse ? await cache.snapshot(for: root) : [:]
        let limit: @Sendable () -> Int = { workerPolicy.limit(system: systemState(), volume: volume) }
        let reporter = ScanProgressReporter(
            initial: FileDiscoveryProgress(stage: .fingerprinting, scannedCount: files.count,
                hashedBytes: 0, skippedCount: skipped + failures.value, stoppedAtLimit: stoppedAtLimit),
            callback: progress)
        let hashCounter = DiscoveryByteCounter()
        let verifyCounter = DiscoveryByteCounter()
        var invalidFiles: Set<URL> = []
        let eligible = files.filter { $0.logicalBytes > 0 && !$0.isProtected }
        let sizes = Dictionary(grouping: eligible, by: \.logicalBytes)
        let candidates = sizes.keys.sorted().flatMap { size -> [ScannedFile] in
            guard let bucket = sizes[size], bucket.count > 1 else { return [] }
            return bucket.sorted { $0.url.path < $1.url.path }
        }
        if !candidates.isEmpty {
            await reporter.phase(.fingerprinting, candidates: candidates.count,
                skipped: skipped + failures.value, workers: limit())
        }
        let samples = try await BoundedScanWork.map(candidates, limit: limit) { file -> FingerprintOutcome in
            await reporter.file(file.url.lastPathComponent)
            var counted = false
            do {
                try Task.checkCancellation()
                let value: String
                let hit = cached[file.url.path]
                let reused = hit?.stamp == file.stamp && hit?.sample != nil
                if reused, let sample = hit?.sample {
                    try validateCandidate(file)
                    value = sample
                } else {
                    value = try sampleFingerprint(file)
                    if canReuse { await cache.store(file, sample: value) }
                }
                await reporter.completed(reused: reused)
                counted = true
                try Task.checkCancellation()
                try validateCandidate(file)
                return FingerprintOutcome(file: file, digest: value)
            } catch is CancellationError { throw CancellationError() } catch {
                if !counted { await reporter.completed() }
                return FingerprintOutcome(file: file, digest: nil)
            }
        }
        invalidFiles.formUnion(samples.filter { $0.digest == nil }.map { $0.file.url })
        let sampled = Dictionary(grouping: samples.filter { $0.digest != nil }) {
            "\($0.file.logicalBytes)-\($0.digest!)"
        }
        let fullFiles = sampled.keys.sorted().flatMap { key -> [ScannedFile] in
            let bucket = sampled[key]!
            return bucket.count > 1 ? bucket.map(\.file) : []
        }
        let totalHashBytes = fullFiles.reduce(UInt64.zero) { total, file in
            let sum = total.addingReportingOverflow(file.logicalBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
        let scannedCount = files.count
        let stopped = stoppedAtLimit
        let hashSkipped = skipped + failures.value + invalidFiles.count
        if !fullFiles.isEmpty {
            await reporter.phase(.hashing, candidates: fullFiles.count, bytes: totalHashBytes,
                skipped: hashSkipped, workers: limit())
        }
        let hashes = try await BoundedScanWork.map(fullFiles, limit: limit) { file -> FingerprintOutcome in
            await reporter.file(file.url.lastPathComponent)
            var counted = false
            do {
                try Task.checkCancellation()
                let hit = cached[file.url.path]
                let digest: String
                let reused = hit?.stamp == file.stamp && hit?.fullHash != nil
                if reused, let saved = hit?.fullHash {
                    try validateCandidate(file)
                    digest = saved
                } else {
                    digest = try await hash(file, counter: hashCounter, scannedCount: scannedCount,
                        skippedCount: hashSkipped, totalHashBytes: totalHashBytes,
                        candidateFiles: fullFiles.count, completedCandidates: 0, stoppedAtLimit: stopped,
                        progress: { await reporter.update($0) })
                    if canReuse { await cache.store(file, fullHash: digest) }
                }
                await reporter.update(FileDiscoveryProgress(stage: .hashing, scannedCount: scannedCount,
                    hashedBytes: hashCounter.value, skippedCount: hashSkipped))
                await reporter.completed(reusedBytes: reused ? file.logicalBytes : 0, reused: reused)
                counted = true
                try Task.checkCancellation()
                try validateCandidate(file)
                return FingerprintOutcome(file: file, digest: digest)
            } catch is CancellationError { throw CancellationError() } catch {
                if !counted { await reporter.completed() }
                return FingerprintOutcome(file: file, digest: nil)
            }
        }
        invalidFiles.formUnion(hashes.filter { $0.digest == nil }.map { $0.file.url })
        let matchingHashes = Dictionary(grouping: hashes.filter { $0.digest != nil }) {
            "\($0.file.logicalBytes)-\($0.digest!)"
        }
        let buckets = matchingHashes.keys.sorted().compactMap { key -> VerificationBucket? in
            let files = matchingHashes[key]!.map(\.file).sorted { $0.url.path < $1.url.path }
            return files.count > 1 ? VerificationBucket(id: key, files: files) : nil
        }
        await reporter.phase(.verifying, candidates: buckets.count, bytes: totalHashBytes,
            skipped: skipped + failures.value + invalidFiles.count, workers: limit())
        let verified = try await BoundedScanWork.map(buckets, limit: limit) { bucket -> VerificationOutcome in
            // Keep comparisons within a hash bucket ordered. Independent buckets
            // run concurrently; SHA equality still requires exact byte equality.
            var invalid: Set<URL> = []
            var clusters: [[ScannedFile]] = []
            for file in bucket.files {
                try Task.checkCancellation()
                await reporter.file(file.url.lastPathComponent)
                do {
                    try validateCandidate(file)
                    var match: Int?
                    for (index, cluster) in clusters.enumerated() where !invalid.contains(cluster[0].url) {
                        do {
                            if try await exactlyEqual(file, cluster[0], counter: verifyCounter,
                                context: FileDiscoveryProgress(stage: .verifying, scannedCount: scannedCount,
                                    hashedBytes: hashCounter.value, skippedCount: hashSkipped,
                                    totalHashBytes: totalHashBytes, currentFileName: file.url.lastPathComponent,
                                    stoppedAtLimit: stopped), progress: { await reporter.update($0) }) {
                                match = index
                                break
                            }
                        } catch is CancellationError { throw CancellationError() } catch {
                            let keeperChanged = (try? validateCandidate(cluster[0])) == nil
                            if keeperChanged { invalid.insert(cluster[0].url) }
                            try validateCandidate(file)
                            if !keeperChanged { throw error }
                        }
                    }
                    if let match { clusters[match].append(file) } else { clusters.append([file]) }
                } catch is CancellationError { throw CancellationError() } catch { invalid.insert(file.url) }
            }
            await reporter.update(FileDiscoveryProgress(stage: .verifying, scannedCount: scannedCount,
                hashedBytes: hashCounter.value, skippedCount: hashSkipped, verifiedBytes: verifyCounter.value))
            await reporter.completed()
            let groups = clusters.enumerated().compactMap { index, cluster -> DuplicateGroup? in
                let valid = cluster.filter { !invalid.contains($0.url) }
                return valid.count > 1 ? DuplicateGroup(id: "\(bucket.id)-\(index)", files: valid) : nil
            }
            return VerificationOutcome(groups: groups, invalid: invalid)
        }
        for outcome in verified { invalidFiles.formUnion(outcome.invalid) }
        await reporter.update(FileDiscoveryProgress(stage: .verifying, scannedCount: scannedCount,
            hashedBytes: hashCounter.value, skippedCount: hashSkipped, verifiedBytes: verifyCounter.value))
        try Task.checkCancellation()
        // Revalidate after awaited callbacks and other buckets, before publishing.
        let candidatesToValidate = Set(largeFiles + verified.flatMap { $0.groups.flatMap(\.files) })
        for file in candidatesToValidate {
            try Task.checkCancellation()
            if (try? validateCandidate(file)) == nil { invalidFiles.insert(file.url) }
        }
        let groups = verified.flatMap(\.groups).compactMap { group -> DuplicateGroup? in
            let valid = group.files.filter { !invalidFiles.contains($0.url) }
            return valid.count > 1 ? DuplicateGroup(id: group.id, files: valid) : nil
        }
        skipped += failures.value + invalidFiles.count
        let metrics = await reporter.snapshot
        return FileDiscoveryResult(
            root: root, largeFiles: largeFiles.filter { !invalidFiles.contains($0.url) },
            duplicateGroups: groups.sorted {
                $0.redundantBytes == $1.redundantBytes ? $0.id < $1.id : $0.redundantBytes > $1.redundantBytes
            },
            scannedCount: files.count, skippedCount: skipped,
            isComplete: skipped == 0 && !stoppedAtLimit, stoppedAtLimit: stoppedAtLimit,
            statistics: FileDiscoveryStatistics(hashedBytes: hashCounter.value, verifiedBytes: verifyCounter.value,
                reusedHashBytes: metrics.reusedHashBytes, reusedFingerprints: metrics.reusedFingerprints,
                maximumWorkers: workerPolicy.limit(system: systemState(), volume: volume)))
    }

    private static func validateCandidate(_ file: ScannedFile) throws {
        try verifiedDescriptor(for: file).withClosedDescriptor { _ in () }
    }

    private static func validateScanRoot(_ root: URL, stamp: FileStamp) throws {
        let denied = ["/", "/Users", "/Volumes", "/private", "/private/tmp", "/private/var", NSHomeDirectory()]
            .map { FilePathPolicy.normalized(URL(fileURLWithPath: $0)).path }
        let protectedPrefixes = [
            "/System", "/Library", "/usr", "/bin", "/sbin", "/dev", "/private/etc", "/private/var/db",
        ]
        let path = root.path
        let isProtected = protectedPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
        let isPackage = (try? root.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
        guard !denied.contains(path), !isProtected, !isPackage, stamp.ownerID == geteuid(), !stamp.isDataless else {
            throw FileDiscoveryError.unsafeRoot
        }
    }

    /// A small beginning/end sample only eliminates mismatches. Matching samples still
    /// require a full SHA-256 and byte comparison; sample equality never proves duplication.
    private static func sampleFingerprint(_ file: ScannedFile) throws -> String {
        let descriptor = try verifiedDescriptor(for: file)
        let fd = descriptor.value
        defer { Darwin.close(fd) }
        let sampleSize: UInt64 = 64 * 1024
        let firstLength = min(sampleSize, file.logicalBytes)
        let secondOffset = max(firstLength, file.logicalBytes > sampleSize ? file.logicalBytes - sampleSize : 0)
        var hasher = SHA256()
        for (offset, length) in [(UInt64.zero, firstLength), (secondOffset, file.logicalBytes - secondOffset)]
        where length > 0 {
            var buffer = [UInt8](repeating: 0, count: Int(length))
            var received = 0
            while received < buffer.count {
                try Task.checkCancellation()
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.pread(
                        fd, $0.baseAddress!.advanced(by: received), $0.count - received, off_t(offset) + off_t(received)
                    )
                }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw FileDiscoveryError.cannotRead
                }
                guard count > 0 else { throw FileDiscoveryError.fileChanged }
                received += count
            }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        }
        try validateOpenFile(fd, file: file)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(
        _ file: ScannedFile, counter: DiscoveryByteCounter, scannedCount: Int, skippedCount: Int,
        totalHashBytes: UInt64, candidateFiles: Int, completedCandidates: Int, stoppedAtLimit: Bool,
        progress: @Sendable (FileDiscoveryProgress) async -> Void
    ) async throws -> String {
        let descriptor = try verifiedDescriptor(for: file)
        let fd = descriptor.value
        defer { Darwin.close(fd) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        var bytesSinceProgress = 0
        var fileBytesRead: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw FileDiscoveryError.cannotRead
            }
            if count == 0 { break }
            buffer.withUnsafeBytes {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: $0.baseAddress, count: count))
            }
            counter.add(UInt64(count))
            fileBytesRead += UInt64(count)
            bytesSinceProgress += count
            if bytesSinceProgress >= 16 * 1024 * 1024 {
                await progress(
                    FileDiscoveryProgress(
                        stage: .hashing, scannedCount: scannedCount,
                        hashedBytes: counter.value, skippedCount: skippedCount, totalHashBytes: totalHashBytes,
                        candidateFiles: candidateFiles, completedCandidates: completedCandidates,
                        currentFileName: file.url.lastPathComponent, stoppedAtLimit: stoppedAtLimit))
                bytesSinceProgress = 0
            }
        }
        guard fileBytesRead == file.logicalBytes else { throw FileDiscoveryError.fileChanged }
        try validateOpenFile(fd, file: file)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func exactlyEqual(
        _ first: ScannedFile, _ second: ScannedFile, counter: DiscoveryByteCounter,
        context: FileDiscoveryProgress, progress: @Sendable (FileDiscoveryProgress) async -> Void
    ) async throws -> Bool {
        let lhs = try verifiedDescriptor(for: first)
        defer { Darwin.close(lhs.value) }
        let rhs = try verifiedDescriptor(for: second)
        defer { Darwin.close(rhs.value) }
        var a = [UInt8](repeating: 0, count: 1024 * 1024)
        var b = [UInt8](repeating: 0, count: 1024 * 1024)
        var comparedBytes: UInt64 = 0
        var bytesSinceProgress = 0
        while true {
            try Task.checkCancellation()
            let ac = try readChunk(lhs.value, into: &a)
            let bc = try readChunk(rhs.value, into: &b)
            guard ac == bc else { return false }
            if ac == 0 { break }
            let equal = a.withUnsafeBytes { left in
                b.withUnsafeBytes { right in Darwin.memcmp(left.baseAddress!, right.baseAddress!, ac) == 0 }
            }
            guard equal else { return false }
            comparedBytes += UInt64(ac)
            counter.add(UInt64(ac + bc))
            bytesSinceProgress += ac + bc
            if bytesSinceProgress >= 16 * 1024 * 1024 {
                var update = context
                update.verifiedBytes = counter.value
                await progress(update)
                bytesSinceProgress = 0
            }
        }
        guard comparedBytes == first.logicalBytes, comparedBytes == second.logicalBytes else {
            throw FileDiscoveryError.fileChanged
        }
        try validateOpenFile(lhs.value, file: first)
        try validateOpenFile(rhs.value, file: second)
        return true
    }

    private static func readChunk(_ fd: Int32, into buffer: inout [UInt8]) throws -> Int {
        var total = 0
        while total < buffer.count {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(fd, $0.baseAddress!.advanced(by: total), $0.count - total)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw FileDiscoveryError.cannotRead
            }
            if count == 0 { break }
            total += count
        }
        return total
    }

    private static func verifiedDescriptor(for file: ScannedFile) throws -> DiscoveryDescriptor {
        guard try FileStamp.read(file.url) == file.stamp else { throw FileDiscoveryError.fileChanged }
        let parent = try FilePathPolicy.openDirectory(file.url.deletingLastPathComponent())
        defer { Darwin.close(parent) }
        let fd = file.url.lastPathComponent.withCString {
            Darwin.openat(parent, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard fd >= 0 else { throw FileDiscoveryError.cannotRead }
        do { try validateOpenFile(fd, file: file) } catch {
            Darwin.close(fd)
            throw error
        }
        return DiscoveryDescriptor(value: fd)
    }

    private static func validateOpenFile(_ fd: Int32, file: ScannedFile) throws {
        let openStamp = try FileStamp.read(descriptor: fd)
        guard openStamp.isRegularFile, !openStamp.isDataless, openStamp == file.stamp,
            try FileStamp.read(file.url) == file.stamp
        else { throw FileDiscoveryError.fileChanged }
    }
}

private struct DiscoveryIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct DiscoveryDescriptor {
    let value: Int32
    func withClosedDescriptor<T>(_ body: (Int32) throws -> T) rethrows -> T {
        defer { Darwin.close(value) }
        return try body(value)
    }
}

private final class DiscoveryFailureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class DiscoveryByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: UInt64 = 0
    func add(_ count: UInt64) {
        lock.withLock {
            let next = bytes.addingReportingOverflow(count)
            bytes = next.overflow ? UInt64.max : next.partialValue
        }
    }
    var value: UInt64 { lock.withLock { bytes } }
}

private struct FingerprintOutcome: Sendable {
    let file: ScannedFile
    let digest: String?
}
private struct VerificationBucket: Sendable {
    let id: String
    let files: [ScannedFile]
}
private struct VerificationOutcome: Sendable {
    let groups: [DuplicateGroup]
    let invalid: Set<URL>
}
