import Foundation

/// Turns raw trigger-key events into dictation actions.
///
/// - Hold the key and speak; release to insert (push-to-talk).
/// - A quick tap (shorter than `tapThreshold`) switches to hands-free mode;
///   press the key again to finish (the text is inserted on that release).
/// - Pressing any other key or clicking while holding the trigger means the
///   user was typing a shortcut, so the recording is cancelled.
/// - Escape cancels at any time.
public struct TriggerGesture: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case holding(since: TimeInterval)
        case handsFree
        case handsFreeStopping
    }

    public enum Action: Equatable, Sendable {
        case none
        case start
        case enterHandsFree
        case finish
        case cancel
    }

    public private(set) var state: State = .idle
    public let tapThreshold: TimeInterval

    public init(tapThreshold: TimeInterval = 0.3) {
        self.tapThreshold = tapThreshold
    }

    public mutating func press(at time: TimeInterval) -> Action {
        switch state {
        case .idle:
            state = .holding(since: time)
            return .start
        case .handsFree:
            state = .handsFreeStopping
            return .none
        case .holding, .handsFreeStopping:
            return .none
        }
    }

    public mutating func release(at time: TimeInterval) -> Action {
        switch state {
        case .holding(let since):
            if time - since < tapThreshold {
                state = .handsFree
                return .enterHandsFree
            }
            state = .idle
            return .finish
        case .handsFreeStopping:
            state = .idle
            return .finish
        case .idle, .handsFree:
            return .none
        }
    }

    /// Another key or a mouse click while the trigger key is held.
    public mutating func interrupt() -> Action {
        switch state {
        case .holding:
            state = .idle
            return .cancel
        case .handsFreeStopping:
            // A shortcut typed during hands-free dictation: keep listening.
            state = .handsFree
            return .none
        case .idle, .handsFree:
            return .none
        }
    }

    public mutating func escape() -> Action {
        guard state != .idle else { return .none }
        state = .idle
        return .cancel
    }

    public mutating func reset() {
        state = .idle
    }
}
