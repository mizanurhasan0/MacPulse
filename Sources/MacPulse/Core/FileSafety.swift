import Darwin
import Foundation

struct FileStamp: Hashable, Sendable {
    var device: UInt64
    var inode: UInt64
    var logicalBytes: UInt64
    var allocatedBytes: UInt64
    var modificationSeconds: Int64
    var modificationNanoseconds: Int64
    var changeSeconds: Int64
    var changeNanoseconds: Int64
    var ownerID: UInt32
    var mode: UInt16
    var flags: UInt32

    var isDirectory: Bool { (mode & UInt16(S_IFMT)) == UInt16(S_IFDIR) }
    var isRegularFile: Bool { (mode & UInt16(S_IFMT)) == UInt16(S_IFREG) }
    var isSymbolicLink: Bool { (mode & UInt16(S_IFMT)) == UInt16(S_IFLNK) }
    var isDataless: Bool { flags & UInt32(SF_DATALESS) != 0 }
    var isImmutable: Bool { flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) != 0 }

    static func read(_ url: URL) throws -> FileStamp {
        guard url.isFileURL else { throw FileSafetyError.unavailable }
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0 else { throw FileSafetyError.unavailable }
        return FileStamp(info)
    }

    static func read(descriptor: Int32) throws -> FileStamp {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw FileSafetyError.unavailable }
        return FileStamp(info)
    }

    init(_ info: stat) {
        device = UInt64(UInt32(bitPattern: info.st_dev))
        inode = UInt64(info.st_ino)
        logicalBytes = UInt64(max(0, info.st_size))
        let blocks = UInt64(max(0, info.st_blocks))
        let allocation = blocks.multipliedReportingOverflow(by: 512)
        allocatedBytes = allocation.overflow ? UInt64.max : allocation.partialValue
        modificationSeconds = Int64(info.st_mtimespec.tv_sec)
        modificationNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changeSeconds = Int64(info.st_ctimespec.tv_sec)
        changeNanoseconds = Int64(info.st_ctimespec.tv_nsec)
        ownerID = UInt32(info.st_uid)
        mode = UInt16(info.st_mode)
        flags = UInt32(info.st_flags)
    }

    /// A rename may change ctime, but must not change the selected object's content identity.
    func hasSameContentIdentity(as other: FileStamp) -> Bool {
        device == other.device && inode == other.inode && logicalBytes == other.logicalBytes
            && modificationSeconds == other.modificationSeconds
            && modificationNanoseconds == other.modificationNanoseconds
            && ownerID == other.ownerID && mode == other.mode && flags == other.flags
    }
}

enum FileSafetyError: Error, LocalizedError, Sendable {
    case invalidRoot, unavailable, symbolicLink, outsideRoot, changed, protectedLocation
    case wrongOwner, unsupportedFile, duplicateKeeper, duplicateMismatch, lockedFile

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "The selected folder is unavailable or is not a directory."
        case .unavailable: "The selected item is unavailable or cannot be read."
        case .symbolicLink: "An item or one of its parent folders is a symbolic link. No changes were made."
        case .outsideRoot: "The selected item is outside the authorized folder."
        case .changed: "The item changed after scanning. Scan again before moving it to Trash."
        case .protectedLocation: "This item is inside a protected location or application package."
        case .wrongOwner: "The selected item belongs to another user."
        case .unsupportedFile: "Only reviewed regular files or eligible cache folders can be moved to Trash."
        case .duplicateKeeper: "At least one unchanged copy must be kept in every duplicate group."
        case .duplicateMismatch: "The duplicate files no longer have identical contents. Scan again."
        case .lockedFile: "Locked files and cloud placeholders cannot be moved by this action."
        }
    }
}

enum FilePathPolicy {
    /// Canonicalize only Apple's standard path aliases. Arbitrary symlinks remain detectable.
    static func normalized(_ url: URL) -> URL {
        let url = url.standardizedFileURL
        let path = url.path
        for (alias, actual) in [("/tmp", "/private/tmp"), ("/var", "/private/var"), ("/etc", "/private/etc")] {
            if path == alias || path.hasPrefix(alias + "/") {
                return URL(fileURLWithPath: actual + path.dropFirst(alias.count), isDirectory: url.hasDirectoryPath)
            }
        }
        return url
    }

    @discardableResult
    static func validateRoot(_ url: URL) throws -> FileStamp {
        guard url.isFileURL else { throw FileSafetyError.invalidRoot }
        let root = normalized(url)
        try validateAncestors(root)
        let stamp = try FileStamp.read(root)
        guard stamp.isDirectory else { throw FileSafetyError.invalidRoot }
        return stamp
    }

