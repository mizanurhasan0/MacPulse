import XCTest
import Darwin
@testable import MacPulse

final class DeveloperProcessTests: XCTestCase {
    func testDiscoversOnlyOwnStandaloneRuntimeAndStopsMatchingFixture() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        let readings = try await service.inspect()
        let target = try XCTUnwrap(readings.first(where: { $0.pid == fixture.pid }))
        XCTAssertEqual(target.uid, geteuid())
        XCTAssertEqual(target.name, "node")
        XCTAssertEqual(URL(fileURLWithPath: target.executablePath).standardizedFileURL,
                       fixture.executable.standardizedFileURL)
        XCTAssertGreaterThan(target.processStartTime, 0)
        XCTAssertGreaterThan(target.memoryBytes, 0)
        let result = await service.stop(target: target)
        XCTAssertEqual(result, .terminated)
        fixture.waitForExit()
        XCTAssertFalse(fixture.isRunning)
    }

    func testStaleStartIdentityDoesNotSignalFixture() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        var target = try await reading(pid: fixture.pid, using: service)
        target.processStartTime &+= 1
        let result = await service.stop(target: target)
        XCTAssertEqual(result, .identityChanged)
        XCTAssertTrue(fixture.isRunning)
    }

    func testForeignUIDAndProtectedPIDAreRejectedBeforeSignal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        let target = try await reading(pid: fixture.pid, using: service)
        var foreign = target
        foreign.uid &+= 1
        let foreignResult = await service.stop(target: foreign)
        XCTAssertEqual(foreignResult, .protected)
        XCTAssertTrue(fixture.isRunning)
        var ownProcess = target
        ownProcess.pid = getpid()
        let ownResult = await service.stop(target: ownProcess)
        XCTAssertEqual(ownResult, .protected)
        XCTAssertTrue(fixture.isRunning)
    }

    func testExecutablePathMismatchDoesNotSignalFixture() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        var target = try await reading(pid: fixture.pid, using: service)
        let secondPath = fixture.directory.appendingPathComponent("other/node")
        try FileManager.default.createDirectory(at: secondPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.executable, to: secondPath)
        target.executablePath = secondPath.path
        let result = await service.stop(target: target)
        XCTAssertEqual(result, .identityChanged)
        XCTAssertTrue(fixture.isRunning)
    }

    func testRuntimeInsideAppBundleIsNotEligible() async throws {
        let fixture = try makeFixture(relativePath: "Embedded.app/Contents/MacOS/node")
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        let readings = try await service.inspect()
        XCTAssertFalse(readings.contains { $0.pid == fixture.pid })
        let target = DeveloperProcessReading(pid: fixture.pid, uid: geteuid(),
                                            executablePath: fixture.executable.path, processStartTime: 1,
                                            memoryBytes: 0, cpuPercent: nil)
        let result = await service.stop(target: target)
        XCTAssertEqual(result, .protected)
        XCTAssertTrue(fixture.isRunning)
    }

    func testAlreadyExitedFixtureIsReportedWithoutAnotherSignal() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        let target = try await reading(pid: fixture.pid, using: service)
        fixture.terminate()
        fixture.waitForExit()
        let result = await service.stop(target: target)
        XCTAssertEqual(result, .alreadyExited)
    }

    func testCancellationBeforeStopDoesNotSignalFixture() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = DeveloperProcessService()
        let target = try await reading(pid: fixture.pid, using: service)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return await service.stop(target: target)
        }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(fixture.isRunning)
    }

    private func reading(pid: Int32, using service: DeveloperProcessService) async throws -> DeveloperProcessReading {
        let readings = try await service.inspect()
        return try XCTUnwrap(readings.first { $0.pid == pid })
    }

    private func makeFixture(relativePath: String = "node") throws -> RuntimeFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacPulseRuntime-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let executable = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0, posix_spawnattr_init(&attributes) == 0 else {
            throw POSIXError(.EIO)
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGTERM)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))

        var arguments: [UnsafeMutablePointer<CChar>?] = [strdup(executable.path), strdup("15"), nil]
        var environment: [UnsafeMutablePointer<CChar>?] = [strdup("PATH=/usr/bin:/bin"), nil]
        defer {
            arguments.forEach { free($0) }
            environment.forEach { free($0) }
        }
        var pid: pid_t = 0
        let status = executable.path.withCString { path in
            arguments.withUnsafeMutableBufferPointer { argv in
                environment.withUnsafeMutableBufferPointer { envp in
                    posix_spawn(&pid, path, &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
                }
            }
        }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO) }
        return RuntimeFixture(directory: directory, executable: executable, pid: pid)
    }
}

private final class RuntimeFixture {
    let directory: URL
    let executable: URL
    let pid: Int32
    private var reaped = false

    init(directory: URL, executable: URL, pid: Int32) {
        self.directory = directory
        self.executable = executable
        self.pid = pid
    }

    var isRunning: Bool {
        guard !reaped else { return false }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid || (result == -1 && errno == ECHILD) {
            reaped = true
            return false
        }
        return result == 0
    }

    func terminate() {
        if isRunning { kill(pid, SIGTERM) }
    }

    func waitForExit() {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    func cleanup() {
        terminate()
        waitForExit()
        try? FileManager.default.removeItem(at: directory)
    }
}
