import Accelerate
import AVFoundation
import OSLog
import Synchronization

/// Microphone levels, each normalized to 0...1 between `AudioSpectrumAnalyzer.floorDecibels`
/// and `AudioSpectrumAnalyzer.ceilingDecibels`.
nonisolated struct AudioLevels: Sendable, Equatable {
    var overall: Float = 0
    var low: Float = 0
    var mid: Float = 0
    var high: Float = 0

    static let silent = AudioLevels()
}

/// Streams the microphone's overall level and low/mid/high band levels; safe to poll every render frame.
final class AudioLevelMonitor {
    enum Status: Equatable {
        case stopped
        case requestingPermission
        case running
        case denied
        case failed(String)
    }

    private(set) var status: Status = .stopped

    private let engine = AVAudioEngine()
    private let analyzer = AudioSpectrumAnalyzer()
    private let logger = Logger(subsystem: "ARFace", category: "Audio")
    private var startTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var tapInstalled = false

    var sensitivityDecibels: Float {
        get { analyzer.sensitivityDecibels }
        set { analyzer.sensitivityDecibels = newValue }
    }

    func start() {
        guard startTask == nil, status != .running else { return }
        status = .requestingPermission
        startTask = Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard !Task.isCancelled else { return }
            startTask = nil
            guard granted else {
                logger.error("Microphone permission denied; audio-reactive bubbles are disabled.")
                status = .denied
                return
            }
            startEngine()
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        let wasRunning = tapInstalled
        stopEngine()
        if wasRunning {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        status = .stopped
    }

    /// Latest smoothed levels; silent unless the microphone is running.
    func snapshot() -> AudioLevels {
        status == .running ? analyzer.levels : .silent
    }

    private func startEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw CocoaError(.featureUnsupported)
            }
            analyzer.reset(sampleRate: format.sampleRate)
            Self.installTap(on: input, format: format, analyzer: analyzer)
            tapInstalled = true
            engine.prepare()
            try engine.start()
            observeSession()
            status = .running
            logger.info("Microphone level monitoring started at \(format.sampleRate) Hz.")
        } catch {
            stopEngine()
            status = .failed(error.localizedDescription)
            logger.error("Microphone level monitoring unavailable: \(error.localizedDescription)")
        }
    }

    private func stopEngine() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        analyzer.reset(sampleRate: nil)
    }

    /// Route changes and interruptions stop the engine; restart it while monitoring is wanted.
    private func observeSession() {
        let center = NotificationCenter.default
        let restart: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.status == .running else { return }
                self.stopEngine()
                self.startEngine()
            }
        }
        observers = [
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
                restart()
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
                let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if rawType == AVAudioSession.InterruptionType.ended.rawValue {
                    restart()
                }
            },
        ]
    }

    /// Nonisolated so the tap block runs on the audio thread instead of being bound to the main actor.
    nonisolated private static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        analyzer: AudioSpectrumAnalyzer
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            analyzer.process(buffer)
        }
    }
}

