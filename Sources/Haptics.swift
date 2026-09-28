import AppKit
import IOKit

/// How hard the trackpad knocks back when a gesture fires.
enum HapticStrength: String, CaseIterable, Identifiable {
    case off, light, medium, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:    return "Off"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }

    /// The pattern the motor plays. The numbers are undocumented: these are
    /// the ones other tools driving the same motor use for weak, medium and
    /// strong, not a scale worked out here — which is why choosing one in
    /// settings plays it, so it can be judged by feel.
    fileprivate var actuation: Int32? {
        switch self {
        case .off:    return nil
        case .light:  return 3
        case .medium: return 4
        case .strong: return 6
        }
    }
}

/// A knock from the trackpad's own motor when a gesture fires.
///
/// The public route, NSHapticFeedbackManager, only plays while a finger rests
/// on the trackpad, and most gestures fire as the fingers leave it: a tap, a
/// corner tap and a swipe are all decided on the lift, when feedback would no
/// longer be felt. So the motor is driven directly, through the same private
/// MultitouchSupport framework the recognition already rests on, which does not
/// wait for a touch. The public route stays behind as the fallback, should the
/// private one go missing in some later release.
@MainActor
enum Haptics {
    private typealias CreateActuator = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias OpenActuator   = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias ActuatorIsOpen = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias Actuate        = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32,
                                                       Float, Float) -> Int32

    private static var loaded = false
    private static var actuator: UnsafeMutableRawPointer?
    private static var open: OpenActuator?
    private static var isOpen: ActuatorIsOpen?
    private static var actuate: Actuate?

    static func play(_ strength: HapticStrength) {
        guard let pattern = strength.actuation else { return }
        if playDirectly(pattern) { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private static func playDirectly(_ pattern: Int32) -> Bool {
        load()
        guard let actuator, let open, let isOpen, let actuate else { return false }
        // Sleep can close the actuator under us. It is opened again rather
        // than left silent until the next launch.
        if !isOpen(actuator), open(actuator) != 0 { return false }
        return actuate(actuator, pattern, 0, 0, 0) == 0          // kIOReturnSuccess
    }

    /// Binds the functions once. Each symbol is checked, as the recogniser does
    /// with its own: were one to vanish, the fallback plays instead of a crash.
    private static func load() {
        guard !loaded else { return }
        loaded = true
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY),
              let createSymbol = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let openSymbol = dlsym(handle, "MTActuatorOpen"),
              let isOpenSymbol = dlsym(handle, "MTActuatorIsOpen"),
              let actuateSymbol = dlsym(handle, "MTActuatorActuate"),
              let deviceID = motorisedTrackpadID() else {
            NSLog("TapShortcuts: no trackpad motor to drive; falling back to the public haptics")
            return
        }
        let create = unsafeBitCast(createSymbol, to: CreateActuator.self)
        guard let reference = create(deviceID) else { return }
        actuator = reference
        open = unsafeBitCast(openSymbol, to: OpenActuator.self)
        isOpen = unsafeBitCast(isOpenSymbol, to: ActuatorIsOpen.self)
        actuate = unsafeBitCast(actuateSymbol, to: Actuate.self)
    }

    /// The multitouch ID of a trackpad that has a motor, read from the I/O
    /// registry — the built-in one first. Read there rather than through
    /// MTDeviceGetDeviceID, whose calling convention is not to be relied on.
    private static func motorisedTrackpadID() -> UInt64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleMultitouchDevice"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var found: [(id: UInt64, builtIn: Bool)] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            func number(_ key: String) -> NSNumber? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber
            }
            if number("ActuationSupported")?.boolValue == true,
               let id = number("Multitouch ID")?.uint64Value {
                found.append((id, number("MT Built-In")?.boolValue ?? false))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (found.first { $0.builtIn } ?? found.first)?.id
    }
}
