import CryptoKit
import Darwin
import Foundation

struct SafeStorageScanner: Sendable {
    /// Read-only analysis of immediate children in the current user's Caches directory.
    /// No candidate is removed by this service; results always require user review.
    func scan(progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [CleanupCandidate] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Caches", isDirectory: true)
        return try await scan(root: root, progress: progress)
    }

    /// Internal root injection permits isolated fixture tests. Production UI uses `scan()` above.
    func scan(root: URL, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws
        -> [CleanupCandidate]
    {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let root = FilePathPolicy.normalized(root)
            do { _ = try FilePathPolicy.validateRoot(root) } catch { throw StorageScanError.invalidRoot }

            let children = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            var candidates: [CleanupCandidate] = []
            var visitedFiles = Set<FileIdentity>()

            for (index, child) in children.enumerated() {
                try Task.checkCancellation()
                defer { progress(index + 1, children.count) }
                guard let childStamp = try? FileStamp.read(child), childStamp.isDirectory else { continue }

                let measurement = try Self.measureDirectory(child, visitedFiles: &visitedFiles)
                guard measurement.allocatedBytes > 0 else { continue }
                candidates.append(
                    CleanupCandidate(
                        url: child,
                        displayName: child.lastPathComponent,
                        allocatedBytes: measurement.allocatedBytes,
                        explanation:
                            "Estimated allocated size of user-level cache data. Applications may rebuild or rely on this data.",
                        risk: "Review required",
                        isComplete: measurement.isComplete && (try? FileStamp.read(child)) == childStamp,
                        stamp: childStamp,
                        inventoryFingerprint: measurement.fingerprint
                    ))
            }
            return candidates.sorted { $0.logicalBytes > $1.logicalBytes }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func inventory(at root: URL) throws -> CacheFolderInventory {
        var visitedFiles = Set<FileIdentity>()
        return try measureDirectory(FilePathPolicy.normalized(root), visitedFiles: &visitedFiles)
    }

    private static func measureDirectory(_ root: URL, visitedFiles: inout Set<FileIdentity>) throws
        -> CacheFolderInventory
    {
        var complete = true
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in
                    complete = false
                    return true
                }
            )
        else {
            return CacheFolderInventory(allocatedBytes: 0, isComplete: false, fingerprint: "")
        }

        var total: UInt64 = 0
        var inventoryEntries: [String] = []
        while let file = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            var info = stat()
            let result = file.standardizedFileURL.path.withCString { lstat($0, &info) }
            guard result == 0 else {
                complete = false
                continue
            }

            let kind = info.st_mode & S_IFMT
            let stamp = FileStamp(info)
            let relativePath = String(file.path.dropFirst(root.path.count))
            inventoryEntries.append(
                "\(relativePath.utf8.count):\(relativePath)\0\(stamp.device):\(stamp.inode):\(stamp.mode):\(stamp.ownerID):\(stamp.flags):\(stamp.logicalBytes):\(stamp.allocatedBytes):\(stamp.modificationSeconds):\(stamp.modificationNanoseconds):\(stamp.changeSeconds):\(stamp.changeNanoseconds)\0"
            )
            if kind == S_IFLNK {
                // Prevent traversal into a link target if the enumerator reports this entry.
                enumerator.skipDescendants()
                complete = false
                continue
            }
            if stamp.isImmutable || stamp.isDataless || stamp.ownerID != geteuid() {
                complete = false
                if stamp.isDirectory { enumerator.skipDescendants() }
                continue
            }
            if stamp.isDirectory {
                if FilePathPolicy.isProtected(file)
                    || (try? file.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                {
                    complete = false
                    enumerator.skipDescendants()
                }
                continue
            }
            guard kind == S_IFREG else { continue }

            let identity = FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
            guard visitedFiles.insert(identity).inserted else { continue }

            // lstat supplies allocated blocks without reopening the path and accidentally
            // following a link if an entry changes between enumeration and measurement.
            let sum = total.addingReportingOverflow(stamp.allocatedBytes)
            total = sum.overflow ? UInt64.max : sum.partialValue
        }
        var hasher = SHA256()
        for entry in inventoryEntries.sorted() {
            try Task.checkCancellation()
            hasher.update(data: Data(entry.utf8))
        }
        let fingerprint = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return CacheFolderInventory(allocatedBytes: total, isComplete: complete, fingerprint: fingerprint)
    }
}

enum StorageScanError: Error {
    case invalidRoot
}

struct CacheFolderInventory: Sendable {
    var allocatedBytes: UInt64
    var isComplete: Bool
    var fingerprint: String
}

private struct FileIdentity: Hashable {
    var device: UInt64
    var inode: UInt64
}