/// Measures overall RMS and low/mid/high band energy of microphone buffers.
///
/// `process` runs on the audio tap's thread, which delivers buffers serially; `reset` is only
/// called while no tap is installed. Published levels are exchanged under a lock.
nonisolated final class AudioSpectrumAnalyzer: @unchecked Sendable {
    static let fftSize = 2048
    static let lowBand: ClosedRange<Double> = 20...250
    static let midBand: ClosedRange<Double> = 250...2_000
    static let highBand: ClosedRange<Double> = 2_000...10_000
    static let floorDecibels: Float = -60
    static let ceilingDecibels: Float = -10
    static let defaultSensitivityDecibels: Float = 12
    static let sensitivityRange: ClosedRange<Float> = 0...36
    private static let attackTime: Float = 0.03
    private static let releaseTime: Float = 0.25
    private static let logInterval: Float = 0.25
    private static let window = vDSP.window(
        ofType: Float.self,
        usingSequence: .hanningDenormalized,
        count: fftSize,
        isHalfWindow: false
    )
    /// One-sided Parseval scaling: a band's summed power becomes the mean square it contributes.
    private static let powerScale = 2 / (Float(fftSize) * vDSP.sumOfSquares(window))

    private let published = Mutex(AudioLevels.silent)
    private let sensitivity = Mutex(defaultSensitivityDecibels)
    private let logger = Logger(subsystem: "ARFace", category: "Audio")
    private let zeros = [Float](repeating: 0, count: fftSize)
    private let dft = try? vDSP.DiscreteFourierTransform(
        previous: nil,
        count: fftSize,
        direction: .forward,
        transformType: .complexComplex,
        ofType: Float.self
    )
    private var history = [Float](repeating: 0, count: fftSize)
    private var sampleRate: Double = 48_000
    private var smoothed = AudioLevels.silent
    private var timeSinceLog: Float = 0

    var levels: AudioLevels { published.withLock { $0 } }

    var sensitivityDecibels: Float {
        get { sensitivity.withLock { $0 } }
        set { sensitivity.withLock { $0 = min(max(newValue, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound) } }
    }

    func reset(sampleRate: Double?) {
        if let sampleRate { self.sampleRate = sampleRate }
        history = [Float](repeating: 0, count: Self.fftSize)
        smoothed = .silent
        timeSinceLog = 0
        published.withLock { $0 = .silent }
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0, let dft else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let size = Self.fftSize
        if samples.count >= size {
            history = Array(samples.suffix(size))
        } else {
            history.removeFirst(samples.count)
            history.append(contentsOf: samples)
        }

        let windowedSamples: [Float] = vDSP.multiply(history, Self.window)
        var spectrumReal = [Float](repeating: 0, count: size)
        var spectrumImaginary = [Float](repeating: 0, count: size)
        dft.transform(
            inputReal: windowedSamples,
            inputImaginary: zeros,
            outputReal: &spectrumReal,
            outputImaginary: &spectrumImaginary
        )
        let binWidth = sampleRate / Double(size)
        let sensitivityDecibels = self.sensitivityDecibels
        func bandLevel(_ band: ClosedRange<Double>) -> Float {
            let lower = max(1, Int((band.lowerBound / binWidth).rounded(.up)))
            let upper = min(size / 2 - 1, Int((band.upperBound / binWidth).rounded(.down)))
            guard lower <= upper else { return 0 }
            var power: Float = 0
            for bin in lower...upper {
                let real = spectrumReal[bin]
                let imaginary = spectrumImaginary[bin]
                power += real * real + imaginary * imaginary
            }
            return Self.normalized(
                decibels: 10 * log10(max(power * Self.powerScale, 1e-12)),
                sensitivityDecibels: sensitivityDecibels
            )
        }

        let rms = vDSP.rootMeanSquare(samples)
        let measured = AudioLevels(
            overall: Self.normalized(decibels: 20 * log10(max(rms, 1e-6)), sensitivityDecibels: sensitivityDecibels),
            low: bandLevel(Self.lowBand),
            mid: bandLevel(Self.midBand),
            high: bandLevel(Self.highBand)
        )

        let deltaTime = Float(Double(samples.count) / sampleRate)
        func smooth(_ previous: Float, _ target: Float) -> Float {
            let time = target > previous ? Self.attackTime : Self.releaseTime
            return previous + (1 - exp(-deltaTime / time)) * (target - previous)
        }
        smoothed = AudioLevels(
            overall: smooth(smoothed.overall, measured.overall),
            low: smooth(smoothed.low, measured.low),
            mid: smooth(smoothed.mid, measured.mid),
            high: smooth(smoothed.high, measured.high)
        )
        let levels = smoothed
        published.withLock { $0 = levels }

        timeSinceLog += deltaTime
        if timeSinceLog >= Self.logInterval {
            timeSinceLog = 0
            logger.debug("Audio levels overall=\(levels.overall, format: .fixed(precision: 2)) low=\(levels.low, format: .fixed(precision: 2)) mid=\(levels.mid, format: .fixed(precision: 2)) high=\(levels.high, format: .fixed(precision: 2))")
        }
    }

    private static func normalized(decibels: Float, sensitivityDecibels: Float) -> Float {
        let boostedDecibels = decibels + sensitivityDecibels
        return min(max((boostedDecibels - floorDecibels) / (ceilingDecibels - floorDecibels), 0), 1)
    }
}
