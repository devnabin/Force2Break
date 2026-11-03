import SwiftUI

enum Palette {
    static let ink = Color(red: 0.10, green: 0.23, blue: 0.20)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let muted = Color(red: 0.43, green: 0.48, blue: 0.44)
    static let accent = Color(red: 0.94, green: 0.58, blue: 0.36)
}

final class AppModel: ObservableObject {
    @Published var focusMinutes = 20
    @Published var breakMinutes = 3
    @Published var loopEnabled = false
    @Published var breakSound: BreakSound = .defaultSound
    @Published var phase: SessionEngine.Phase = .ready
    @Published var remaining = 180
    @Published var breakDuration = 180.0
    @Published var emergencyProgress = 0.0
    @Published var roundNumber = 0
    @Published var completedRounds = 0
    @Published var isLongBreak = false
}

struct Brand: View {
    var light = false
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(light ? Color.white.opacity(0.35) : Palette.ink.opacity(0.25), lineWidth: 1.5)
                Image(systemName: "pause.fill").font(.system(size: 11, weight: .black))
            }.frame(width: 29, height: 29)
            Text("Fore2Break").font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(-0.4)
        }.foregroundStyle(light ? Color.white.opacity(0.85) : Palette.ink)
    }
}

struct SetupView: View {
    static let size = CGSize(width: 284, height: 404)

    @ObservedObject var model: AppModel
    var save: () -> Void
    var preview: (BreakSound) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            durationRow(title: "Focus · minutes", options: SessionEngine.focusOptions, value: $model.focusMinutes)
            durationRow(title: "Break · minutes", options: SessionEngine.breakOptions, value: $model.breakMinutes)
            soundRow
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.loopEnabled.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "repeat").font(.system(size: 12, weight: .medium))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loop").font(.system(size: 12, weight: .medium))
                        Text("Restart when you return").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 5)
                    ZStack(alignment: model.loopEnabled ? .trailing : .leading) {
                        Capsule().fill(model.loopEnabled ? Palette.ink : Palette.ink.opacity(0.18))
                        Circle().fill(.white).padding(2)
                            .frame(width: 20, height: 20)
                    }.frame(width: 34, height: 20)
                }.foregroundStyle(Palette.ink)
            }.buttonStyle(.plain)
                .accessibilityLabel("Loop")
                .accessibilityValue(model.loopEnabled ? "On" : "Off")
                .help("After each break, the first click, key press, mouse movement, or scroll starts the next focus timer.")
            Button(action: save) {
                HStack(spacing: 7) {
                    Image(systemName: model.phase == .ready ? "play.fill" : "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text(model.phase == .ready ? "Start" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 36)
                .foregroundStyle(.white)
                .background(Palette.ink, in: Capsule())
            }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
                .help(model.phase == .ready ? "Start your focus timer and hide this popup" : "Apply these times to the next round")
            Text("Every 4th round includes a 10-min break.")
                .font(.system(size: 9)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.paper)
    }

    private var soundRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                Text("Break sound").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer(minLength: 6)
                Button { preview(model.breakSound) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                        Text("Preview").font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 7).frame(height: 16)
                    .foregroundStyle(Palette.ink)
                    .background(Color.white.opacity(0.9), in: Capsule())
                    .overlay(Capsule().stroke(Palette.ink.opacity(0.08), lineWidth: 1))
                    .contentShape(Capsule())
                }.buttonStyle(.plain)
                    .disabled(model.breakSound == .none)
                    .opacity(model.breakSound == .none ? 0.35 : 1)
                    .accessibilityLabel("Preview \(model.breakSound.title) sound")
                    .help(model.breakSound == .none ? "No sound to preview" : "Play the \(model.breakSound.title.lowercased()) sound once")
            }
            HStack(spacing: 3) {
                ForEach(BreakSound.allCases, id: \.self) { sound in
                    let selected = model.breakSound == sound
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { model.breakSound = sound }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: sound.symbol).font(.system(size: 12, weight: .medium))
                            Text(sound.title).font(.system(size: 10, weight: selected ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .foregroundStyle(selected ? Color.white : Palette.ink)
                        .background {
                            if selected { Capsule().fill(Palette.ink) }
                        }
                        .contentShape(Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Break sound: \(sound.title)")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .help(sound == .none ? "Finish breaks silently" : "Play the \(sound.title.lowercased()) sound when your break ends")
                }
            }.padding(3).background(Color.white.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(Palette.ink.opacity(0.08), lineWidth: 1))
        }
    }

    private func durationRow(title: String, options: [Int], value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { index, minutes in
                    Button { value.wrappedValue = minutes } label: {
                        Text("\(minutes)")
                            .font(.system(size: 13, weight: value.wrappedValue == minutes ? .semibold : .regular, design: .rounded))
                            .frame(maxWidth: .infinity).frame(height: 33)
                            .foregroundStyle(value.wrappedValue == minutes ? Color.white : Palette.ink)
                            .background {
                                if value.wrappedValue == minutes {
                                    Capsule().fill(Palette.ink)
                                }
                            }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(title.components(separatedBy: " · ").first ?? title): \(minutes) minutes")
                        .accessibilityAddTraits(value.wrappedValue == minutes ? [.isSelected] : [])
                    if index < options.count - 1 {
                        Rectangle().fill(Palette.ink.opacity(0.12)).frame(width: 1, height: 12)
                    }
                }
            }.padding(3).background(Color.white.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(Palette.ink.opacity(0.08), lineWidth: 1))
        }
    }
}

