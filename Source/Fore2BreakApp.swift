import AppKit
import ServiceManagement
import SwiftUI

@main
enum Fore2BreakApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class BreakWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) {}
    override func performClose(_ sender: Any?) {}
}

final class CirclePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CircleControl: NSView {
    var start: (() -> Void)?
    var didMove: (() -> Void)?
    private var downPoint = NSPoint.zero
    private var windowOrigin = NSPoint.zero
    private var dragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool { start?(); return true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 8, dy: 8)).fill()
        NSColor.white.withAlphaComponent(0.15).setStroke()
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 14, dy: 14))
        ring.lineWidth = 1
        ring.stroke()
        NSColor(calibratedRed: 0.94, green: 0.58, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 60, y: 56, width: 9, height: 9)).fill()
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: 36, y: 30))
        triangle.line(to: NSPoint(x: 36, y: 50))
        triangle.line(to: NSPoint(x: 51, y: 40))
        triangle.close()
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.90, alpha: 1).setFill()
        triangle.fill()
    }
    override func mouseDown(with event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - downPoint.x, y: current.y - downPoint.y)
        if hypot(delta.x, delta.y) > 4 { dragged = true }
        guard dragged, let window else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(current, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: windowOrigin.x + delta.x, y: windowOrigin.y + delta.y)
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX), frame.maxX - window.frame.width)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - window.frame.height)
        }
        window.setFrameOrigin(origin)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { didMove?() } else if bounds.insetBy(dx: 7, dy: 7).contains(convert(event.locationInWindow, from: nil)) { start?() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = AppModel()
    private var engine = SessionEngine()
    private var resumeGate = AutoResumeGate()
    private var loopEnabled = false
    private var breakSound: BreakSound = .defaultSound
    private var activityCount: () -> UInt64? = { ActivitySource.interactionCount() }
    private let breakCompletionSound = BreakCompletionSound()
    private lazy var playBreakCompletionSound: (BreakSound) -> Void = { [weak self] sound in
        _ = self?.breakCompletionSound.play(sound)
    }
    private let continuousClock = ContinuousClock()
    private let clockOrigin = ContinuousClock.now
    private let dateOrigin = Date()
    private var testAdvance: TimeInterval = 0
    private let testing = CommandLine.arguments.contains("--integration-test")
    private lazy var preferences: UserDefaults = testing
        ? UserDefaults(suiteName: "com.circlebreak.tests.\(UUID().uuidString)")! : .standard
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var setupWindow: NSWindow?
    private var circlePanel: CirclePanel?
    private var breakWindows: [BreakWindow] = []
    private var timer: Timer?
    private var keyMonitor: Any?
    private var previousPresentation: NSApplication.PresentationOptions = []
    private var emergencyStarted: ContinuousClock.Instant?
    private var previousApplication: NSRunningApplication?
    private var isExiting = false

    private var now: Date {
        let elapsed = clockOrigin.duration(to: continuousClock.now).components
        return dateOrigin.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18 + testAdvance)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let focus = preferences.object(forKey: "focusMinutes") as? Int ?? 20
        let pause = preferences.object(forKey: "breakMinutes") as? Int ?? 3
        engine = SessionEngine(focusMinutes: focus, breakMinutes: pause)
        model.focusMinutes = engine.focusMinutes
        model.breakMinutes = engine.breakMinutes
        synchronizeModel(at: now)
        loopEnabled = preferences.bool(forKey: "loopEnabled")
        model.loopEnabled = loopEnabled
        breakSound = BreakSound(preference: preferences.string(forKey: "breakSound"))
        model.breakSound = breakSound
        configureMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        if testing {
            DispatchQueue.main.async { self.runIntegrationTests() }
            return
        }
        if CommandLine.arguments.contains("--test-break-sound") {
            testBreakSound()
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            renderPreviews(at: CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--preview-break") {
            model.remaining = 132
            model.breakDuration = 180
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 750), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Fore2Break · Break preview"
            window.contentView = NSHostingView(rootView: BreakView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            setupWindow = window
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let pulse = Timer(timeInterval: 0.2, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(pulse, forMode: .common)
        timer = pulse
        showSettings(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if engine.phase != .breaking { showSettings(nil) }
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        emergencyStarted = nil
        model.emergencyProgress = 0
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        engine.phase == .breaking && !isExiting ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        resumeGate.cancel()
        restoreDesktop()
        timer?.invalidate()
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "Fore2Break")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.autoenablesItems = false
        stateItem = NSMenuItem(title: "Ready · click your circle", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        settingsItem = NSMenuItem(title: "Focus & break settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let startItem = NSMenuItem(title: "Start focus", action: #selector(startFromMenu), keyEquivalent: "")
        startItem.target = self
        startItem.tag = 8
        menu.addItem(startItem)
        let showCircleItem = NSMenuItem(title: "Show start circle", action: #selector(revealCircle), keyEquivalent: "")
        showCircleItem.target = self
        showCircleItem.tag = 7
        menu.addItem(showCircleItem)
        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = 9
        menu.addItem(loginItem)
        menu.addItem(.separator())
        quitItem = NSMenuItem(title: "Quit Fore2Break", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu
        updateMenu()
        refreshLaunchAtLoginItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // The user can also change this in System Settings › General › Login Items.
        refreshLaunchAtLoginItem()
    }

    private func refreshLaunchAtLoginItem() {
        guard let item = statusItem?.menu?.item(withTag: 9) else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            item.state = .on
            item.toolTip = "Fore2Break opens automatically when you log in"
        case .requiresApproval:
            item.state = .mixed
            item.toolTip = "Allow Fore2Break in System Settings › General › Login Items"
        default:
            item.state = .off
            item.toolTip = "Open Fore2Break automatically when you log in"
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            NSLog("Fore2Break: could not change launch at login: %@", error.localizedDescription)
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshLaunchAtLoginItem()
    }

    @objc func showSettings(_ sender: Any?) {
        guard engine.phase != .breaking else { return }
        resumeGate.cancel()
        circlePanel?.orderOut(nil)
        if let setupWindow { setupWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        model.focusMinutes = engine.focusMinutes
        model.breakMinutes = engine.breakMinutes
        model.loopEnabled = loopEnabled
        model.breakSound = breakSound
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: SetupView.size), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Fore2Break"
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .canJoinAllApplications]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.93, alpha: 1)
        window.contentView = NSHostingView(rootView: SetupView(
            model: model,
            save: { [weak self] in self?.saveSettingsAndClose(start: true) },
            preview: { [weak self] sound in _ = self?.breakCompletionSound.play(sound) }
        ))
        if let frame = (circlePanel?.screen ?? NSScreen.main)?.visibleFrame {
            window.setFrameTopLeftPoint(NSPoint(x: frame.maxX - 30 - SetupView.size.width, y: frame.maxY - 55))
        } else { window.center() }
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateMenu()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === setupWindow { saveSettingsAndClose(); return false }
        return true
    }

    private func saveSettingsAndClose(start: Bool = false) {
        engine.updateSettings(focusMinutes: model.focusMinutes, breakMinutes: model.breakMinutes)
        loopEnabled = model.loopEnabled
        breakSound = model.breakSound
        preferences.set(engine.focusMinutes, forKey: "focusMinutes")
        preferences.set(engine.breakMinutes, forKey: "breakMinutes")
        preferences.set(loopEnabled, forKey: "loopEnabled")
        preferences.set(breakSound.rawValue, forKey: "breakSound")
        setupWindow?.orderOut(nil)
        setupWindow = nil
        if engine.phase == .ready {
            if start { startFocus() } else { showCircle() }
        }
        updateMenu()
    }

    @objc private func revealCircle() {
        if engine.phase == .ready { showCircle() }
    }

    @objc private func startFromMenu() {
        guard engine.phase == .ready else { return }
        if setupWindow != nil { saveSettingsAndClose(start: true) } else { startFocus() }
    }

    private func showCircle() {
        guard !loopEnabled, setupWindow == nil else { circlePanel?.orderOut(nil); return }
        guard engine.phase == .ready, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel: CirclePanel
        if let existing = circlePanel { panel = existing } else {
            panel = CirclePanel(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .canJoinAllApplications]
            panel.isReleasedWhenClosed = false
            let circle = CircleControl(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
            circle.start = { [weak self] in self?.startFocus() }
            circle.didMove = { [weak self] in self?.rememberCirclePosition() }
            panel.contentView = circle
            let visible = screen.visibleFrame
            var origin = NSPoint(x: visible.maxX - 106, y: visible.maxY - 124)
            if preferences.object(forKey: "circleX") != nil {
                origin = NSPoint(x: preferences.double(forKey: "circleX"), y: preferences.double(forKey: "circleY"))
            }
            panel.setFrameOrigin(origin)
            circlePanel = panel
        }
        clampCircleToScreens()
        panel.contentView?.toolTip = resumeGate.isArmed
            ? "Move, click, scroll, or press a key to resume \(engine.focusMinutes) minutes of focus"
            : "Start \(engine.focusMinutes) minutes of focus · drag to move"
        panel.contentView?.setAccessibilityLabel("Start a \(engine.focusMinutes) minute focus session")
        panel.orderFrontRegardless()
    }

    private func rememberCirclePosition() {
        guard let origin = circlePanel?.frame.origin else { return }
        preferences.set(origin.x, forKey: "circleX")
        preferences.set(origin.y, forKey: "circleY")
    }

    private func clampCircleToScreens() {
        guard let panel = circlePanel, let fallback = NSScreen.main ?? NSScreen.screens.first else { return }
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) } ?? fallback
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, visible.minX), visible.maxX - 80), y: min(max(panel.frame.minY, visible.minY), visible.maxY - 80)))
    }

    private func startFocus() {
        guard engine.start(now: now) else { return }
        resumeGate.cancel()
        circlePanel?.orderOut(nil)
        setupWindow?.orderOut(nil)
        setupWindow = nil
        synchronizeModel(at: now)
        updateMenu()
    }

    private func synchronizeModel(at instant: Date) {
        model.phase = engine.phase
        model.remaining = engine.remainingSeconds(now: instant)
        model.roundNumber = engine.currentRound
        model.completedRounds = engine.completedRounds
        model.isLongBreak = engine.isLongBreak
        if engine.phase == .breaking {
            model.breakDuration = engine.phaseDuration ?? Double(engine.breakMinutes * 60)
        }
    }

    @objc private func tick() {
        let instant = now
        let transition = engine.tick(now: instant)
        synchronizeModel(at: instant)
        if transition == .focusEnded { beginBreak() }
        if transition == .breakEnded {
            finishBreak()
            // Only a naturally completed countdown signals a return to work.
            // Emergency exit also restores the desktop, but must stay silent.
            if breakSound != .none { playBreakCompletionSound(breakSound) }
        }
        if engine.phase == .ready, setupWindow == nil, loopEnabled, resumeGate.isArmed,
           resumeGate.consume(activityCount: activityCount()) {
            startFocus()
        }
        if let start = emergencyStarted, engine.phase == .breaking {
            let elapsed = start.duration(to: continuousClock.now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            model.emergencyProgress = min(1, seconds / 3)
            if seconds >= 3 { emergencyExit() }
        }
        updateMenu()
    }

    private func updateMenu() {
        guard statusItem != nil else { return }
        let round = "R: \(engine.currentRound)"
        switch engine.phase {
        case .ready:
            statusItem.button?.title = " \(round) | Ready"
            if resumeGate.isArmed {
                statusItem.button?.toolTip = "Fore2Break · your next interaction starts \(engine.focusMinutes) minutes of focus"
                stateItem.title = "\(round) completed · Loop is waiting for you"
            } else if loopEnabled {
                statusItem.button?.toolTip = "Fore2Break · use Start focus or settings in this menu"
                stateItem.title = "\(round) completed · choose Start focus to begin"
            } else {
                statusItem.button?.toolTip = "Fore2Break · click the floating circle to focus"
                stateItem.title = "\(round) completed · \(engine.focusMinutes) min focus / \(engine.breakMinutes) min break"
            }
        case .focusing:
            let remaining = BreakView.timeString(engine.remainingSeconds(now: now))
            statusItem.button?.title = " \(round) | \(remaining)"
            statusItem.button?.toolTip = "Fore2Break · \(round) · break in \(remaining)"
            stateItem.title = "\(round) · Focusing · \(engine.isLongBreak ? "10-min long break next" : "break in " + remaining)"
        case .breaking:
            let remaining = BreakView.timeString(engine.remainingSeconds(now: now))
            statusItem.button?.title = " \(round) | \(remaining)"
            statusItem.button?.toolTip = "Fore2Break · \(round) · \(engine.isLongBreak ? "Long break" : "Break")"
            stateItem.title = "\(round) · \(engine.isLongBreak ? "10-minute long break" : "Taking a break")"
        }
        settingsItem.isEnabled = engine.phase != .breaking
        quitItem.isEnabled = engine.phase != .breaking
        statusItem.menu?.item(withTag: 7)?.isEnabled = engine.phase == .ready && !loopEnabled && setupWindow == nil
        statusItem.menu?.item(withTag: 8)?.isEnabled = engine.phase == .ready
    }

    private func beginBreak() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        circlePanel?.orderOut(nil)
        setupWindow?.orderOut(nil)
        setupWindow = nil
        // A break ends editing. Unsubmitted choices must not affect its cycle.
        model.focusMinutes = engine.focusMinutes
        model.breakMinutes = engine.breakMinutes
        model.loopEnabled = loopEnabled
        model.breakSound = breakSound
        model.breakDuration = engine.phaseDuration ?? Double(engine.breakMinutes * 60)
        previousPresentation = NSApp.presentationOptions
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.engine.phase == .breaking else { return event }
            let required: NSEvent.ModifierFlags = [.control, .option, .command]
            let modifiersHeld = event.modifierFlags.intersection(required) == required
            if event.type == .keyDown, event.keyCode == 14, modifiersHeld, !event.isARepeat {
                self.emergencyStarted = self.continuousClock.now
            } else if (event.type == .keyUp && event.keyCode == 14) || !modifiersHeld {
                self.emergencyStarted = nil
                self.model.emergencyProgress = 0
            }
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        createBreakWindows()
    }

    private func createBreakWindows() {
        breakWindows.forEach { $0.orderOut(nil); $0.close() }
        breakWindows.removeAll()
        guard engine.phase == .breaking else { return }
        for screen in NSScreen.screens {
            let window = BreakWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.18, blue: 0.16, alpha: 1)
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.isMovable = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .canJoinAllApplications]
            window.contentView = NSHostingView(rootView: BreakView(model: model))
            breakWindows.append(window)
            window.orderFrontRegardless()
        }
        let target = breakWindows.first { $0.screen == NSScreen.main } ?? breakWindows.first
        target?.makeKeyAndOrderFront(nil)
    }

    private func finishBreak(allowAutomaticResume: Bool = true) {
        restoreDesktop()
        resumeGate.cancel()
        if allowAutomaticResume && loopEnabled {
            resumeGate.arm(activityCount: activityCount())
        }
        if !testing { previousApplication?.activate(options: []) }
        previousApplication = nil
        showCircle()
    }

    private func restoreDesktop() {
        emergencyStarted = nil
        model.emergencyProgress = 0
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        breakWindows.forEach { $0.orderOut(nil); $0.close() }
        breakWindows.removeAll()
        NSApp.presentationOptions = previousPresentation
    }

    private func emergencyExit() {
        resumeGate.cancel()
        engine.reset()
        synchronizeModel(at: now)
        finishBreak(allowAutomaticResume: false)
        updateMenu()
    }

    @objc private func wokeUp() { tick() }
    @objc private func displaysChanged() {
        tick()
        if engine.phase == .breaking { createBreakWindows() } else { clampCircleToScreens() }
    }
    @objc private func quit() {
        guard engine.phase != .breaking else { return }
        resumeGate.cancel()
        isExiting = true
        NSApp.terminate(nil)
    }

    private func renderPreviews(at path: String) {
        do {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            @MainActor func save<V: View>(_ content: V, name: String, scale: Double = 1.5) throws {
                let renderer = ImageRenderer(content: content)
                renderer.scale = scale
                guard let cgImage = renderer.cgImage else { throw NSError(domain: "Preview", code: 1) }
                try NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])!
                    .write(to: folder.appendingPathComponent(name))
            }
            model.phase = .ready
            model.focusMinutes = 20
            model.breakMinutes = 3
            model.loopEnabled = false
            model.breakSound = .defaultSound
            try save(SetupView(model: model, save: {}), name: "setup.png", scale: 2)
            model.phase = .breaking
            model.roundNumber = 1
            model.completedRounds = 0
            model.isLongBreak = false
            model.remaining = 132
            model.breakDuration = 180
            try save(BreakView(model: model).frame(width: 1060, height: 750), name: "break.png")
            try save(BreakView(model: model).frame(width: 1060, height: 620), name: "break-compact.png", scale: 1)
            model.roundNumber = 4
            model.completedRounds = 3
            model.isLongBreak = true
            model.remaining = 600
            model.breakDuration = 600
            try save(BreakView(model: model).frame(width: 1060, height: 750), name: "break-long.png")

            // Render the actual menu-bar control with a representative fourth round.
            engine = SessionEngine()
            var previewDate = now
            for _ in 0..<3 {
                engine.start(now: previewDate)
                previewDate = previewDate.addingTimeInterval(1200)
                engine.tick(now: previewDate)
                previewDate = previewDate.addingTimeInterval(180)
                engine.tick(now: previewDate)
            }
            engine.start(now: now)
            testAdvance += 743
            updateMenu()
            if let button = statusItem.button {
                // Use the real status title and its font in a readable menu-bar preview.
                try save(HStack(spacing: 7) {
                    Image(systemName: "circle.dotted.circle").font(.system(size: 17))
                    Text(button.title.trimmingCharacters(in: .whitespaces))
                        .font(Font(button.font ?? .monospacedDigitSystemFont(ofSize: 12, weight: .regular)))
                }.foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(red: 0.52, green: 0.52, blue: 0.53)), name: "menu-bar.png", scale: 3)
            }
            print("Rendered Fore2Break previews in \(path)")
        } catch {
            fputs("Preview failed: \(error)\n", stderr)
            exit(1)
        }
        isExiting = true
        NSApp.terminate(nil)
    }

    private func testBreakSound() {
        let sound = BreakSound.developer
        let duration = breakCompletionSound.duration(for: sound)
        guard breakCompletionSound.isLoaded(for: sound), duration > 0,
              breakCompletionSound.play(sound) else {
            fputs("Fore2Break: bundled sound playback test failed.\n", stderr)
            exit(1)
        }
        print(String(format: "Playing bundled break sound once (%.2f seconds).", duration))
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1) {
            guard !self.breakCompletionSound.isPlaying(for: sound) else {
                fputs("Fore2Break: sound did not finish within its expected duration.\n", stderr)
                exit(1)
            }
            print("Fore2Break bundled sound playback test passed.")
            self.isExiting = true
            NSApp.terminate(nil)
        }
    }

    private func runIntegrationTests() {
        var count = 0
        var soundPlayCount = 0
        var lastPlayedSound: BreakSound?
        var desktopRestoredBeforeSound = true
        playBreakCompletionSound = { [unowned self] sound in
            soundPlayCount += 1
            lastPlayedSound = sound
            desktopRestoredBeforeSound = desktopRestoredBeforeSound
                && self.engine.phase == .ready && self.breakWindows.isEmpty && self.keyMonitor == nil
        }
        // Tests inject totals only; no synthetic system input or permissions.
        var simulatedActivity: UInt64 = 100
        activityCount = { simulatedActivity }
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                engine.reset()
                restoreDesktop()
                exit(1)
            }
            count += 1
        }
        showSettings(nil)
        check(setupWindow?.isVisible == true, "setup is visible")
        check(model.focusMinutes == 20 && model.breakMinutes == 3, "defaults")
        check(!loopEnabled && !model.loopEnabled, "Loop defaults off")
        check(breakSound == .defaultSound && model.breakSound == .defaultSound, "sound defaults to the standard chime")
        check(BreakSound(preference: "unknown") == .defaultSound, "invalid sound preferences use the default")
        check(!resumeGate.isArmed, "opening app never arms automatic restart")
        for sound in [BreakSound.developer, .defaultSound] {
            check(breakCompletionSound.isLoaded(for: sound) && breakCompletionSound.duration(for: sound) > 0, "\(sound.title) audio decodes")
        }
        check(!breakCompletionSound.play(.none), "No sound does not start audio playback")
        check(soundPlayCount == 0, "opening the app is silent")
        for sound in BreakSound.allCases {
            model.breakSound = sound
            saveSettingsAndClose()
            check(BreakSound(preference: preferences.string(forKey: "breakSound")) == sound, "\(sound.title) preference persists")
            model.breakSound = .none
            showSettings(nil)
            check(model.breakSound == sound && breakSound == sound, "reopening settings restores \(sound.title)")
        }
        saveSettingsAndClose(start: true)
        check(engine.phase == .focusing, "Start begins focus immediately")
        check(setupWindow == nil, "Start hides compact popup")
        engine.reset()
        model.phase = .ready
        showCircle()
        check(circlePanel?.isVisible == true, "circle available when ready")
        check(circlePanel?.canBecomeKey == false, "circle preserves work focus")
        showSettings(nil)
        check(circlePanel?.isVisible == false, "settings hides circle so it cannot obscure choices")
        revealCircle()
        check(circlePanel?.isVisible == false, "menu cannot reveal a circle over unsaved settings")
        saveSettingsAndClose()
        check(circlePanel?.isVisible == true, "closing settings restores idle circle")
        startFocus()
        check(engine.phase == .focusing, "circle starts focus")
        check(circlePanel?.isVisible == false, "circle disappears while focusing")
        testAdvance += 1201
        tick()
        check(engine.phase == .breaking, "focus expires into break")
        check(breakWindows.count == NSScreen.screens.count && !breakWindows.isEmpty, "every display covered")
        check(breakWindows.allSatisfy { $0.isVisible && $0.level == .screenSaver }, "break overlays visible at screen saver level")
        check(breakWindows.allSatisfy { $0.frame == $0.screen?.frame }, "break covers full screen bounds")
        check(breakWindows.allSatisfy { $0.canBecomeKey && $0.canBecomeMain }, "break can receive keyboard")
        check(keyMonitor != nil, "keyboard monitor installed")
        check(NSApp.presentationOptions.contains(.disableProcessSwitching), "normal app switching blocked")
        check(!quitItem.isEnabled && !settingsItem.isEnabled, "break has no ordinary quit/settings")
        let deadline = engine.deadline
        displaysChanged()
        check(engine.deadline == deadline, "display changes preserve deadline")
        testAdvance += 181
        tick()
        check(engine.phase == .ready && circlePanel?.isVisible == true, "break returns start circle")
        check(!resumeGate.isArmed, "Loop off leaves automatic restart disarmed")
        check(breakWindows.isEmpty && keyMonitor == nil, "overlay and monitor cleaned up")
        check(NSApp.presentationOptions == previousPresentation, "desktop presentation restored")
        tick()
        check(engine.phase == .ready, "next round waits for click")
        simulatedActivity += 1
        tick()
        check(engine.phase == .ready, "Loop off ignores all activity after break")
        startFocus()
        testAdvance += 1201
        tick()
        let keyWindow = breakWindows.first!
        let modifiers: NSEvent.ModifierFlags = [.control, .option, .command]
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: keyWindow.windowNumber, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14)!
        NSApp.sendEvent(down)
        check(emergencyStarted != nil, "emergency shortcut is detected")
        let up = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: keyWindow.windowNumber, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14)!
        NSApp.sendEvent(up)
        check(emergencyStarted == nil, "releasing emergency shortcut cancels hold")
        NSApp.sendEvent(down)
        emergencyStarted = continuousClock.now.advanced(by: .seconds(-3.1))
        tick()
        check(engine.phase == .ready && breakWindows.isEmpty, "emergency exit restores desktop")

        showSettings(nil)
        model.focusMinutes = 15
        model.breakMinutes = 2
        model.loopEnabled = true
        model.breakSound = .developer
        saveSettingsAndClose(start: true)
        check(loopEnabled && preferences.bool(forKey: "loopEnabled"), "Loop choice is saved")
        check(breakSound == .developer && preferences.string(forKey: "breakSound") == "developer", "Start saves the developer sound")
        check(engine.phase == .focusing && engine.phaseDuration == 900, "Loop requires an initial manual Start")
        let focusDeadline = engine.deadline
        simulatedActivity += 1
        tick()
        check(engine.deadline == focusDeadline, "activity during focus does not reset timer")
        showSettings(nil)
        model.focusMinutes = 25
        model.loopEnabled = false
        model.breakSound = .none
        testAdvance += 901
        tick()
        check(engine.phase == .breaking && engine.phaseDuration == 120, "Loop uses chosen break duration")
        check(setupWindow == nil, "focus expiry dismisses settings so Loop can resume later")
        check(model.focusMinutes == 15 && model.loopEnabled, "break preserves saved settings and discards unsubmitted edits")
        check(model.breakSound == .developer && breakSound == .developer, "break discards an unsubmitted sound change")
        let breakDeadline = engine.deadline
        simulatedActivity += 20
        tick()
        check(engine.phase == .breaking && engine.deadline == breakDeadline && !resumeGate.isArmed, "activity during break cannot restart or shorten it")
        testAdvance += 121
        tick()
        check(engine.phase == .ready && resumeGate.isArmed, "completed break arms Loop")
        check(circlePanel?.isVisible != true, "Loop never shows the floating circle after a break")
        check(statusItem.menu?.item(withTag: 7)?.isEnabled == false, "Loop disables the circle menu item")
        for _ in 0..<5 { tick() }
        check(engine.phase == .ready && resumeGate.isArmed, "Loop waits indefinitely when there is no new activity")
        simulatedActivity += 1
        tick()
        check(engine.phase == .focusing && engine.phaseDuration == 900, "one interaction restarts same focus duration")
        check(engine.focusMinutes == 15 && engine.breakMinutes == 2, "automatic rounds keep saved durations")
        check(!resumeGate.isArmed && circlePanel?.isVisible == false, "automatic restart hides circle and consumes gate")
        let automaticDeadline = engine.deadline
        simulatedActivity += 10
        tick()
        check(engine.deadline == automaticDeadline, "later interactions do not repeatedly reset automatic focus")

        testAdvance += 901
        tick()
        testAdvance += 121
        tick()
        check(engine.phase == .ready && resumeGate.isArmed, "Loop rearms after another full round")
        showSettings(nil)
        check(!resumeGate.isArmed, "settings popup pauses pending automatic restart")
        simulatedActivity += 1
        tick()
        check(engine.phase == .ready && setupWindow != nil, "interacting with settings cannot start focus")
        model.loopEnabled = false
        saveSettingsAndClose()
        check(!loopEnabled && !preferences.bool(forKey: "loopEnabled"), "Loop can be switched off")
        simulatedActivity += 1
        tick()
        check(engine.phase == .ready, "turning Loop off restores manual behavior")

        showSettings(nil)
        model.loopEnabled = true
        saveSettingsAndClose(start: true)
        testAdvance += 901
        tick()
        emergencyExit()
        check(engine.phase == .ready && !resumeGate.isArmed, "emergency exit never arms Loop")
        simulatedActivity += 1
        tick()
        check(engine.phase == .ready, "emergency release remains idle despite activity")
        check(circlePanel?.isVisible != true, "Loop emergency recovery has no floating circle")
        let completedBeforeRecovery = engine.completedRounds
        startFromMenu()
        check(engine.phase == .focusing, "Loop can be restarted from the menu without a circle")
        engine.reset()
        synchronizeModel(at: now)
        check(engine.completedRounds == completedBeforeRecovery, "manual recovery does not invent a completed round")

        // Exercise the real completion hook for every offered duration/mode.
        for minutes in SessionEngine.breakOptions {
            for looping in [false, true] {
                engine.updateSettings(focusMinutes: 10, breakMinutes: minutes)
                loopEnabled = looping
                model.loopEnabled = looping
                breakSound = looping ? .defaultSound : .developer
                model.breakSound = breakSound
                resumeGate.cancel()
                let before = soundPlayCount
                startFocus()
                check(soundPlayCount == before, "manual start is silent")
                testAdvance += 601
                tick()
                check(engine.phase == .breaking && soundPlayCount == before, "focus expiry is silent")
                let scheduledBreak = engine.phaseDuration!
                testAdvance += scheduledBreak - 1
                tick()
                check(engine.phase == .breaking && soundPlayCount == before, "unfinished break is silent")
                testAdvance += 2
                tick()
                check(engine.phase == .ready && soundPlayCount == before + 1, "completed \(minutes)-minute break plays once with Loop \(looping)")
                check(lastPlayedSound == breakSound, "completion plays the saved sound choice")
                check(desktopRestoredBeforeSound, "desktop restoration precedes playback")
                tick()
                wokeUp()
                displaysChanged()
                check(soundPlayCount == before + 1, "repeated ticks/wake/display updates do not replay sound")
                simulatedActivity += 1
                tick()
                check(soundPlayCount == before + 1, "post-break interaction does not replay sound")
                if engine.phase == .ready { startFocus() }
                testAdvance += 601
                tick()
                emergencyExit()
                check(soundPlayCount == before + 1, "emergency exit is silent in both modes")
            }
        }
        for looping in [false, true] {
            loopEnabled = looping
            showSettings(nil)
            model.breakSound = .none
            saveSettingsAndClose(start: true)
            let before = soundPlayCount
            testAdvance += Double(engine.focusMinutes * 60) + 1
            tick()
            check(engine.phase == .breaking, "muting does not prevent the break")
            testAdvance += engine.phaseDuration! + 1
            tick()
            check(engine.phase == .ready && soundPlayCount == before, "No sound keeps completed breaks silent with Loop \(looping)")
            check(resumeGate.isArmed == looping, "No sound preserves Loop behavior")
        }
        breakSound = .defaultSound
        model.breakSound = breakSound
        // Round labels and fourth-round timing must stay in sync across UI.
        engine = SessionEngine()
        loopEnabled = true
        model.loopEnabled = true
        resumeGate.cancel()
        for round in 1...8 {
            startFocus()
            check(model.roundNumber == round && statusItem.button?.title.contains("R: \(round) |") == true, "menu and focus share the current round")
            check(circlePanel?.isVisible != true, "Loop focus has no circle")
            testAdvance += 1201
            tick()
            let expectedBreak = round.isMultiple(of: 4) ? 600.0 : 180.0
            check(engine.phaseDuration == expectedBreak && model.breakDuration == expectedBreak, "fourth-round break replaces the short break")
            check(model.roundNumber == round && model.isLongBreak == round.isMultiple(of: 4), "break screen shows current round and kind")
            check(engine.completedRounds == round - 1, "round stays incomplete until break finishes")
            let before = soundPlayCount
            testAdvance += expectedBreak + 1
            tick()
            check(engine.completedRounds == round && model.completedRounds == round, "completed break increments round once")
            check(soundPlayCount == before + 1, "short and long breaks play one completion sound")
            check(resumeGate.isArmed && circlePanel?.isVisible != true, "Loop rearms without displaying a circle")
            tick()
            check(engine.completedRounds == round, "idle ticks never add rounds")
        }
        showSettings(nil)
        model.loopEnabled = false
        saveSettingsAndClose()
        check(circlePanel?.isVisible == true, "turning Loop off restores the idle circle")
        check(engine.completedRounds == 8, "settings preserve completed round totals")
        showSettings(nil)
        model.loopEnabled = true
        saveSettingsAndClose()
        check(circlePanel?.isVisible != true && !resumeGate.isArmed, "Loop settings-close stays idle without a circle")
        print("Fore2Break integration tests passed (\(count) checks).")
        isExiting = true
        NSApp.terminate(nil)
    }
}
