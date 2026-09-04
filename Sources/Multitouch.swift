import AppKit

// MARK: - Raw trackpad data layout
//
// macOS offers no public path to raw trackpad touches: NSEvent hands over
// already-interpreted gestures and does not report the finger count of a tap.
// So we take the private MultitouchSupport framework and bind to it through
// the runtime. It needs no permissions — verified.

private struct MTPoint { var x: Float = 0; var y: Float = 0 }
private struct MTReadout { var pos = MTPoint(); var vel = MTPoint() }

/// A single touch. The field layout matches what the framework hands back;
/// we only need the position and the contact size, the rest is padding.
private struct MTTouch {
    var frame: Int32 = 0
    var timestamp: Double = 0
    var identifier: Int32 = 0, state: Int32 = 0, foo3: Int32 = 0, foo4: Int32 = 0
    var normalized = MTReadout()
    var size: Float = 0
    var zero1: Int32 = 0
    var angle: Float = 0, majorAxis: Float = 0, minorAxis: Float = 0
    var mm = MTReadout()
    var zero2: (Int32, Int32) = (0, 0)
    var unk2: Float = 0
}

// The touch struct is not representable in Objective-C, so the callback
// signature takes a raw pointer and reinterprets the memory in place.
private typealias FrameCallback = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?,
                                                  Int32, Double, Int32) -> Int32

/// Which gesture was recognised.
///
/// The set is derived from what can be read reliably out of the raw trackpad
/// data: each finger's position, its drift, the distance between fingers and
/// the angle between them. Gestures the system claims for itself are marked —
/// they can be bound, but they will not always fire.
enum Gesture: String, CaseIterable, Identifiable {
    case tap2, tap3, tap4, tap5
    case doubleTap2, doubleTap3, doubleTap4
    case hold2, hold3, hold4
    case tipLeft, tipRight, tipLeft2, tipRight2
    case swipeUp3, swipeDown3, swipeLeft3, swipeRight3
    case swipeUp4, swipeDown4, swipeLeft4, swipeRight4
    case swipeUp5, swipeDown5, swipeLeft5, swipeRight5
    case pinchIn2, pinchOut2, pinchIn3, pinchOut3, pinchIn4, pinchOut4
    case rotateLeft, rotateRight
    case cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight

    var id: String { rawValue }

    /// The section in settings: a flat list of forty rows is unreadable.
    var family: String {
        switch self {
        case .tap2, .tap3, .tap4, .tap5:                 return "Taps"
        case .doubleTap2, .doubleTap3, .doubleTap4:      return "Double taps"
        case .hold2, .hold3, .hold4:                     return "Hold"
        case .tipLeft, .tipRight, .tipLeft2, .tipRight2: return "Tap beside a held finger"
        case .swipeUp3, .swipeDown3, .swipeLeft3, .swipeRight3,
             .swipeUp4, .swipeDown4, .swipeLeft4, .swipeRight4,
             .swipeUp5, .swipeDown5, .swipeLeft5, .swipeRight5: return "Swipes"
        case .pinchIn2, .pinchOut2, .pinchIn3, .pinchOut3,
             .pinchIn4, .pinchOut4:                      return "Pinch"
        case .rotateLeft, .rotateRight:                  return "Rotate"
        case .cornerTopLeft, .cornerTopRight,
             .cornerBottomLeft, .cornerBottomRight:      return "Corner tap"
        }
    }

