struct MouthBubbleBurst {
    struct Emission {
        let delay: Float
        let radiusScale: Float
        let speedScale: Float
    }

    private let emissions: [Emission]
    private var elapsed: Float = 0
    private var nextEmission = 0

    var isComplete: Bool { nextEmission == emissions.count }

    init(count: Int = Int.random(in: 0...11)) {
        precondition(count >= 0, "Bubble count must be nonnegative.")
        guard count > 0 else {
            emissions = []
            return
        }
        let largeCount = Int.random(in: 0...min(3, count))
        let duration = Float.random(in: 0.15...0.35)
        let burstSpeed = Float.random(in: 0.05...0.3)
        let sizes = (0..<count).map { index in
            index < largeCount
                ? Float.random(in: 0.7...1.0)
                : Float.random(in: 0.15...0.3)
        }.shuffled()
        let delays = (0..<count).map { index -> Float in
            if index == 0 { return 0 }
            if index == count - 1 { return duration }
            return Float.random(in: 0...duration)
        }.sorted()
        emissions = zip(delays, sizes).map { delay, size in
            Emission(delay: delay, radiusScale: size, speedScale: burstSpeed * Float.random(in: 0.8...1.2))
        }
    }

    mutating func advance(deltaTime: Float) -> [Emission] {
        elapsed += deltaTime
        let start = nextEmission
        while nextEmission < emissions.count, emissions[nextEmission].delay <= elapsed {
            nextEmission += 1
        }
        return Array(emissions[start..<nextEmission])
    }
}
