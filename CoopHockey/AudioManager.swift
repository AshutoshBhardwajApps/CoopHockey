import AVFoundation

final class BGM {
    static let shared = BGM()

    private var player: AVAudioPlayer?
    private var targetVolume: Float = 0.20

    private init() {}

    func play(volume: Float = 0.20) {
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

    func duck()   { setVolume(0.08, fadeDuration: 0.3) }
    func unduck() { setVolume(targetVolume, fadeDuration: 0.5) }
}
