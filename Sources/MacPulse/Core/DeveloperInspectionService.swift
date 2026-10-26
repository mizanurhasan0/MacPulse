import Foundation
import Darwin

enum DeveloperToolID: String, CaseIterable, Identifiable, Sendable {
    case node, npm, pnpm, yarn, homebrew, xcode, swift, docker
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .node: "Node.js"
        case .npm: "npm"
        case .pnpm: "pnpm"
        case .yarn: "Yarn"
        case .homebrew: "Homebrew"
        case .xcode: "Xcode"
        case .swift: "Swift"
        case .docker: "Docker"
        }
    }

    fileprivate var executableCandidates: [String] {
        switch self {
        case .node: ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        case .npm: ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"]
        case .pnpm: ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"]
        case .yarn: ["/opt/homebrew/bin/yarn", "/usr/local/bin/yarn"]
        case .homebrew: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .xcode: ["/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", "/usr/bin/xcodebuild"]
        case .swift: ["/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
                      "/Library/Developer/CommandLineTools/usr/bin/swift", "/usr/bin/swift"]
        case .docker: ["/Applications/Docker.app/Contents/Resources/bin/docker", "/opt/homebrew/bin/docker", "/usr/local/bin/docker"]
        }
    }

    fileprivate var versionArguments: [String] { self == .xcode ? ["-version"] : ["--version"] }
}

enum DeveloperToolStatus: String, Sendable {
    case available, notFound, failed, timedOut
}

struct DockerEngineReading: Sendable {
    var isRunning: Bool
    var serverVersion: String?
    var runningContainers: Int?
    var stoppedContainers: Int?
    var images: Int?
    var cpuCount: Int?
    var memoryBytes: UInt64?
    var detail: String?
}

struct DeveloperToolReading: Identifiable, Sendable {
    var id: DeveloperToolID
    var executablePath: String?
    var version: String?
    var status: DeveloperToolStatus
    var detail: String?
    var docker: DockerEngineReading?
}

/// Explicit, on-demand inspection only. It never installs, updates, prunes, or stops development tools.
struct DeveloperInspectionService: Sendable {
    private let executableOverrides: [DeveloperToolID: URL]
    private let runner: BoundedCommandRunner

    /// Overrides permit isolated executable fixtures in tests. The production UI uses the defaults.
    init(executableOverrides: [DeveloperToolID: URL] = [:], timeout: TimeInterval = 4) {
        self.executableOverrides = executableOverrides
        runner = BoundedCommandRunner(timeout: timeout)
    }

    func inspect() async throws -> [DeveloperToolReading] {
        try Task.checkCancellation()
        let tools = DeveloperToolID.allCases
        return try await withThrowingTaskGroup(of: DeveloperToolReading.self) { group in
            var nextIndex = 0
            var readings: [DeveloperToolReading] = []
            for _ in 0..<min(3, tools.count) {
                let tool = tools[nextIndex]
                nextIndex += 1
                group.addTask { try await inspect(tool: tool) }
            }
            while let reading = try await group.next() {
                try Task.checkCancellation()
                readings.append(reading)
                if nextIndex < tools.count {
                    let tool = tools[nextIndex]
                    nextIndex += 1
                    group.addTask { try await inspect(tool: tool) }
                }
            }
            return readings.sorted { tools.firstIndex(of: $0.id)! < tools.firstIndex(of: $1.id)! }
        }
    }

