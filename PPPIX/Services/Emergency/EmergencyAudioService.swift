import AVFoundation
import AudioToolbox
import UIKit

/// Toca sirene de emergência — funciona com ringer silenciado via .playback
@MainActor
final class EmergencyAudioService {

    static let shared = EmergencyAudioService()
    private init() {}

    private var player: AVAudioPlayer?
    var isPlaying: Bool { player?.isPlaying ?? false }

    // MARK: - Play

    func playSiren() {
        // Garantir main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.playSiren() }
            return
        }
        guard !isPlaying else { return }

        configureAudioSession()

        // Tentar mp3 direto (caf é gerado no CI mas pode não existir)
        let url = Bundle.main.url(forResource: "sirene", withExtension: "mp3")
               ?? Bundle.main.url(forResource: "sirene", withExtension: "caf")
               ?? Bundle.main.url(forResource: "sirene", withExtension: "wav")

        guard let url = url else {
            // Fallback garantido: vibração repetida
            playVibrationFallback()
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()
        } catch {
            playVibrationFallback()
        }
    }

    // MARK: - Stop

    func stopSiren() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stopSiren() }
            return
        }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio Session
    // .playback ignora o ringer silenciado — único modo confiável para alarmes

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[PPPIX] Audio session error: \(error)")
        }
    }

    private func playVibrationFallback() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
