import XCTest
@testable import MacPulse

final class DeveloperInspectionTests: XCTestCase {
    func testVersionInspectionUsesFixedArgumentsAndNeutralEnvironment() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: "printf '%s\\n' \"$*\" \"$COREPACK_ENABLE_NETWORK|$HOMEBREW_NO_AUTO_UPDATE\" \"$PWD\"")
        let reading = try await DeveloperInspectionService(executableOverrides: [.node: executable]).inspect(tool: .node)
        XCTAssertEqual(reading.status, .available)
        XCTAssertEqual(reading.version, "--version\n0|1\n/")
        XCTAssertEqual(reading.executablePath, executable.path)
    }

    func testWorldWritableExecutableIsNotExecuted() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: "echo unexpected")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: executable.path)
        let reading = try await DeveloperInspectionService(executableOverrides: [.node: executable]).inspect(tool: .node)
        XCTAssertEqual(reading.status, .notFound)
        XCTAssertNil(reading.version)
    }

    func testFailedCommandReportsBoundedStderr() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: "echo 'fixture failure' >&2\nexit 7")
        let reading = try await DeveloperInspectionService(executableOverrides: [.node: executable]).inspect(tool: .node)
        XCTAssertEqual(reading.status, .failed)
        XCTAssertEqual(reading.detail, "fixture failure")
    }

    func testDockerInspectionReadsOnlyAggregateFields() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: """
        if [ "$1" = --host ]; then
            [ "$3" = info ] && [ "$4" = --format ] || exit 8
            case "$2" in unix:///*) ;; *) echo 'remote endpoint rejected' >&2; exit 9 ;; esac
            [ -z "$DOCKER_HOST" ] && [ -z "$DOCKER_CONTEXT" ] || exit 10
            echo '28.0|2|3|5|8|4294967296'
        else
            [ "$1" = --version ] || exit 11
            echo 'Docker version fixture'
        fi
        """)
        let reading = try await DeveloperInspectionService(executableOverrides: [.docker: executable]).inspect(tool: .docker)
        XCTAssertEqual(reading.status, .available)
        XCTAssertEqual(reading.docker?.isRunning, true)
        XCTAssertEqual(reading.docker?.serverVersion, "28.0")
        XCTAssertEqual(reading.docker?.runningContainers, 2)
        XCTAssertEqual(reading.docker?.stoppedContainers, 3)
        XCTAssertEqual(reading.docker?.images, 5)
        XCTAssertEqual(reading.docker?.cpuCount, 8)
        XCTAssertEqual(reading.docker?.memoryBytes, 4_294_967_296)
    }

    func testUnavailableDockerDaemonKeepsCLIAvailable() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: """
        if [ "$1" = --host ]; then
            [ "$3" = info ] && [ "$4" = --format ] || exit 8
            case "$2" in unix:///*) ;; *) echo 'remote endpoint rejected' >&2; exit 9 ;; esac
            echo 'daemon unavailable' >&2
            exit 1
        fi
        echo 'Docker version fixture'
        """)
        let reading = try await DeveloperInspectionService(executableOverrides: [.docker: executable]).inspect(tool: .docker)
        XCTAssertEqual(reading.status, .available)
        XCTAssertEqual(reading.docker?.isRunning, false)
        XCTAssertEqual(reading.docker?.detail, "daemon unavailable")
    }

    func testOutputIsDrainedButMemoryIsBounded() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: "i=0; while [ \"$i\" -lt 10000 ]; do echo '012345678901234567890123456789'; i=$((i + 1)); done")
        let result = try await BoundedCommandRunner(timeout: 4, outputLimit: 1024).run(executable: executable, arguments: [])
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.outputTruncated)
        XCTAssertLessThanOrEqual(result.output.utf8.count, 1024)
    }

    func testTimeoutStopsOnlyLaunchedFixture() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: "exec /bin/sleep 5")
        let result = try await BoundedCommandRunner(timeout: 0.15).run(executable: executable, arguments: [])
        XCTAssertTrue(result.timedOut)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testCancellationPropagatesAndStopsLaunchedFixture() async throws {
        let fixture = try directory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = try script(in: fixture, body: "exec /bin/sleep 5")
        let task = Task { try await BoundedCommandRunner(timeout: 5).run(executable: executable, arguments: []) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled inspection must throw CancellationError")
        } catch is CancellationError { }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseDeveloperTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func script(in directory: URL, body: String) throws -> URL {
        let url = directory.appendingPathComponent("fixture-tool")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