    func inspect(tool: DeveloperToolID) async throws -> DeveloperToolReading {
        try Task.checkCancellation()
        guard let executable = executable(for: tool) else {
            return DeveloperToolReading(id: tool, executablePath: nil, version: nil,
                                        status: .notFound, detail: nil, docker: nil)
        }
        do {
            let command = try await runner.run(executable: executable, arguments: tool.versionArguments)
            if command.timedOut {
                return DeveloperToolReading(id: tool, executablePath: executable.path, version: nil,
                                            status: .timedOut, detail: summary(command.output), docker: nil)
            }
            guard command.exitCode == 0, !command.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return DeveloperToolReading(id: tool, executablePath: executable.path, version: nil,
                                            status: .failed, detail: summary(command.output), docker: nil)
            }
            let engine = tool == .docker ? try await dockerStatus(executable: executable) : nil
            return DeveloperToolReading(id: tool, executablePath: executable.path,
                                        version: summary(command.output), status: .available, detail: nil, docker: engine)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return DeveloperToolReading(id: tool, executablePath: executable.path, version: nil,
                                        status: .failed, detail: String(error.localizedDescription.prefix(512)), docker: nil)
        }
    }

    private func dockerStatus(executable: URL) async throws -> DockerEngineReading {
        let format = "{{.ServerVersion}}|{{.ContainersRunning}}|{{.ContainersStopped}}|{{.Images}}|{{.NCPU}}|{{.MemTotal}}"
        // Never honor a user-selected remote Docker context or environment endpoint.
        let result = try await runner.run(executable: executable,
                                          arguments: ["--host", Self.localDockerEndpoint, "info", "--format", format])
        let fields = result.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false)
        guard !result.timedOut, result.exitCode == 0, fields.count == 6,
              let running = Int(fields[1]), let stopped = Int(fields[2]), let images = Int(fields[3]),
              let cpu = Int(fields[4]), let memory = UInt64(fields[5]),
              running >= 0, stopped >= 0, images >= 0, cpu > 0, memory > 0 else {
            return DockerEngineReading(isRunning: false, detail: summary(result.output))
        }
        return DockerEngineReading(isRunning: true, serverVersion: String(fields[0]), runningContainers: running,
                                   stoppedContainers: stopped, images: images, cpuCount: cpu, memoryBytes: memory)
    }

    private static var localDockerEndpoint: String {
        let userSocket = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".docker/run/docker.sock").resolvingSymlinksInPath().path
        var info = stat()
        let status = userSocket.withCString { lstat($0, &info) }
        if status == 0, info.st_mode & S_IFMT == S_IFSOCK,
           info.st_uid == geteuid() || info.st_uid == 0 {
            return "unix://" + userSocket
        }
        return "unix:///var/run/docker.sock"
    }

    private func summary(_ output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return String(value.split(whereSeparator: \.isNewline).prefix(3).joined(separator: "\n").prefix(512))
    }

    private func executable(for tool: DeveloperToolID) -> URL? {
        if let override = executableOverrides[tool] {
            return Self.isUsableExecutable(override) ? override : nil
        }
        return tool.executableCandidates.lazy.map { URL(fileURLWithPath: $0) }
            .first(where: { Self.isUsableExecutable($0) })
    }

    private static func isUsableExecutable(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        var info = stat()
        let status = path.withCString { lstat($0, &info) }
        return status == 0 && info.st_mode & S_IFMT == S_IFREG
            && (info.st_uid == 0 || info.st_uid == geteuid())
            && info.st_mode & 0o002 == 0
            && FileManager.default.isExecutableFile(atPath: path)
    }
}

struct BoundedCommandResult: Sendable {
    var output: String
    var exitCode: Int32
    var timedOut: Bool
    var outputTruncated: Bool
}

/// Uses a nonblocking output pipe so a noisy or stalled child cannot block the UI or grow memory without limit.
struct BoundedCommandRunner: Sendable {
    var timeout: TimeInterval = 4
    var outputLimit = 32_768

    func run(executable: URL, arguments: [String]) async throws -> BoundedCommandResult {
        let worker = Task.detached(priority: .utility) {
            try execute(executable: executable, arguments: arguments)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func execute(executable: URL, arguments: [String]) throws -> BoundedCommandResult {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.environment = Self.inspectionEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            Self.stopOwnedChild(process)
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        try process.run()
        try pipe.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, min(timeout, 15))
        let limit = max(1_024, min(outputLimit, 1_048_576))
        var captured = Data()
        var truncated = false
        var timedOut = false
        var buffer = [UInt8](repeating: 0, count: 8_192)

        func drain() throws {
            // Bound each drain pass so continual output still allows timeout/cancellation checks.
            for _ in 0..<8 {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    let accepted = min(count, max(0, limit - captured.count))
                    if accepted > 0 { captured.append(contentsOf: buffer.prefix(accepted)) }
                    if accepted < count { truncated = true }
                } else if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                } else if errno != EINTR {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }

        while true {
            try Task.checkCancellation()
            try drain()
            if !process.isRunning {
                process.waitUntilExit()
                // The parent has exited; consume remaining buffered bytes without waiting for descendant processes.
                try drain()
                break
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = true
                Self.stopOwnedChild(process)
                try drain()
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return BoundedCommandResult(output: String(decoding: captured, as: UTF8.self),
                                    exitCode: process.isRunning ? -1 : process.terminationStatus,
                                    timedOut: timedOut, outputTruncated: truncated)
    }

    private static func stopOwnedChild(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private static func inspectionEnvironment() -> [String: String] {
        var environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8", "LC_ALL": "C", "CI": "1",
            "COREPACK_ENABLE_NETWORK": "0", "COREPACK_ENABLE_DOWNLOAD_PROMPT": "0", "COREPACK_ENABLE_PROJECT_SPEC": "0",
            "YARN_ENABLE_NETWORK": "0", "PNPM_DISABLE_SELF_UPDATE_CHECK": "1",
            "NPM_CONFIG_UPDATE_NOTIFIER": "false", "NPM_CONFIG_AUDIT": "false",
            "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"
        ]
        for key in ["HOME", "TMPDIR", "USER", "LOGNAME"] {
            if let value = ProcessInfo.processInfo.environment[key] { environment[key] = value }
        }
        let developerDirectory = "/Applications/Xcode.app/Contents/Developer"
        if FileManager.default.fileExists(atPath: developerDirectory) { environment["DEVELOPER_DIR"] = developerDirectory }
        return environment
    }
}
