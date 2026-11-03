import AVFoundation
import Foundation

/// Keeps the user's chosen audio loaded independently of any overlay window.
/// Playback failures must never delay restoring the desktop or starting focus.
@MainActor
final class BreakCompletionSound {
    private var player: AVAudioPlayer?

    var isLoaded: Bool { player != nil }
    var duration: TimeInterval { player?.duration ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "BreakComplete", withExtension: "mp3") else {
            NSLog("Fore2Break: break-complete sound is missing from the app bundle.")
            return
        }
        do {
            let decoded = try AVAudioPlayer(contentsOf: url)
            decoded.numberOfLoops = 0
            decoded.volume = 1
            // Keep the player even if the output route is temporarily unavailable.
            // play() can prepare the audio hardware again when the break ends.
            _ = decoded.prepareToPlay()
            player = decoded
        } catch {
            NSLog("Fore2Break: could not decode break-complete sound: %@", error.localizedDescription)
        }
    }

    @discardableResult
    func play() -> Bool {
        guard let player else { return false }
        player.currentTime = 0
        let started = player.play()
        if !started { NSLog("Fore2Break: break-complete sound could not start playback.") }
        return started
    }
}