    var title: String {
        switch self {
        case .tap2: return "Tap 2 fingers"
        case .tap3: return "Tap 3 fingers"
        case .tap4: return "Tap 4 fingers"
        case .tap5: return "Tap 5 fingers"
        case .doubleTap2: return "Double tap 2 fingers"
        case .doubleTap3: return "Double tap 3 fingers"
        case .doubleTap4: return "Double tap 4 fingers"
        case .hold2: return "Hold 2 fingers"
        case .hold3: return "Hold 3 fingers"
        case .hold4: return "Hold 4 fingers"
        case .tipLeft:   return "Hold 1, tap on its left"
        case .tipRight:  return "Hold 1, tap on its right"
        case .tipLeft2:  return "Hold 2, tap on their left"
        case .tipRight2: return "Hold 2, tap on their right"
        case .swipeUp3: return "Swipe up, 3 fingers"
        case .swipeDown3: return "Swipe down, 3 fingers"
        case .swipeLeft3: return "Swipe left, 3 fingers"
        case .swipeRight3: return "Swipe right, 3 fingers"
        case .swipeUp4: return "Swipe up, 4 fingers"
        case .swipeDown4: return "Swipe down, 4 fingers"
        case .swipeLeft4: return "Swipe left, 4 fingers"
        case .swipeRight4: return "Swipe right, 4 fingers"
        case .swipeUp5: return "Swipe up, 5 fingers"
        case .swipeDown5: return "Swipe down, 5 fingers"
        case .swipeLeft5: return "Swipe left, 5 fingers"
        case .swipeRight5: return "Swipe right, 5 fingers"
        case .pinchIn2: return "Pinch in, 2 fingers"
        case .pinchOut2: return "Pinch out, 2 fingers"
        case .pinchIn3: return "Pinch in, 3 fingers"
        case .pinchOut3: return "Pinch out, 3 fingers"
        case .pinchIn4: return "Pinch in, 4 fingers"
        case .pinchOut4: return "Pinch out, 4 fingers"
        case .rotateLeft: return "Rotate anticlockwise"
        case .rotateRight: return "Rotate clockwise"
        case .cornerTopLeft: return "Tap top-left corner"
        case .cornerTopRight: return "Tap top-right corner"
        case .cornerBottomLeft: return "Tap bottom-left corner"
        case .cornerBottomRight: return "Tap bottom-right corner"
        }
    }

    /// Whether the system claims this gesture. Such ones can be bound, but
    /// interception is unreliable: macOS takes some events before we see them.
    var conflictsWithSystem: Bool {
        switch self {
        case .tap2: return true                        // secondary click
        case .pinchIn2, .pinchOut2: return true         // zoom
        case .pinchIn4, .pinchOut4: return true         // Launchpad and Show Desktop
        case .rotateLeft, .rotateRight: return true     // rotation in viewers
        case .swipeUp3, .swipeDown3, .swipeLeft3, .swipeRight3,
             .swipeUp4, .swipeDown4, .swipeLeft4, .swipeRight4:
            return true                                 // spaces and Mission Control
        default: return false
        }
    }
}

/// Watching the trackpad and recognising gestures.
///
/// The framework callback is a plain function pointer; a closure with
/// captures cannot be passed there. So the state lives in a singleton.
final class TouchWatcher {
    static let shared = TouchWatcher()

    /// Called when a gesture is recognised.
    var onGesture: ((Gesture) -> Void)?
    /// Which gestures are bound. Needed for the double tap: the single one
    /// has to be held back to wait for the second, and that is only worth
    /// doing when the double is bound to something.
    ///
    /// A set, deliberately, rather than a closure that reads the settings.
    /// Recognition runs on the trackpad thread, and every attempt to ask the
    /// main thread from there crashed the app: MainActor.assumeIsolated is an
    /// assertion that we are already on the main actor, not a hop onto it.
    private var bound: Set<String> = []
    private let boundLock = NSLock()

    func setBound(_ gestures: Set<String>) {
        boundLock.lock()
        bound = gestures
        boundLock.unlock()
    }

    private func isBound(_ gesture: Gesture) -> Bool {
        boundLock.lock()
        defer { boundLock.unlock() }
        return bound.contains(gesture.rawValue)
    }

    // Thresholds, chosen by reasoning. Drift and distances are given as
    // fractions of the trackpad, where 1.0 is its full width or height.
    private let tapDuration: TimeInterval = 0.30
    private let holdDuration: TimeInterval = 0.60
    private let maxTapDrift: Float = 0.06
    private let minSwipe: Float = 0.15
    private let minPinch: Float = 0.10
    private let minRotation: Float = 25          // degrees
    private let cornerZone: Float = 0.22
    private let doubleGap: TimeInterval = 0.35
    private let cooldown: TimeInterval = 0.35

    // Guards against accidental triggers.
    //
    /// A contact larger than this is a palm or the edge of a hand, not a
    /// fingertip. The framework reports contact size, and a palm's is several
    /// times bigger.
    private let maxTouchSize: Float = 1.6
    /// Too faint a contact is a ghost: a finger hovering over the surface.
    private let minTouchSize: Float = 0.05
    /// The fingers of a real tap land almost together. If more time passed
    /// between the first and the last, it is a hand settling, not a gesture.
    private let maxLandingSpread: TimeInterval = 0.12
    /// How long to stay silent after typing: while typing, hands brush the
    /// trackpad constantly and almost every contact there is accidental.
    private let typingGuard: TimeInterval = 0.6

