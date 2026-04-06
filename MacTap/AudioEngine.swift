// AudioEngine.swift
// MacTap — AVAudioPlayer-based sound playback with pack support

import AVFoundation
import AppKit

final class AudioEngine {
    static let shared = AudioEngine()

    private var players: [AVAudioPlayer] = []
    private let queue = DispatchQueue(label: "audio", qos: .userInteractive)

    private init() {}

    // MARK: - Play Random Sound from Pack

    func playRandom(pack: SoundPack, volume: Double) {
        let names = pack.allFileNames.shuffled()
        for name in names {
            if let player = makePlayer(fileName: name) {
                play(player: player, volume: volume)
                return
            }
        }
    }

    // MARK: - Preview a specific file

    func preview(fileName: String, volume: Double) {
        if let player = makePlayer(fileName: fileName) {
            play(player: player, volume: volume)
        }
    }

    // MARK: - Internals

    private func makePlayer(fileName: String) -> AVAudioPlayer? {
        guard let url = audioURL(for: fileName) else {
            return nil
        }
        return try? AVAudioPlayer(contentsOf: url)
    }

    private func audioURL(for fileName: String) -> URL? {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") {
            return url
        }

        if let url = Bundle.main.url(forResource: fileName, withExtension: "mp3", subdirectory: "Resources") {
            return url
        }

        return nil
    }

    private func play(player: AVAudioPlayer, volume: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            player.volume = Float(max(0, min(1, volume)))
            player.prepareToPlay()
            player.play()

            // Keep strong reference until playback ends
            self.players.append(player)

            // Clean up finished players periodically
            self.players = self.players.filter { $0.isPlaying || $0.currentTime == 0 }
        }
    }
}
