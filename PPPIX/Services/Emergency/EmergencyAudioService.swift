import AVFoundation
import UIKit

/// Equivalente ao EmergencyService.kt do Android.
/// Toca sirene.mp3 via AVAudioPlayer com categoria de áudio .alarm.
@MainActor
final class EmergencyAudioService {

    static let shared = EmergencyAudioService()
    private init() { configureAudioSession() }

    private var player: AVAudioPlayer?
    var isPlaying: Bool { player?.isPlaying ?? false }

    // MARK: - Play

    func playSiren() {
        guard !isPlaying else { return }

        configureAudioSession()

        // Tenta .caf primeiro (formato iOS nativo), depois .mp3 como fallback
        let url = Bundle.main.url(forResource: "sirene", withExtension: "caf")
               ?? Bundle.main.url(forResource: "sirene", withExtension: "mp3")
        guard let url = url else {
            // Fallback: vibração
            playVibrationFallback()
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1 // loop infinito
            player?.volume = 1.0
            player?.play()
        } catch {
            playVibrationFallback()
        }
    }

    // MARK: - Stop

    func stopSiren() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PPPIX] Audio session error: \(error)")
        }
    }

    private func playVibrationFallback() {
        // Vibra repetidamente como fallback
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}

// AudioServicesPlaySystemSound precisa do import
import AudioToolbox