    /// How much earlier the anchor finger must land for a touch to count as
    /// made "beside it". Without this threshold an ordinary two-finger tap —
    /// the system secondary click — would fall into our gestures.
    /// The anchor must be down noticeably earlier. 0.09 s was too small: in
    /// ordinary scrolling the fingers land a tenth of a second apart, and the
    /// first was wrongly taken for an anchor.
    ///
    /// The gesture has no fallback: if evaluateLift() does not accept the
    /// anchor, classify() will not pick it up either — there the gesture is
    /// rejected once duration exceeds tapDuration (0.3 s) from the first
    /// contact to the last, and an anchor finger usually rests longer. So an
    /// inflated threshold does not soften the trigger, it silences the gesture
    /// altogether. 0.25 s demanded an unnaturally long pause between putting
    /// the finger down and tapping — lowered to a safe minimum above the
    /// spread seen in ordinary scrolling.
    private let anchorLead: TimeInterval = 0.15
    private let minSideways: Float = 0.02

    private var handle: UnsafeMutableRawPointer?
    private var device: AnyObject?
    private var lastFired = Date.distantPast

    /// Whether the guards are on. Set from settings and read on the trackpad
    /// thread, hence the lock.
    private var guardsOn = true
    private let guardsLock = NSLock()

    func setGuardsEnabled(_ on: Bool) {
        guardsLock.lock(); guardsOn = on; guardsLock.unlock()
    }

    private var guardsEnabled: Bool {
        guardsLock.lock(); defer { guardsLock.unlock() }
        return guardsOn
    }

    /// One finger on the trackpad, tracked across frames.
    private struct Contact {
        let began: Date
        let startX: Float, startY: Float
        var x: Float, y: Float
        var drift: Float
    }

    private var contacts: [Int32: Contact] = [:]

    /// A summary of the whole touch — from the first finger down to the last lifted.
    private struct Session {
        var began: Date
        var peakFingers = 0
        var startCentre: (Float, Float) = (0, 0)
        var endCentre: (Float, Float) = (0, 0)
        var startSpread: Float = 0
        var endSpread: Float = 0
        var startAngle: Float = .nan
        var endAngle: Float = .nan
        var measured = false          // initial values are not taken immediately
        /// When the first and last finger landed. The gap between them shows
        /// whether it was a tap made at once or a hand settling piecemeal.
        var firstLanding: Date
        var lastLanding: Date
        var tipFired = false          // a tip-tap gesture was already emitted
    }
    private var session: Session?

    // For the double tap.
    private var pendingTap: (gesture: Gesture, at: Date)?
    private var pendingWork: DispatchWorkItem?

    private init() {}

    func start() {
        guard handle == nil else { return }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            NSLog("TapShortcuts: the multitouch framework failed to load")
            return
        }
        self.handle = handle

        typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
        typealias Register = @convention(c) (UnsafeRawPointer, FrameCallback) -> Void
        typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Void

