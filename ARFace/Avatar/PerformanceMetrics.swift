import Darwin
import Foundation
import QuartzCore

/// What the app costs while it runs, for tuning (the debug panel) and before/after comparisons
/// (Benchmark): frames per second, the whole app's CPU use, our per-frame scene update, the GPU
/// time of the frame's last command buffer (where the post-process runs), and the phone's thermal
/// state. Summarized once a second.
nonisolated final class PerformanceMetrics: @unchecked Sendable {
    static let shared = PerformanceMetrics()

    struct Sample {
        /// Seconds since the first sample.
        var time: Double = 0
        var fps: Double = 0
        /// The whole app's CPU use, all threads (100 = one core flat out).
        var cpuPercent: Double = 0
        /// Our scene update each frame (ms): mean and 95th percentile.
        var updateMs: Double = 0
        var updateP95Ms: Double = 0
        /// GPU time of the frame's command buffer the post-process is in (ms, mean).
        var gpuMs: Double = 0
        /// ProcessInfo.ThermalState: 0 normal, 1 fair, 2 serious, 3 critical.
        var thermal: Int = 0
        /// Glass bubbles drawn by the post-process (mean).
        var bubbles: Double = 0
    }

    private let lock = NSLock()
    private var updateTimes: [Double] = []
    private var gpuTimes: [Double] = []
    private var bubbleCounts: [Int] = []
    private var firstSample: Double?
    private var lastSample = CACurrentMediaTime()
    private var lastCPU = PerformanceMetrics.cpuSeconds()
    private var latestSample = Sample()

    var latest: Sample {
        lock.lock(); defer { lock.unlock() }
        return latestSample
    }

    /// One frame's scene update took `ms`.
    func recordUpdate(ms: Double) {
        lock.lock(); defer { lock.unlock() }
        updateTimes.append(ms)
    }

    /// This frame draws `count` glass bubbles.
    func recordBubbles(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        bubbleCounts.append(count)
    }

    /// One frame's GPU work took `ms` (from a command buffer's completion, on any thread).
    func recordGPU(ms: Double) {
        guard ms.isFinite, ms > 0, ms < 1000 else { return }
        lock.lock(); defer { lock.unlock() }
        gpuTimes.append(ms)
    }

    /// Once a second: the summary of that second (nil in between).
    func sampleIfDue() -> Sample? {
        let now = CACurrentMediaTime()
        lock.lock(); defer { lock.unlock() }
        let elapsed = now - lastSample
        guard elapsed >= 1 else { return nil }
        let cpu = Self.cpuSeconds()
        let sorted = updateTimes.sorted()
        var sample = Sample()
        if firstSample == nil { firstSample = now }
        sample.time = now - (firstSample ?? now)
        sample.fps = Double(updateTimes.count) / elapsed
        sample.cpuPercent = (cpu - lastCPU) / elapsed * 100
        sample.updateMs = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
        sample.updateP95Ms = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        sample.gpuMs = gpuTimes.isEmpty ? 0 : gpuTimes.reduce(0, +) / Double(gpuTimes.count)
        sample.thermal = ProcessInfo.processInfo.thermalState.rawValue
        sample.bubbles = bubbleCounts.isEmpty ? 0 : Double(bubbleCounts.reduce(0, +)) / Double(bubbleCounts.count)
        bubbleCounts.removeAll(keepingCapacity: true)
        updateTimes.removeAll(keepingCapacity: true)
        gpuTimes.removeAll(keepingCapacity: true)
        lastSample = now
        lastCPU = cpu
        latestSample = sample
        return sample
    }

    /// CPU seconds the app has used so far, all threads.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}

/// Benchmark mode, for before/after comparisons: launched with FACEFISH_BENCH=1, the fish runs the
/// same moves every time and the metrics are logged once a second to Documents/metrics.csv (from
/// the moment the fish is ready), for 70 seconds.
@MainActor
enum Benchmark {
    static let isOn = ProcessInfo.processInfo.environment["FACEFISH_BENCH"] == "1"
    /// Scene parts switched off for the run (FACEFISH_BENCH_OFF, comma-separated SceneSwitch
    /// names), to see what each costs; not saved.
    static let switchedOff: [SceneSwitch] = (ProcessInfo.processInfo.environment["FACEFISH_BENCH_OFF"] ?? "")
        .split(separator: ",").compactMap { SceneSwitch(rawValue: String($0)) }
    static let duration: Double = 70

    /// Seconds into the run, and the move asked for then.
    private static let schedule: [(Double, SwimMove)] = [
        (10, .lap), (20, .spin), (24, .loop), (29, .blush), (34, .bubbles),
        (40, .hide), (47, .show), (54, .stare), (62, .lap),
    ]
    private static var start: Double?
    private static var nextIndex = 0
    private static var file: FileHandle?

    /// The scheduled move that's due, if any.
    static func move() -> SwimMove? {
        guard isOn, let start, nextIndex < schedule.count else { return nil }
        let (at, move) = schedule[nextIndex]
        guard CACurrentMediaTime() - start >= at else { return nil }
        nextIndex += 1
        return move
    }

    /// Logs one second's metrics (and starts the run on the first).
    static func log(_ sample: PerformanceMetrics.Sample) {
        guard isOn else { return }
        if start == nil {
            start = CACurrentMediaTime()
            let url = URL.documentsDirectory.appending(path: "metrics.csv")
            try? "time,fps,cpu_percent,update_ms,update_p95_ms,gpu_ms,thermal,bubbles,move\n".write(to: url, atomically: true, encoding: .utf8)
            file = try? FileHandle(forWritingTo: url)
            file?.seekToEndOfFile()
        }
        guard let start, CACurrentMediaTime() - start <= duration else {
            try? file?.close()
            file = nil
            return
        }
        let current = schedule[..<nextIndex].last.map { "\($0.1)" } ?? "idle"
        let row = String(format: "%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%d,%.0f,%@\n",
                         CACurrentMediaTime() - start, sample.fps, sample.cpuPercent, sample.updateMs,
                         sample.updateP95Ms, sample.gpuMs, sample.thermal, sample.bubbles, current)
        file?.write(Data(row.utf8))
    }
}
