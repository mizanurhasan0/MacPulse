import AppKit
import Darwin
import Foundation

struct NativeCleanerService: Sendable {
    private struct Root: Sendable {
        var url: URL
        var category: String
        var recursiveTargets: Bool
        var minimumAge: TimeInterval = 0
        var ownerBundleID: String? = nil
    }

    func scan(progress: @escaping @Sendable (String) -> Void) async -> [CleanupEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let runningIDs = await MainActor.run {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).map { $0.lowercased() })
        }
        return await Task.detached(priority: .utility) {
            Self.scan(home: home, runningBundleIDs: runningIDs, progress: progress)
        }.value
    }

    func clean(
        _ entries: [CleanupEntry], runningBundleIDs: Set<String>,
        onUpdate: @escaping @Sendable (String, CleanupEntry.State) -> Void
    ) async -> [CleanupEntry] {
        await Task.detached(priority: .utility) {
            var results = entries
            for index in results.indices {
                let state = Self.remove(
                    results[index], home: FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL,
                    runningBundleIDs: runningBundleIDs)
                results[index].state = state
                onUpdate(results[index].url.path, state)
            }
            return results
        }.value
    }

    private static func scan(
        home: URL, runningBundleIDs: Set<String>, progress: @escaping @Sendable (String) -> Void
    ) -> [CleanupEntry] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let roots = [
            Root(url: library.appendingPathComponent("Caches", isDirectory: true), category: "Application caches", recursiveTargets: true),
            Root(url: library.appendingPathComponent("Logs", isDirectory: true), category: "Application logs", recursiveTargets: true, minimumAge: 30 * 24 * 60 * 60),
            Root(url: home.appendingPathComponent(".npm/_cacache", isDirectory: true), category: "npm cache", recursiveTargets: true),
            Root(url: home.appendingPathComponent(".cache/pip", isDirectory: true), category: "pip cache", recursiveTargets: true),
            Root(url: home.appendingPathComponent(".cache/uv", isDirectory: true), category: "uv cache", recursiveTargets: true),
            Root(url: home.appendingPathComponent(".gradle/caches", isDirectory: true), category: "Gradle cache", recursiveTargets: true),
            Root(url: library.appendingPathComponent("Caches/pnpm", isDirectory: true), category: "pnpm cache", recursiveTargets: true),
            Root(url: library.appendingPathComponent("Caches/Yarn", isDirectory: true), category: "Yarn cache", recursiveTargets: true),
            Root(url: library.appendingPathComponent("Caches/Homebrew", isDirectory: true), category: "Homebrew downloads", recursiveTargets: true),
            Root(url: library.appendingPathComponent("Developer/Xcode/DerivedData", isDirectory: true), category: "Xcode build cache", recursiveTargets: true, ownerBundleID: "com.apple.dt.Xcode"),
            Root(url: library.appendingPathComponent("Developer/CoreSimulator/Caches", isDirectory: true), category: "Simulator cache", recursiveTargets: true, ownerBundleID: "com.apple.dt.Xcode"),
        ]

        var entries: [CleanupEntry] = []
        var seen = Set<String>()
        for root in roots {
            progress(root.category)
            entries += scanRoot(
                root, home: home, runningBundleIDs: runningBundleIDs, seen: &seen, progress: progress)
        }

        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        let supportCaches: [(String, String, String)] = [
            ("Code/Cache", "Editor cache", "com.microsoft.VSCode"),
            ("Code/CachedData", "Editor cache", "com.microsoft.VSCode"),
            ("Discord/Cache", "App cache", "com.hnc.Discord"),
            ("Discord/Code Cache", "App cache", "com.hnc.Discord"),
            ("Claude/Cache", "App cache", "com.anthropic.claudefordesktop"),
            ("Claude/GPUCache", "App cache", "com.anthropic.claudefordesktop"),
            ("Google/GoogleUpdater/crx_cache", "Browser update cache", "com.google.GoogleUpdater"),
        ]
        for (relative, category, bundleID) in supportCaches {
            progress(category)
            entries += scanRoot(
                Root(url: support.appendingPathComponent(relative, isDirectory: true),
                     category: category, recursiveTargets: true, ownerBundleID: bundleID),
                home: home, runningBundleIDs: runningBundleIDs, seen: &seen, progress: progress)
        }

        let containers = library.appendingPathComponent("Containers", isDirectory: true)
        let containerNames = (try? FileManager.default.contentsOfDirectory(
            at: containers, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for container in containerNames {
            let bundleID = container.lastPathComponent
            guard bundleID.contains("."), !bundleID.lowercased().hasPrefix("com.apple."),
                  !runningBundleIDs.contains(bundleID.lowercased())
            else { continue }
            progress("Sandboxed app cache")
            let dataRoot = container.appendingPathComponent("Data", isDirectory: true)
            entries += scanRoot(
                Root(url: dataRoot.appendingPathComponent("Library/Caches", isDirectory: true),
                     category: "Sandboxed app cache", recursiveTargets: true, ownerBundleID: bundleID),
                home: home, runningBundleIDs: runningBundleIDs, seen: &seen, progress: progress)
            entries += scanRoot(
                Root(url: dataRoot.appendingPathComponent("tmp", isDirectory: true),
                     category: "Old app temporary files", recursiveTargets: true,
                     minimumAge: 7 * 24 * 60 * 60, ownerBundleID: bundleID),
                home: home, runningBundleIDs: runningBundleIDs, seen: &seen, progress: progress)
        }

        for browser in browserProfiles(in: library) {
            progress("Browser service worker cache")
            let bundleID = browser.bundleID.lowercased()
            guard !runningBundleIDs.contains(bundleID) else { continue }
            let cache = browser.profile.appendingPathComponent("Service Worker/CacheStorage", isDirectory: true)
            entries += scanRoot(
                Root(url: cache, category: "Browser service worker cache", recursiveTargets: true,
                     ownerBundleID: bundleID), home: home, runningBundleIDs: runningBundleIDs,
                seen: &seen, skipActive: false, progress: progress)
        }

        return entries.sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    private static func scanRoot(
        _ root: Root, home: URL, runningBundleIDs: Set<String>, seen: inout Set<String>,
        skipActive: Bool = true, progress: (@Sendable (String) -> Void)? = nil
    ) -> [CleanupEntry] {
        if skipActive, let bundleID = root.ownerBundleID,
           runningBundleIDs.contains(bundleID.lowercased()) { return [] }
        var rootInfo = stat()
        guard root.url.path.withCString({ lstat($0, &rootInfo) }) == 0,
              rootInfo.st_mode & S_IFMT == S_IFDIR,
              rootInfo.st_uid == geteuid()
        else { return [] }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var result: [CleanupEntry] = []
        for (index, child) in children.enumerated() {
            if index > 0 && index.isMultiple(of: 10) {
                progress?("\(root.category) · \(index) folders checked")
            }
            let name = child.lastPathComponent
            guard !name.isEmpty, name != ".", name != ".." else { continue }
            if root.category == "Application caches" && name.lowercased().hasPrefix("com.apple.") { continue }
            let ownerBundle = root.ownerBundleID ?? inferredBundleID(for: name, among: runningBundleIDs)
            if skipActive, let ownerBundle, runningBundleIDs.contains(ownerBundle.lowercased()) { continue }
            if name.lowercased().contains("macpulse") { continue }

            var info = stat()
            guard child.path.withCString({ lstat($0, &info) }) == 0,
                  info.st_mode & S_IFMT != S_IFLNK,
                  info.st_uid == geteuid()
            else { continue }

            if root.minimumAge > 0 {
                let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                guard Date().timeIntervalSince(modified) >= root.minimumAge else { continue }
            }
            let bytes: UInt64
            if root.recursiveTargets && info.st_mode & S_IFMT == S_IFDIR {
                let inventory = allocatedSize(at: child, minimumAge: root.minimumAge) { folders, items in
                    progress?("\(root.category) · \(folders) folders / \(items) items checked")
                }
                guard inventory.isComplete else { continue }
                bytes = inventory.bytes
            } else {
                bytes = allocated(info)
            }
            guard bytes > 0, seen.insert(child.standardizedFileURL.path).inserted else { continue }
            let category = root.category == "Application caches" ? cacheCategory(for: name) : root.category

            result.append(CleanupEntry(
                url: child.standardizedFileURL,
                category: category,
                estimatedBytes: bytes,
                state: .pending,
                allowedRootPath: root.url.standardizedFileURL.path,
                device: UInt64(info.st_dev),
                inode: UInt64(info.st_ino),
                modificationSeconds: Int64(info.st_mtimespec.tv_sec),
                ownerBundleIdentifier: ownerBundle))
        }
        return result
    }

    private static func remove(
        _ entry: CleanupEntry, home: URL, runningBundleIDs: Set<String>
    ) -> CleanupEntry.State {
        if let owner = entry.ownerBundleIdentifier, runningBundleIDs.contains(owner.lowercased()) {
            return .retained
        }
        let path = entry.url.standardizedFileURL.path
        let rootPath = entry.allowedRootPath
        guard rootPath.hasPrefix(home.path + "/"),
              entry.url.deletingLastPathComponent().standardizedFileURL.path == rootPath,
              path.hasPrefix(rootPath + "/"),
              validateAncestors(of: entry.url, home: home)
        else { return .retained }

        var current = stat()
        guard path.withCString({ lstat($0, &current) }) == 0,
              current.st_mode & S_IFMT != S_IFLNK,
              current.st_uid == geteuid(),
              UInt64(current.st_dev) == entry.device,
              UInt64(current.st_ino) == entry.inode,
              Int64(current.st_mtimespec.tv_sec) == entry.modificationSeconds,
              current.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) == 0
        else { return .retained }

        do {
            try FileManager.default.removeItem(at: entry.url)
            return .removed
        } catch {
            return .retained
        }
    }

    private static func validateAncestors(of url: URL, home: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.path != home.path {
            var info = stat()
            guard current.path.withCString({ lstat($0, &info) }) == 0,
                  info.st_mode & S_IFMT != S_IFLNK,
                  info.st_uid == geteuid()
            else { return false }
            current.deleteLastPathComponent()
            guard current.path.hasPrefix(home.path) else { return false }
        }
        return true
    }

    private static func allocatedSize(
        at root: URL, minimumAge: TimeInterval = 0,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> (bytes: UInt64, isComplete: Bool) {
        var pending = [root]
        var visited = 0
        var inspected = 0
        var total: UInt64 = 0
        var complete = true
        while let current = pending.popLast(), visited < 20_000, inspected < 100_000 {
            visited += 1
            if visited.isMultiple(of: 500) { progress?(visited, inspected) }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: current, includingPropertiesForKeys: nil, options: [])
            else { complete = false; continue }
            for child in children {
                inspected += 1
                if inspected > 100_000 { complete = false; break }
                var info = stat()
                guard child.path.withCString({ lstat($0, &info) }) == 0,
                      info.st_mode & S_IFMT != S_IFLNK,
                      info.st_uid == geteuid(),
                      info.st_flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) == 0
                else { complete = false; continue }
                if minimumAge > 0 {
                    let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                    if Date().timeIntervalSince(modified) < minimumAge { complete = false; continue }
                }
                if info.st_mode & S_IFMT == S_IFDIR {
                    pending.append(child)
                } else if info.st_mode & S_IFMT == S_IFREG {
                    let sum = total.addingReportingOverflow(allocated(info))
                    total = sum.overflow ? UInt64.max : sum.partialValue
                }
            }
        }
        if !pending.isEmpty || visited >= 20_000 || inspected >= 100_000 { complete = false }
        return (total, complete)
    }

    private static func allocated(_ info: stat) -> UInt64 {
        UInt64(max(0, info.st_blocks)) * 512
    }

    private static func inferredBundleID(for name: String, among running: Set<String>) -> String? {
        let candidate = name.lowercased()
        return running.first { id in
            id == candidate || id.hasSuffix("." + candidate) || candidate.hasSuffix("." + id)
        }
    }

    private static func cacheCategory(for name: String) -> String {
        let lowercased = name.lowercased()
        if ["google", "chrome", "firefox", "mozilla", "brave", "vivaldi", "microsoft edge"]
            .contains(where: lowercased.contains) {
            return "Browser cache"
        }
        if ["npm", "pnpm", "yarn", "homebrew", "pip", "uv", "swiftpm", "gradle", "maven"]
            .contains(where: lowercased.contains) {
            return "Developer cache"
        }
        return "Application caches"
    }

    private struct BrowserProfile {
        var profile: URL
        var bundleID: String
    }

    private static func browserProfiles(in library: URL) -> [BrowserProfile] {
        let applicationSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let roots: [(String, String)] = [
            ("Google/Chrome", "com.google.Chrome"),
            ("Microsoft Edge", "com.microsoft.edgemac"),
            ("BraveSoftware/Brave-Browser", "com.brave.Browser"),
            ("Vivaldi", "com.vivaldi.Vivaldi"),
        ]
        var profiles: [BrowserProfile] = []
        for (relative, bundleID) in roots {
            let browserRoot = applicationSupport.appendingPathComponent(relative, isDirectory: true)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: browserRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            profiles += children.compactMap { profile in
                var info = stat()
                guard profile.path.withCString({ lstat($0, &info) }) == 0,
                      info.st_mode & S_IFMT == S_IFDIR,
                      info.st_uid == geteuid()
                else { return nil }
                return BrowserProfile(profile: profile, bundleID: bundleID)
            }
        }
        return profiles
    }
}