        guard let listSym = dlsym(handle, "MTDeviceCreateList"),
              let regSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart") else {
            NSLog("TapShortcuts: the framework is missing the symbols we need")
            return
        }

        let createList = unsafeBitCast(listSym, to: CreateList.self)
        guard let list = createList()?.takeRetainedValue() as? [AnyObject],
              let device = list.first else {
            NSLog("TapShortcuts: no multitouch device found")
            return
        }
        self.device = device

        let ref = Unmanaged.passUnretained(device).toOpaque()
        unsafeBitCast(regSym, to: Register.self)(ref) { _, raw, count, _, _ in
            TouchWatcher.shared.handle(raw: raw, count: Int(count))
            return 0
        }
        unsafeBitCast(startSym, to: Start.self)(ref, 0)
    }

    func stop() {
        guard let handle, let device else { return }
        if let stopSym = dlsym(handle, "MTDeviceStop") {
            typealias Stop = @convention(c) (UnsafeRawPointer, Int32) -> Void
            unsafeBitCast(stopSym, to: Stop.self)(Unmanaged.passUnretained(device).toOpaque(), 0)
        }
        self.device = nil
    }

    // MARK: - Frame handling

    /// Frames arrive thick and fast, so this only accumulates state and does no heavy work.
    fileprivate func handle(raw: UnsafeRawPointer?, count: Int) {
        let now = Date()
        var present = Set<Int32>()
        var points: [(Float, Float)] = []

        if count > 0, let raw {
            let touches = raw.assumingMemoryBound(to: MTTouch.self)
            for i in 0..<count {
                let t = touches[i]
                // Palms and ghosts are filtered here, before any analysis:
                // otherwise a hand resting on the trackpad would count as
                // fingers and turn every touch into a multi-finger gesture.
                guard t.size >= minTouchSize, t.size <= maxTouchSize else { continue }
                let id = t.identifier
                let x = t.normalized.pos.x, y = t.normalized.pos.y
                present.insert(id)
                points.append((x, y))

                if var existing = contacts[id] {
                    existing.x = x; existing.y = y
                    // Drift is measured from the start, not between frames:
                    // a finger's tremor would accumulate and drown recognition.
                    existing.drift = max(existing.drift,
                                         abs(x - existing.startX) + abs(y - existing.startY))
                    contacts[id] = existing
                } else {
                    contacts[id] = Contact(began: now, startX: x, startY: y, x: x, y: y, drift: 0)
                    session?.lastLanding = now
                }
            }

            if !points.isEmpty {
                if session == nil { session = Session(began: now, firstLanding: now, lastLanding: now) }
                update(&session!, with: points, at: now)
            }
        }

        for (id, contact) in contacts where !present.contains(id) {
            contacts[id] = nil
            evaluateLift(of: contact, at: now)
        }

        if contacts.isEmpty, let finished = session {
            session = nil
            classify(finished, at: now)
        }
    }

    private func update(_ s: inout Session, with points: [(Float, Float)], at now: Date) {
        s.peakFingers = max(s.peakFingers, points.count)

        let cx = points.map(\.0).reduce(0, +) / Float(points.count)
        let cy = points.map(\.1).reduce(0, +) / Float(points.count)
        // Spread is the mean distance of the fingers from their centroid.
        // Its change tells a pinch in from a pinch out.
        let spread = points
            .map { hypot($0.0 - cx, $0.1 - cy) }
            .reduce(0, +) / Float(points.count)

        var angle = Float.nan
        if points.count >= 2 {
            let dx = points[1].0 - points[0].0, dy = points[1].1 - points[0].1
            angle = atan2(dy, dx) * 180 / .pi
        }

        // Initial values are taken not on the first frame but once the
        // fingers have settled: at the very start the coordinates jump about
        // and the spread comes out false.
        if !s.measured, now.timeIntervalSince(s.began) >= 0.03 {
            s.startCentre = (cx, cy); s.startSpread = spread; s.startAngle = angle
            s.measured = true
        }
        s.endCentre = (cx, cy); s.endSpread = spread; s.endAngle = angle
    }

    // MARK: - Handling a lifted finger

    /// A finger was lifted — was this a tap beside an anchor finger?
    private func evaluateLift(of lifted: Contact, at now: Date) {
        // The touch involved noticeable motion, so it is a scroll or a swipe.
        // Lifting a finger there is not a tap, whatever it may look like.
        if let s = session {
            let travel = hypot(s.endCentre.0 - s.startCentre.0,
                               s.endCentre.1 - s.startCentre.1)
            if travel >= minSwipe / 2 {
                return
            }
        }

        let duration = now.timeIntervalSince(lifted.began)
        guard duration <= tapDuration, lifted.drift <= maxTapDrift else {
            return
        }

        // Anchors are fingers that landed noticeably earlier and are still
        // down. Both conditions are required: without the first an ordinary
        // two-finger tap would land here, without the second a spread would.
        // The anchor must also be still. In scrolling both fingers travel, and
        // without this check a travelling one passed for an anchor.
        let anchors = contacts.values.filter {
            lifted.began.timeIntervalSince($0.began) >= anchorLead
                && $0.drift <= maxTapDrift
        }
        guard anchors.count == 1 || anchors.count == 2 else {
            return
        }

        let anchorX = anchors.map(\.x).reduce(0, +) / Float(anchors.count)
        let sideways = lifted.startX - anchorX
        guard abs(sideways) >= minSideways else {
            return
        }

        session?.tipFired = true
        switch (anchors.count, sideways < 0) {
        case (1, true):  fire(.tipLeft)
        case (1, false): fire(.tipRight)
        case (2, true):  fire(.tipLeft2)
        default:         fire(.tipRight2)
        }
    }

    // MARK: - Handling a finished touch

    private func classify(_ s: Session, at now: Date) {
        // A tip tap was already emitted during this touch — there is no need
        // to analyse the same motion twice.
        guard !s.tipFired else { return }

        let fingers = s.peakFingers
        let duration = now.timeIntervalSince(s.began)
        let dx = s.endCentre.0 - s.startCentre.0
        let dy = s.endCentre.1 - s.startCentre.1
        let travel = hypot(dx, dy)
        let spreadChange = s.endSpread - s.startSpread

        // The order matters: motion takes precedence over tapping.
        if fingers >= 3, travel >= minSwipe, abs(spreadChange) < minPinch {
            // The trackpad's origin is bottom-left, so growing y means up.
            let name = abs(dx) > abs(dy)
                ? (dx > 0 ? "swipeRight" : "swipeLeft")
                : (dy > 0 ? "swipeUp" : "swipeDown")
            if let g = Gesture(rawValue: name + String(min(fingers, 5))) { fire(g) }
            return
        }

        if fingers >= 2, abs(spreadChange) >= minPinch {
            let name = spreadChange > 0 ? "pinchOut" : "pinchIn"
            if let g = Gesture(rawValue: name + String(min(fingers, 4))) { fire(g) }
            return
        }

        if fingers == 2, !s.startAngle.isNaN, !s.endAngle.isNaN {
            var turn = s.endAngle - s.startAngle
            // Normalise to -180...180: otherwise crossing zero would report
            // a rotation of hundreds of degrees out of nowhere.
            while turn > 180 { turn -= 360 }
            while turn < -180 { turn += 360 }
            if abs(turn) >= minRotation {
                fire(turn > 0 ? .rotateLeft : .rotateRight)
                return
            }
        }

        if duration >= holdDuration, travel <= maxTapDrift, fingers >= 2 {
            if let g = Gesture(rawValue: "hold" + String(min(fingers, 4))) { fire(g) }
            return
        }

        guard duration <= tapDuration, travel <= maxTapDrift else { return }

        if fingers == 1 {
            let (x, y) = s.startCentre
            let left = x <= cornerZone, right = x >= 1 - cornerZone
            let bottom = y <= cornerZone, top = y >= 1 - cornerZone
            switch (left, right, top, bottom) {
            case (true, _, true, _): fire(.cornerTopLeft)
            case (_, true, true, _): fire(.cornerTopRight)
            case (true, _, _, true): fire(.cornerBottomLeft)
            case (_, true, _, true): fire(.cornerBottomRight)
            default: break
            }
            return
        }

        // The fingers of a real tap land almost together. A hand settling on
        // the trackpad piecemeal gives the same finger count but stretched in
        // time — that does not count as a gesture.
        let landingSpread = s.lastLanding.timeIntervalSince(s.firstLanding)
        guard landingSpread <= maxLandingSpread else { return }

        guard fingers >= 2,
              let single = Gesture(rawValue: "tap" + String(min(fingers, 5))) else { return }
        let double = Gesture(rawValue: "doubleTap" + String(min(fingers, 4)))

        // A second identical tap in a row makes it a double.
        if let pending = pendingTap, pending.gesture == single,
           now.timeIntervalSince(pending.at) <= doubleGap, let double {
            pendingWork?.cancel()
            pendingTap = nil
            fire(double)
            return
        }

        // Hold back the single one only if the double is bound to something:
        // otherwise the delay would be noticeable for no reason.
        if let double, isBound(double) {
            pendingTap = (single, now)
            let work = DispatchWorkItem { [weak self] in
                self?.pendingTap = nil
                self?.fire(single)
            }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleGap, execute: work)
        } else {
            fire(single)
        }
    }

    private func fire(_ gesture: Gesture) {
        // While typing, hands brush the trackpad constantly and almost every
        // contact is accidental. We ask the system for the time since the last
        // key press: that is a public facility and needs no special permission,
        // unlike watching the keyboard.
        if guardsEnabled {
            let sinceKey = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: .keyDown)
            if sinceKey < typingGuard {
                return
            }

            // A held button means dragging or selecting — multi-finger
            // contacts there have nothing to do with gestures.
            //
            // "Anchor finger plus a tap beside it" is exempt: the tap itself
            // physically coincides with the system's tap-to-click, and the OS
            // generates its own click for the same contact — pressedMouseButtons
            // becomes true for an instant not because of dragging but as a side
            // effect of that very tap. Confirmed by the logs: the gesture was
            // recognised correctly but suppressed by this check a third of the
            // time.
            let isTip: Bool
            switch gesture {
            case .tipLeft, .tipRight, .tipLeft2, .tipRight2: isTip = true
            default: isTip = false
            }
            if !isTip, NSEvent.pressedMouseButtons != 0 {
                return
            }
        }

        let now = Date()
        guard now.timeIntervalSince(lastFired) > cooldown else {
            return
        }
        lastFired = now
        DispatchQueue.main.async { [weak self] in self?.onGesture?(gesture) }
    }
}
