import Foundation

struct DiagnosisThresholds: Sendable {
    var lowStorageAttentionFraction = 0.10
    var lowStorageCriticalFraction = 0.05
    var highCPUPercent = 85.0
    var memoryAttentionAvailableFraction = 0.08
    var memoryCriticalAvailableFraction = 0.03
}

struct DiagnosisEngine: Sendable {
    var thresholds = DiagnosisThresholds()

    func findings(for snapshot: PerformanceSnapshot, sustainedCPU: Bool = false) -> [Finding] {
        [
            StoragePressureRule(attentionFraction: thresholds.lowStorageAttentionFraction,
                                criticalFraction: thresholds.lowStorageCriticalFraction).evaluate(snapshot),
            ThermalRule().evaluate(snapshot),
            MemoryPressureRule(attentionFraction: thresholds.memoryAttentionAvailableFraction,
                               criticalFraction: thresholds.memoryCriticalAvailableFraction).evaluate(snapshot),
            CPUPressureRule(thresholdPercent: thresholds.highCPUPercent).evaluate(snapshot, sustained: sustainedCPU)
        ]
            .compactMap { $0 }
            .sorted { rank($0.severity) > rank($1.severity) }
    }

    private func rank(_ state: HealthState) -> Int {
        switch state { case .critical: 3; case .attention: 2; case .healthy: 1; case .unavailable: 0 }
    }
}

struct StoragePressureRule: DiagnosticRule {
    var attentionFraction = 0.10
    var criticalFraction = 0.05

    func evaluate(_ snapshot: PerformanceSnapshot) -> Finding? {
        guard snapshot.storage.totalBytes > 0 else { return nil }
        let fraction = Double(snapshot.storage.availableBytes) / Double(snapshot.storage.totalBytes)
        guard fraction < attentionFraction else { return nil }
        let severity: HealthState = fraction < criticalFraction ? .critical : .attention
        return Finding(id: "storage-low", category: .storage, severity: severity,
                       title: "Storage space is low",
                       detail: "Review regenerable data and large files before the disk becomes constrained.",
                       evidence: "\(ByteCountFormatter.string(fromByteCount: Int64(snapshot.storage.availableBytes), countStyle: .file)) available (\(Int(fraction * 100))%).",
                       destination: "Storage",
                       possibleCauses: ["Large files", "Application data", "Caches and temporary files"],
                       confidence: .high, risk: .reviewRequired)
    }
}

struct ThermalRule: DiagnosticRule {
    func evaluate(_ snapshot: PerformanceSnapshot) -> Finding? {
        guard snapshot.thermal.health == .attention || snapshot.thermal.health == .critical else { return nil }
        return Finding(id: "thermal-elevated", category: .thermal, severity: snapshot.thermal.health,
                       title: "Mac is running warm", detail: "Reduce demanding work and let the Mac cool if performance is affected.",
                       evidence: "macOS thermal state: \(snapshot.thermal.state)", destination: "Processes",
                       possibleCauses: ["Sustained CPU or GPU work", "Restricted ventilation", "Warm ambient conditions"],
                       confidence: .high, risk: .low)
    }
}

struct MemoryPressureRule: DiagnosticRule {
    var attentionFraction = 0.08
    var criticalFraction = 0.03

    func evaluate(_ snapshot: PerformanceSnapshot) -> Finding? {
        let severity: HealthState
        if let availableFraction = snapshot.memory.estimatedAvailableFraction {
            guard availableFraction < attentionFraction else { return nil }
            severity = availableFraction < criticalFraction ? .critical : .attention
        } else {
            guard snapshot.memory.pressure == .attention || snapshot.memory.pressure == .critical else { return nil }
            severity = snapshot.memory.pressure
        }
        let evidence = snapshot.memory.estimatedAvailableFraction.map {
            "Estimated free, inactive, and speculative pages are \(Int($0 * 100))% of physical memory; this is not Apple's memory-pressure reading."
        } ?? "Estimated from current VM page availability; this is not Apple's memory-pressure reading."
        return Finding(id: "memory-pressure", category: .memory, severity: severity,
                       title: "Memory pressure is elevated", detail: "Review memory-heavy applications and quit only those you no longer need.",
                       evidence: evidence, destination: "Processes",
                       possibleCauses: ["Concurrent applications", "Memory-intensive development work"],
                       confidence: .low, risk: .reviewRequired)
    }
}

struct CPUPressureRule: DiagnosticRule {
    var thresholdPercent = 85.0

    func evaluate(_ snapshot: PerformanceSnapshot) -> Finding? {
        evaluate(snapshot, sustained: false)
    }

    func evaluate(_ snapshot: PerformanceSnapshot, sustained: Bool) -> Finding? {
        guard sustained, snapshot.cpu.isAvailable, snapshot.cpu.total >= thresholdPercent else { return nil }
        return Finding(id: "cpu-busy", category: .cpu, severity: .attention,
                       title: "CPU activity is high", detail: "Check whether a build, render, or other expected task is running before taking action.",
                       evidence: "CPU activity remained at or above \(Int(thresholdPercent))% for at least three interval samples; latest reading: \(Int(snapshot.cpu.total))%.", destination: "Processes",
                       possibleCauses: ["Build or compile", "Rendering or export", "A background application"],
                       confidence: .medium, risk: .reviewRequired)
    }
}