    @discardableResult
    static func validate(url: URL, within root: URL, expectedStamp: FileStamp? = nil) throws -> FileStamp {
        guard url.isFileURL, root.isFileURL else { throw FileSafetyError.outsideRoot }
        let root = normalized(root)
        let url = normalized(url)
        _ = try validateRoot(root)
        guard isStrictDescendant(url, of: root) else { throw FileSafetyError.outsideRoot }
        guard !isProtected(url) else { throw FileSafetyError.protectedLocation }
        try validateAncestors(url)
        let stamp = try FileStamp.read(url)
        guard !stamp.isSymbolicLink else { throw FileSafetyError.symbolicLink }
        guard stamp.isDirectory || stamp.isRegularFile else { throw FileSafetyError.unsupportedFile }
        guard stamp.ownerID == geteuid() else { throw FileSafetyError.wrongOwner }
        guard !stamp.isImmutable, !stamp.isDataless else { throw FileSafetyError.lockedFile }
        if let expectedStamp, stamp != expectedStamp { throw FileSafetyError.changed }
        return stamp
    }

    static func isStrictDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = normalized(root).path
        let path = normalized(url).path
        return path != rootPath && path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    static func isProtected(_ url: URL) -> Bool {
        let path = normalized(url).path
        let protected = [
            "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/dev",
            "/private/etc", "/private/var/db", "/private/var/root", "/private/var/vm",
        ]
        if protected.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let packageExtensions: Set<String> = [
            "app", "bundle", "framework", "photoslibrary", "photolibrary",
            "musiclibrary", "aplibrary", "sparsebundle", "backupbundle",
            "xcodeproj", "xcworkspace",
        ]
        return normalized(url).pathComponents.contains { component in
            component == ".git" || component == ".Trash"
                || packageExtensions.contains((component as NSString).pathExtension.lowercased())
        }
    }

    /// Manual large/duplicate-file actions remain conservative around credentials, source code,
    /// configuration, and application databases even when a scan is explicitly authorized.
    static func isProtectedReviewedFile(_ url: URL) -> Bool {
        let normalized = normalized(url)
        if isProtected(normalized) { return true }
        let library = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        if normalized == library || isStrictDescendant(normalized, of: library) { return true }
        if normalized.pathComponents.contains(where: { $0 != "/" && $0.hasPrefix(".") }) { return true }
        let name = normalized.lastPathComponent.lowercased()
        let protectedNames: Set<String> = [
            "dockerfile", "makefile", "cmakelists.txt", "podfile", "podfile.lock", "gemfile", "gemfile.lock",
            "package.swift", "package.resolved", "cargo.lock", "yarn.lock", "pnpm-lock.yaml", "package-lock.json",
            "id_rsa", "id_ed25519", "id_ecdsa", "known_hosts", "authorized_keys", "credentials", "config",
        ]
        if protectedNames.contains(name) { return true }
        let protectedExtensions: Set<String> = [
            "db", "db-wal", "db-shm", "sqlite", "sqlite3", "sqlite-wal", "sqlite-shm", "sqlite3-wal", "sqlite3-shm",
            "realm", "mdb", "accdb", "keychain", "keychain-db", "kdbx", "1password", "opvault", "agilekeychain",
            "pem", "key", "p12", "pfx", "crt", "cer", "mobileprovision", "provisionprofile",
            "swift", "m", "mm", "h", "hpp", "hxx", "c", "cc", "cpp", "cxx", "rs", "py", "pyw",
            "js", "mjs", "cjs", "jsx", "ts", "tsx", "go", "java", "kt", "kts", "rb", "php", "cs", "fs", "fsx",
            "scala", "sh", "zsh", "bash", "fish", "pl", "r", "lua", "dart", "vue", "svelte", "html", "css",
            "scss", "less", "sql", "ipynb", "gradle", "cmake", "json", "yaml", "yml", "toml", "ini", "conf", "config",
            "xml",
        ]
        return protectedExtensions.contains(normalized.pathExtension.lowercased())
    }

    /// Open directory components separately with O_NOFOLLOW rather than trusting path resolution.
    static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL else { throw FileSafetyError.invalidRoot }
        let normalized = normalized(url)
        var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw FileSafetyError.unavailable }
        do {
            for component in normalized.pathComponents where component != "/" {
                let next = component.withCString {
                    openat(current, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw FileSafetyError.symbolicLink }
                close(current)
                current = next
            }
            return current
        } catch {
            close(current)
            throw error
        }
    }

    private static func validateAncestors(_ url: URL) throws {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        let components = normalized(url).pathComponents.filter { $0 != "/" }
        for (index, component) in components.enumerated() {
            current.appendPathComponent(component)
            let stamp = try FileStamp.read(current)
            guard !stamp.isSymbolicLink else { throw FileSafetyError.symbolicLink }
            if index < components.count - 1, !stamp.isDirectory { throw FileSafetyError.invalidRoot }
        }
    }
}
