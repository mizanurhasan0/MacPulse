import Darwin
import Darwin.libproc
import Dispatch
import Foundation

struct DeveloperProcessReading: Identifiable, Sendable, Hashable {
    var id: Int32 { pid }
    var pid: Int32
    var uid: UInt32
    var executablePath: String
    var processStartTime: UInt64
    var memoryBytes: UInt64
    var cpuPercent: Double?
    var name: String { URL(fileURLWithPath: executablePath).lastPathComponent }
}

enum DeveloperStopOutcome: String, Sendable {
    case terminated, alreadyExited, identityChanged, protected, permissionDenied, stillRunning, requested, cancelled,
        failed
}

/// On-demand inspection of this user's standalone JavaScript runtimes.
/// Stopping a process is a separate explicitly approved action; the only signal sent is SIGTERM.
actor DeveloperProcessService {
    private var cpuSampler = ProcessCPUSampler()

    func inspect() async throws -> [DeveloperProcessReading] {
        let worker = Task.detached(priority: .utility) {
            try Self.collect()
        }
        let raw = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        cpuSampler.retain(pids: Set(raw.map(\.pid)))
        let now = DispatchTime.now().uptimeNanoseconds
        return raw.map { process in
            DeveloperProcessReading(
                pid: process.pid, uid: process.uid, executablePath: process.path,
                processStartTime: process.startTime, memoryBytes: process.memoryBytes,
                cpuPercent: cpuSampler.sample(
                    pid: process.pid, executablePath: process.path,
                    processStartTime: process.startTime,
                    userNanoseconds: process.userNanoseconds,
                    systemNanoseconds: process.systemNanoseconds,
                    sampledAtNanoseconds: now))
        }.sorted {
            if $0.memoryBytes == $1.memoryBytes { return $0.pid < $1.pid }
            return $0.memoryBytes > $1.memoryBytes
        }
    }

    func stop(target: DeveloperProcessReading) async -> DeveloperStopOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard target.pid > 1, target.pid != getpid(), target.uid > 0, target.uid == geteuid(),
            target.processStartTime > 0, Self.isEligiblePath(target.executablePath)
        else { return .protected }
        let current: RawDeveloperProcess
        do {
            current = try Self.capture(pid: target.pid)
        } catch let error as DeveloperProcessLookupError {
            switch error {
            case .notFound: return .alreadyExited
            case .permissionDenied: return .permissionDenied
            case .protected: return .protected
            case .unavailable: return .failed
            }
        } catch { return .failed }
        guard Self.matches(current, target) else { return .identityChanged }
        guard !Task.isCancelled else { return .cancelled }

        // Revalidate immediately before this single signal. Every later operation is observation only.
        guard kill(target.pid, SIGTERM) == 0 else {
            if errno == ESRCH { return .alreadyExited }
            if errno == EPERM || errno == EACCES { return .permissionDenied }
            return .failed
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while ProcessInfo.processInfo.systemUptime < deadline {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return .requested }
            guard !Task.isCancelled else { return .requested }
            do {
                let next = try Self.capture(pid: target.pid)
                if next.startTime != target.processStartTime { return .terminated }
                if !Self.matches(next, target) { return .identityChanged }
            } catch DeveloperProcessLookupError.notFound {
                cpuSampler.discard(pid: target.pid)
                return .terminated
            } catch DeveloperProcessLookupError.protected {
                return .identityChanged
            } catch DeveloperProcessLookupError.permissionDenied {
                return .permissionDenied
            } catch {
                // A temporary libproc failure does not establish that the process exited.
                continue
            }
        }
        return .stillRunning
    }

    private static func matches(_ process: RawDeveloperProcess, _ target: DeveloperProcessReading) -> Bool {
        process.pid == target.pid && process.uid == target.uid
            && process.startTime == target.processStartTime
            && process.path == target.executablePath
    }

    private static func collect() throws -> [RawDeveloperProcess] {
        try Task.checkCancellation()
        guard geteuid() > 0 else { return [] }
        let needed = proc_listpids(UInt32(PROC_UID_ONLY), geteuid(), nil, 0)
        guard needed >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var capacity = min(131_072, max(256, Int(needed) / MemoryLayout<pid_t>.size + 256))
        var pids: [pid_t] = []
        while true {
            try Task.checkCancellation()
            pids = Array(repeating: 0, count: capacity)
            let received = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(UInt32(PROC_UID_ONLY), geteuid(), buffer.baseAddress, Int32(buffer.count))
            }
            guard received >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let count = Int(received) / MemoryLayout<pid_t>.size
            if count < capacity || capacity >= 131_072 {
                pids = Array(pids.prefix(min(count, capacity)))
                break
            }
            capacity = min(131_072, capacity * 2)
        }
        var result: [RawDeveloperProcess] = []
        for pid in pids where pid > 1 && pid != getpid() {
            try Task.checkCancellation()
            if let process = try? capture(pid: pid) { result.append(process) }
        }
        return result
    }

    private static func capture(pid: Int32) throws -> RawDeveloperProcess {
        guard pid > 1, pid != getpid() else { throw DeveloperProcessLookupError.protected }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let status = withUnsafeMutablePointer(to: &bsd) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, size)
        }
        guard status == size else { throw lookupError(pid: pid) }
        guard bsd.pbi_status != UInt32(SZOMB) else { throw DeveloperProcessLookupError.notFound }
        guard bsd.pbi_uid > 0, bsd.pbi_uid == geteuid(), bsd.pbi_ruid == geteuid() else {
            throw DeveloperProcessLookupError.protected
        }
        // The SDK's compound PROC_PIDPATHINFO_MAXSIZE macro is not imported into Swift.
        var pathBuffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = pathBuffer.withUnsafeMutableBytes { buffer in
            proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        guard pathLength > 0 else { throw lookupError(pid: pid) }
        let path = String(decoding: pathBuffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        guard isEligiblePath(path) else { throw DeveloperProcessLookupError.protected }

        var usage = rusage_info_v4()
        let usageStatus = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard usageStatus == 0, usage.ri_proc_start_abstime > 0 else { throw lookupError(pid: pid) }
        // Ensure an exec/exit/UID transition during the multi-call capture did not produce a mixed identity.
        var checkedBSD = proc_bsdinfo()
        let checkedStatus = withUnsafeMutablePointer(to: &checkedBSD) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, size)
        }
        guard checkedStatus == size, checkedBSD.pbi_uid == bsd.pbi_uid, checkedBSD.pbi_ruid == bsd.pbi_ruid,
            checkedBSD.pbi_start_tvsec == bsd.pbi_start_tvsec,
            checkedBSD.pbi_start_tvusec == bsd.pbi_start_tvusec
        else {
            throw DeveloperProcessLookupError.unavailable
        }
        pathBuffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let checkedPathLength = pathBuffer.withUnsafeMutableBytes { buffer in
            proc_pidpath(pid, buffer.baseAddress, UInt32(buffer.count))
        }
        guard checkedPathLength > 0,
            String(decoding: pathBuffer.prefix(while: { $0 != 0 }), as: UTF8.self) == path
        else {
            throw DeveloperProcessLookupError.unavailable
        }
        return RawDeveloperProcess(
            pid: pid, uid: bsd.pbi_uid, path: path, startTime: usage.ri_proc_start_abstime,
            memoryBytes: usage.ri_phys_footprint,
            userNanoseconds: usage.ri_user_time, systemNanoseconds: usage.ri_system_time)
    }

    private static func isEligiblePath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        // proc_pidpath may use /private/var while Foundation standardizes it to /var.
        // Preserve the exact kernel path for identity matching instead of treating that alias as unsafe.
        guard path.hasPrefix("/"),
            ["node", "bun", "deno"].contains(url.lastPathComponent.lowercased()),
            !url.pathComponents.contains(where: { $0.lowercased().hasSuffix(".app") }),
            !["/System/", "/bin/", "/sbin/", "/usr/sbin/", "/usr/libexec/"].contains(where: { path.hasPrefix($0) })
        else {
            return false
        }
        var info = stat()
        let status = path.withCString { lstat($0, &info) }
        return status == 0 && info.st_mode & S_IFMT == S_IFREG
            && (info.st_uid == geteuid() || info.st_uid == 0)
            && info.st_mode & 0o002 == 0
    }

    private static func lookupError(pid: Int32) -> DeveloperProcessLookupError {
        let error = errno
        if error == EPERM || error == EACCES { return .permissionDenied }
        if error == ESRCH || (kill(pid, 0) == -1 && errno == ESRCH) { return .notFound }
        return .unavailable
    }
}

private struct RawDeveloperProcess: Sendable {
    var pid: Int32
    var uid: UInt32
    var path: String
    var startTime: UInt64
    var memoryBytes: UInt64
    var userNanoseconds: UInt64
    var systemNanoseconds: UInt64
}

private enum DeveloperProcessLookupError: Error {
    case notFound, permissionDenied, protected, unavailable
}