struct BreakView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            let inset: CGFloat = compact ? 24 : 40
            ZStack {
                LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.16), Color(red: 0.10, green: 0.26, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(Color.white.opacity(0.035), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.9).offset(x: geometry.size.width * 0.38, y: geometry.size.height * 0.35)
                Circle().stroke(Color.white.opacity(0.035), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.65).offset(x: geometry.size.width * 0.38, y: geometry.size.height * 0.35)
                VStack(spacing: 0) {
                    HStack {
                        Brand(light: true)
                        Spacer(minLength: 10)
                        HStack(spacing: 9) {
                            Text("R: \(model.roundNumber)")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Palette.accent)
                            Text(model.isLongBreak ? "10-MIN LONG BREAK" : "SCREEN BREAK")
                                .font(.system(size: 9, weight: .medium)).tracking(1)
                                .foregroundStyle(.white.opacity(0.65))
                        }.padding(.horizontal, 13).padding(.vertical, 9)
                            .background(Color.white.opacity(0.05), in: Capsule())
                    }
                    Spacer(minLength: 12)
                    ZStack {
                        Circle().fill(Color.white.opacity(0.05)).frame(width: compact ? 36 : 52, height: compact ? 36 : 52)
                        Image(systemName: model.isLongBreak ? "figure.walk" : "leaf")
                            .font(.system(size: compact ? 19 : 25, weight: .light)).foregroundStyle(Palette.accent)
                    }.padding(.bottom, compact ? 10 : 15)
                    Text(model.isLongBreak ? "Four rounds.\nTake a longer pause." : "Step away.\nCome back refreshed.")
                        .font(.system(size: compact ? 31 : 42, weight: .medium, design: .rounded)).tracking(-1.5)
                        .multilineTextAlignment(.center).lineSpacing(0).foregroundStyle(Color(red: 0.94, green: 0.95, blue: 0.88))
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, compact ? 12 : 20)
                    Text("COME BACK IN").font(.system(size: 10, weight: .medium)).tracking(2.6).foregroundStyle(.white.opacity(0.45))
                    Text(Self.timeString(model.remaining))
                        .font(.system(size: compact ? 65 : 82, weight: .ultraLight, design: .rounded)).monospacedDigit()
                        .tracking(-3).foregroundStyle(Color(red: 0.94, green: 0.95, blue: 0.88))
                        .accessibilityLabel("\(model.remaining) seconds remaining")
                    GeometryReader { track in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(Palette.accent).frame(width: track.size.width * max(0, min(1, 1 - Double(model.remaining) / max(1, model.breakDuration))))
                        }
                    }.frame(width: min(320, geometry.size.width * 0.6), height: 3).padding(.top, 6)
                    HStack(alignment: .top, spacing: 12) {
                        prompt(symbol: "eye", title: "20–20–20", text: "Every 20 minutes, look at least 20 feet (6 m) away for at least 20 seconds.", compact: compact)
                        prompt(symbol: "figure.walk", title: "Move a little", text: "If comfortable, take a short walk. Or stretch gently where you are.", compact: compact)
                    }.frame(maxWidth: 620).padding(.top, compact ? 18 : 24)
                    Text(model.isLongBreak ? "A longer reset for your eyes and body. Your screen will be ready when this ends." : "Rest your eyes. Move a little. Your work will be here when you return.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center).padding(.top, compact ? 10 : 15)
                    Spacer(minLength: 12)
                    Text(model.emergencyProgress > 0
                         ? "Emergency exit… keep holding \(Int(ceil(max(0, 3 - model.emergencyProgress * 3))))s"
                         : "Emergency exit: hold ⌃⌥⌘ E for 3 seconds")
                        .font(.system(size: 10, weight: model.emergencyProgress > 0 ? .medium : .regular))
                        .foregroundStyle(model.emergencyProgress > 0 ? Palette.accent : Color.white.opacity(0.3))
                }.padding(inset)
            }
        }.ignoresSafeArea()
    }

    private func prompt(symbol: String, title: String, text: String, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: compact ? 16 : 19, weight: .light))
                .foregroundStyle(Palette.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: compact ? 12 : 14, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Text(text).font(.system(size: compact ? 11 : 12)).lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(compact ? 12 : 16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    static func timeString(_ seconds: Int) -> String {
        String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
