import AVFoundation

final class BGM {
    static let shared = BGM()

    /// Resting music level. The one number to turn — call sites deliberately
    /// don't pass their own, so music can be balanced from here alone.
    ///
    /// Dropped from 0.20 when the track changed to the current hard-rock bed:
    /// it carries a full drum kit where the old one didn't, so the same
    /// nominal level sat far more forward against gameplay.
    static let defaultVolume: Float = 0.13

    /// How far to duck under ads and promos, as a fraction of the resting
    /// level rather than an absolute — so changing `defaultVolume` keeps the
    /// ducking proportionate instead of silently becoming a no-op.
    private static let duckFraction: Float = 0.40

    private var player: AVAudioPlayer?
    private var targetVolume: Float = BGM.defaultVolume

    private init() {}

    func play(volume: Float = BGM.defaultVolume) {
        targetVolume = volume
        guard let url = Bundle.main.url(forResource: "COOPbackground", withExtension: "mp3") else { return }
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
        }
        player?.volume = volume
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func setVolume(_ volume: Float, fadeDuration: TimeInterval = 0.4) {
        player?.setVolume(volume, fadeDuration: fadeDuration)
    }

    func duck()   { setVolume(targetVolume * Self.duckFraction, fadeDuration: 0.3) }
    func unduck() { setVolume(targetVolume, fadeDuration: 0.5) }
}
