import AppKit
import Combine
import UtterCore

/// Ties the hotkey, recorder, indicator and text insertion together.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case preparing(String)
        case ready
        case listening
        case finishing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing("Starting…")
    @Published private(set) var languages: [LanguageOption] = []
    @Published private(set) var activeLanguage: String?

    let settings = Settings.shared
    let permissions = Permissions()

    private let transcriber = Transcriber()
    private let indicator = IndicatorPanel()
    private let hotkey: HotkeyMonitor
    private var gesture = TriggerGesture()
    private var showIndicator: Task<Void, Never>?
    private var accessibilityPoll: Timer?
    private var subscriptions = Set<AnyCancellable>()

    /// Don't flash the indicator for a trigger key used in a quick shortcut.
    private static let indicatorDelay: Duration = .milliseconds(180)

    init() {
        hotkey = HotkeyMonitor(key: settings.triggerKey)
        hotkey.onPress = { [weak self] in self?.handle(self?.gesture.press(at: Self.now) ?? .none) }
        hotkey.onRelease = { [weak self] in self?.handle(self?.gesture.release(at: Self.now) ?? .none) }
        hotkey.onInterrupt = { [weak self] in self?.handle(self?.gesture.interrupt() ?? .none) }
        hotkey.onEscape = { [weak self] in self?.handle(self?.gesture.escape() ?? .none) }

        transcriber.onPartial = { [weak self] text in self?.indicator.model.text = text }
        transcriber.onLevel = { [weak self] level in self?.indicator.model.level = level }

        settings.$triggerKey.dropFirst().sink { [weak self] key in self?.hotkey.key = key }.store(in: &subscriptions)
        settings.$localeID.dropFirst().removeDuplicates().sink { [weak self] id in
            guard let self, id != self.activeLanguage else { return }
            Task { await self.prepare(id) }
        }.store(in: &subscriptions)

        hotkey.start()
        Task { await bootstrap() }
    }

    var statusText: String {
        switch phase {
        case .preparing(let message): return message
        case .ready:
            guard permissions.accessibility else { return "Needs Accessibility permission" }
            return "Ready · hold \(settings.triggerKey.label) to talk"
        case .listening: return "Listening…"
        case .finishing: return "Inserting…"
        case .failed(let message): return message
        }
    }

    var menuBarSymbol: String {
        switch phase {
        case .preparing: return "hourglass"
        case .ready: return permissions.accessibility ? "waveform" : "exclamationmark.triangle"
        case .listening: return "waveform.badge.mic"
        case .finishing: return "ellipsis"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var isBusy: Bool {
        phase == .listening || phase == .finishing
    }

    func retry() {
        Task { await prepare(settings.localeID) }
    }

    // MARK: - Setup

    private func bootstrap() async {
        languages = await Transcriber.languages()
        await permissions.requestMicrophone()
        if !permissions.accessibility {
            permissions.promptAccessibility()
            pollForAccessibility()
        }
        await prepare(settings.localeID)
    }

    private func prepare(_ id: String) async {
        let name = Locale.current.localizedString(forIdentifier: id) ?? id
        phase = .preparing("Preparing \(name) speech model…")
        do {
            let resolved = try await transcriber.prepare(localeID: id)
            activeLanguage = resolved
            if settings.localeID != resolved { settings.localeID = resolved }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Global key monitors only start delivering events once Accessibility is
    /// granted, so re-register them when that happens.
    private func pollForAccessibility() {
        accessibilityPoll?.invalidate()
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.permissions.refresh()
                if self.permissions.accessibility {
                    timer.invalidate()
                    self.hotkey.start()
                    self.objectWillChange.send()
                }
            }
        }
    }

    // MARK: - Gesture actions

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func handle(_ action: TriggerGesture.Action) {
        switch action {
        case .none: break
        case .start: startListening()
        case .enterHandsFree:
            indicator.model.handsFree = true
            showIndicator?.cancel()
            indicator.show()
        case .finish: finish()
        case .cancel: cancel()
        }
    }

    private func startListening() {
        guard phase == .ready else {
            gesture.reset()
            if case .failed = phase { NSSound.beep() }
            return
        }
        do {
            try transcriber.start()
        } catch {
            gesture.reset()
            phase = .failed(error.localizedDescription)
            return
        }
        phase = .listening
        indicator.model.reset()
        showIndicator = Task { [weak self] in
            try? await Task.sleep(for: Self.indicatorDelay)
            guard let self, !Task.isCancelled, self.phase == .listening else { return }
            self.indicator.show()
        }
    }

    private func finish() {
        guard phase == .listening else { return }
        showIndicator?.cancel()
        phase = .finishing
        indicator.model.finishing = true
        Task {
            let text: String
            do {
                text = try await transcriber.stop()
            } catch {
                text = ""
                NSLog("Utter: transcription failed: \(error.localizedDescription)")
            }
            indicator.hide()
            phase = .ready
            insert(text)
        }
    }

    private func cancel() {
        guard phase == .listening else { return }
        showIndicator?.cancel()
        indicator.hide()
        phase = .finishing
        Task {
            await transcriber.cancel()
            phase = .ready
        }
    }

    private func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let output = settings.addTrailingSpace ? text + " " : text
        permissions.refresh()
        if permissions.accessibility {
            TextInserter.insert(output, restoreClipboard: settings.restoreClipboard)
        } else {
            // Without Accessibility we can't type into other apps; leave it on the clipboard.
            TextInserter.copy(output)
            NSSound.beep()
        }
    }
}
