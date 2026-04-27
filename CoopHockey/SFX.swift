import AVFoundation

/// Synthesises short percussive sound effects at runtime — no audio files needed.
final class SFX {
    static let shared = SFX()

    private let engine = AVAudioEngine()
    private var pool:   [AVAudioPlayerNode] = []
    private var cursor = 0
    private let poolSize = 6

    // Prevent wall/mallet sounds from stacking up on rapid contacts
    private var lastHitTime: TimeInterval = 0
    private let hitCooldown: TimeInterval = 0.06

    private static let sampleRate: Double = 44100
    private static let format = AVAudioFormat(
        standardFormatWithSampleRate: sampleRate, channels: 1)!

    private init() {
        for _ in 0..<poolSize {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: Self.format)
            pool.append(node)
        }
        try? engine.start()
        pool.forEach { $0.play() }
    }

    // MARK: - Public API

    /// Called when a mallet hits the puck. `speed` is the approach velocity (pts/s).
    func playHit(speed: CGFloat) {
        guard SettingsStore.shared.effectsEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastHitTime >= hitCooldown else { return }
        lastHitTime = now

        let norm   = Float(min(1.0, max(0.15, speed / 700)))
        let buffer = makeBuffer(
            duration:   0.09,
            decayTime:  0.022,
            freqHz:     650 + Double(norm) * 550,
            volume:     0.28 + norm * 0.52,
            noiseRatio: 0.50
        )
        schedule(buffer)
    }

    /// Called when the puck bounces off a wall.
    func playWall() {
        guard SettingsStore.shared.effectsEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastHitTime >= hitCooldown else { return }
        lastHitTime = now

        let buffer = makeBuffer(
            duration:   0.06,
            decayTime:  0.014,
            freqHz:     320,
            volume:     0.16,
            noiseRatio: 0.75
        )
        schedule(buffer)
    }

    /// Called when a goal is scored.
    func playGoal() {
        guard SettingsStore.shared.effectsEnabled else { return }
        let buffer = makeBuffer(
            duration:   0.45,
            decayTime:  0.14,
            freqHz:     440,
            volume:     0.55,
            noiseRatio: 0.06,
            freqSweep:  2.0
        )
        schedule(buffer)
    }

    // MARK: - Private

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        let node = pool[cursor]
        cursor = (cursor + 1) % poolSize
        node.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Synthesises a short percussive tone: exponentially-decayed mix of a
    /// sine wave and white noise, with optional frequency sweep.
    private func makeBuffer(duration: Double,
                            decayTime: Double,
                            freqHz: Double,
                            volume: Float,
                            noiseRatio: Float,
                            freqSweep: Double = 1.0) -> AVAudioPCMBuffer {
        let sr    = Self.sampleRate
        let count = AVAudioFrameCount(sr * duration)
        let buf   = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: count)!
        buf.frameLength = count
        let data = buf.floatChannelData![0]

        for i in 0..<Int(count) {
            let t    = Double(i) / sr
            let env  = Float(exp(-t / decayTime))
            let freq = freqHz * pow(freqSweep, t / duration)
            let sine = Float(sin(2 * Double.pi * freq * t))
            let noise = Float.random(in: -1...1)
            data[i] = env * volume * (noiseRatio * noise + (1 - noiseRatio) * sine)
        }
        return buf
    }
}
