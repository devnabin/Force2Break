import AVFoundation
import Foundation

enum BreakSound: String, CaseIterable {
    case none
    case developer
    case defaultSound = "default"

    init(preference: String?) {
        self = preference.flatMap(Self.init(rawValue:)) ?? .defaultSound
    }

    var title: String {
        switch self {
        case .none: return "No sound"
        case .developer: return "Developer"
        case .defaultSound: return "Default"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "speaker.slash"
        case .developer: return "waveform"
        case .defaultSound: return "bell"
        }
    }
}

/// Keeps the user's chosen audio loaded independently of any overlay window.
/// Playback failures must never delay restoring the desktop or starting focus.
@MainActor
final class BreakCompletionSound {
    private var players: [BreakSound: AVAudioPlayer] = [:]

    func isLoaded(for sound: BreakSound) -> Bool { players[sound] != nil }
    func duration(for sound: BreakSound) -> TimeInterval { players[sound]?.duration ?? 0 }
    func isPlaying(for sound: BreakSound) -> Bool { players[sound]?.isPlaying ?? false }

    init(bundle: Bundle = .main) {
        load(.defaultSound, from: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"))
        if let url = bundle.url(forResource: "BreakComplete", withExtension: "mp3") {
            load(.developer, from: url)
        } else {
            NSLog("Fore2Break: developer sound is missing from the app bundle.")
        }
    }

    private func load(_ sound: BreakSound, from url: URL) {
        do {
            let decoded = try AVAudioPlayer(contentsOf: url)
            decoded.numberOfLoops = 0
            decoded.volume = 1
            // Keep the player even if the output route is temporarily unavailable.
            // play() can prepare the audio hardware again when the break ends.
            _ = decoded.prepareToPlay()
            players[sound] = decoded
        } catch {
            NSLog("Fore2Break: could not decode %@ sound: %@", sound.title, error.localizedDescription)
        }
    }

    @discardableResult
    func play(_ sound: BreakSound) -> Bool {
        players.values.forEach { $0.stop() }
        guard sound != .none, let player = players[sound] else { return false }
        player.currentTime = 0
        let started = player.play()
        if !started { NSLog("Fore2Break: %@ sound could not start playback.", sound.title) }
        return started
    }
}
