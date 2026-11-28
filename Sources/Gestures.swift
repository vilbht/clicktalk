// Gestures on one physical button: a press, a double press and a long press, each with its
// own binding. Pure logic with explicit times, so the tests can drive it.
//
// A button with only a press binding behaves exactly as before: the action starts the
// moment the button goes down, and a held keystroke goes up when it is released.
//
// Once a button also has a double press or a long press, EucLink cannot know what a press
// means the moment it happens, so it waits briefly:
//
//   released quickly, no second press within the window   -> press
//   pressed again within the window                        -> double press
//   still held after the hold delay                        -> long press if bound,
//                                                             otherwise a held press
//
// Every gesture is reported as a begin and an end. A tap reports both at once. A held
// gesture ends when the button is released, which is what push-to-talk needs.

import Foundation

enum Gesture: String, Codable, CaseIterable {
    case press, doublePress, longPress

    var label: String {
        switch self {
        case .press: return "Press"
        case .doublePress: return "Double press"
        case .longPress: return "Long press"
        }
    }

    var symbol: String {
        switch self {
        case .press: return "hand.tap"
        case .doublePress: return "hand.tap.fill"
        case .longPress: return "hand.point.up.left.and.text"
        }
    }

    var explanation: String {
        switch self {
        case .press: return "One press. Instant unless the same button also has a double or long press."
        case .doublePress: return "Two presses in quick succession."
        case .longPress: return "Press and keep holding."
        }
    }
}

struct GestureRecognizer {
    enum Event: Equatable { case begin(Gesture), end(Gesture) }

    /// What to do now, and when to call `timeout(at:)` next (nil: no call needed).
    struct Step: Equatable {
        var events: [Event] = []
        var deadline: TimeInterval?
    }

    /// The gestures that have a binding on this button.
    var bound: Set<Gesture>
    /// How long after a quick release a second press still counts as a double press.
    var window: TimeInterval
    /// How long the button must stay down to count as held.
    var holdDelay: TimeInterval
    /// A second press sooner than this after the first release is the same press reported
    /// twice, which some clickers do, not a double press.
    static let bounce: TimeInterval = 0.04

    private enum Phase: Equatable {
        case idle
        case firstDown(at: TimeInterval)
        case waitingForSecond(releasedAt: TimeInterval)
        case holding(Gesture)
        case ignoringRelease
    }
    private var phase: Phase = .idle

    init(bound: Set<Gesture>, window: TimeInterval = 0.3, holdDelay: TimeInterval = 0.3) {
        self.bound = bound
        self.window = window
        self.holdDelay = holdDelay
    }

    /// True when a press can be acted on the moment it happens.
    var immediate: Bool { !bound.contains(.doublePress) && !bound.contains(.longPress) }

    mutating func down(at t: TimeInterval) -> Step {
        if immediate {
            phase = .holding(.press)
            return Step(events: [.begin(.press)])
        }
        switch phase {
        case .idle:
            phase = .firstDown(at: t)
            return Step(deadline: t + holdDelay)
        case .waitingForSecond(let releasedAt):
            if t - releasedAt < Self.bounce {
                phase = .ignoringRelease
                return Step()
            }
            phase = .holding(.doublePress)
            return Step(events: [.begin(.doublePress)])
        case .firstDown, .holding, .ignoringRelease:
            return Step()
        }
    }

    mutating func up(at t: TimeInterval) -> Step {
        switch phase {
        case .holding(let g):
            phase = .idle
            return Step(events: [.end(g)])
        case .firstDown:
            if bound.contains(.doublePress) {
                phase = .waitingForSecond(releasedAt: t)
                return Step(deadline: t + window)
            }
            phase = .idle
            return Step(events: [.begin(.press), .end(.press)])
        case .ignoringRelease:
            phase = .waitingForSecond(releasedAt: t)
            return Step(deadline: t + window)
        case .idle, .waitingForSecond:
            return Step()
        }
    }

    mutating func timeout(at t: TimeInterval) -> Step {
        switch phase {
        case .firstDown(let at) where t >= at + holdDelay:
            let g: Gesture = bound.contains(.longPress) ? .longPress : .press
            phase = .holding(g)
            return Step(events: [.begin(g)])
        case .waitingForSecond(let releasedAt) where t >= releasedAt + window:
            phase = .idle
            return Step(events: [.begin(.press), .end(.press)])
        default:
            return Step()
        }
    }

    /// Forgets a press in progress, for example when the button disconnects.
    mutating func reset() { phase = .idle }
}
