import Foundation

// MARK: - Раскладка сырых данных трекпада
//
// Открытого пути к касаниям трекпада в macOS нет: NSEvent отдаёт уже
// истолкованные жесты, а число пальцев при постукивании — нет. Поэтому
// берём частный механизм MultitouchSupport и подключаемся к нему через
// среду выполнения. Разрешений он не требует — проверено.

private struct MTPoint { var x: Float = 0; var y: Float = 0 }
private struct MTReadout { var pos = MTPoint(); var vel = MTPoint() }

/// Одно касание. Раскладка полей подобрана под то, что отдаёт механизм;
/// нам нужны только положение и размер пятна, остальное — заполнение.
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

// Структура касания не выражается в терминах Objective-C, поэтому в сигнатуре
// обратного вызова берём сырой указатель и перетолковываем память на месте.
private typealias FrameCallback = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?,
                                                  Int32, Double, Int32) -> Int32

/// Что за жест распознан.
///
/// Набор выведен из того, что достоверно извлекается из сырых данных
/// трекпада: положение каждого пальца, его сдвиг, расстояние между пальцами
/// и угол между ними. Жесты, которые система забирает себе, помечены —
/// назначать их можно, но срабатывать они будут не всегда.
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

    /// Раздел в настройках: плоский список из сорока пунктов нечитаем.
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

    /// Занят ли жест системой. Такие можно назначать, но перехват выйдет
    /// ненадёжным: часть событий macOS забирает себе раньше нас.
    var conflictsWithSystem: Bool {
        switch self {
        case .tap2: return true                        // вторичный щелчок
        case .pinchIn2, .pinchOut2: return true         // масштаб
        case .pinchIn4, .pinchOut4: return true         // Launchpad и рабочий стол
        case .rotateLeft, .rotateRight: return true     // поворот в просмотрщиках
        case .swipeUp3, .swipeDown3, .swipeLeft3, .swipeRight3,
             .swipeUp4, .swipeDown4, .swipeLeft4, .swipeRight4:
            return true                                 // рабочие столы и Mission Control
        default: return false
        }
    }
}

/// Слежение за трекпадом и распознавание жестов.
///
/// Обратный вызов механизма — обычный указатель на функцию, замыкание с
/// захватом туда не передать. Поэтому состояние держим в одиночке.
final class TouchWatcher {
    static let shared = TouchWatcher()

    /// Вызывается, когда жест распознан.
    var onGesture: ((Gesture) -> Void)?
    /// Какие жесты заняты. Нужно для двойного постукивания: одиночное
    /// приходится придерживать, чтобы дождаться второго, и делать это стоит
    /// только когда двойное кому-то назначено.
    ///
    /// Именно набор, а не замыкание с обращением к настройкам. Разбор идёт
    /// в потоке трекпада, и всякая попытка спросить оттуда главный поток
    /// роняла приложение: MainActor.assumeIsolated — это утверждение, что мы
    /// уже на главном потоке, а не переход на него.
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

    // Пороги. Подобраны рассуждением: сдвиг и расстояния даны в долях
    // от размера трекпада, где 1.0 — вся его ширина или высота.
    private let tapDuration: TimeInterval = 0.30
    private let holdDuration: TimeInterval = 0.60
    private let maxTapDrift: Float = 0.06
    private let minSwipe: Float = 0.15
    private let minPinch: Float = 0.10
    private let minRotation: Float = 25          // градусов
    private let cornerZone: Float = 0.22
    private let doubleGap: TimeInterval = 0.35
    private let cooldown: TimeInterval = 0.35

    /// Насколько раньше опорный палец должен лечь, чтобы касание считалось
    /// сделанным «при нём». Без этого порога обычное постукивание двумя
    /// пальцами — системный вторичный щелчок — попадало бы в наши жесты.
    private let anchorLead: TimeInterval = 0.09
    private let minSideways: Float = 0.02

    private var handle: UnsafeMutableRawPointer?
    private var device: AnyObject?
    private var lastFired = Date.distantPast

    /// Один палец на трекпаде, прослеженный по кадрам.
    private struct Contact {
        let began: Date
        let startX: Float, startY: Float
        var x: Float, y: Float
        var drift: Float
    }

    private var contacts: [Int32: Contact] = [:]

    /// Обобщение всего касания — от первого пальца до снятия последнего.
    private struct Session {
        var began: Date
        var peakFingers = 0
        var startCentre: (Float, Float) = (0, 0)
        var endCentre: (Float, Float) = (0, 0)
        var startSpread: Float = 0
        var endSpread: Float = 0
        var startAngle: Float = .nan
        var endAngle: Float = .nan
        var measured = false          // начальные величины сняты не сразу
        var tipFired = false          // жест при опорном пальце уже выдан
    }
    private var session: Session?

    // Для двойного постукивания.
    private var pendingTap: (gesture: Gesture, at: Date)?
    private var pendingWork: DispatchWorkItem?

    private init() {}

    func start() {
        guard handle == nil else { return }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            NSLog("TapShortcuts: механизм касаний не загрузился")
            return
        }
        self.handle = handle

        typealias CreateList = @convention(c) () -> Unmanaged<CFMutableArray>?
        typealias Register = @convention(c) (UnsafeRawPointer, FrameCallback) -> Void
        typealias Start = @convention(c) (UnsafeRawPointer, Int32) -> Void

        guard let listSym = dlsym(handle, "MTDeviceCreateList"),
              let regSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart") else {
            NSLog("TapShortcuts: в механизме нет нужных символов")
            return
        }

        let createList = unsafeBitCast(listSym, to: CreateList.self)
        guard let list = createList()?.takeRetainedValue() as? [AnyObject],
              let device = list.first else {
            NSLog("TapShortcuts: устройство с многопальцевым вводом не найдено")
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

    // MARK: - Разбор кадров

    /// Кадры идут густо, поэтому здесь только накопление, без тяжёлой работы.
    fileprivate func handle(raw: UnsafeRawPointer?, count: Int) {
        let now = Date()
        var present = Set<Int32>()
        var points: [(Float, Float)] = []

        if count > 0, let raw {
            let touches = raw.assumingMemoryBound(to: MTTouch.self)
            for i in 0..<count {
                let t = touches[i]
                let id = t.identifier
                let x = t.normalized.pos.x, y = t.normalized.pos.y
                present.insert(id)
                points.append((x, y))

                if var existing = contacts[id] {
                    existing.x = x; existing.y = y
                    // Сдвиг считаем от начала, а не между кадрами: дрожание
                    // пальца накапливалось бы и глушило распознавание.
                    existing.drift = max(existing.drift,
                                         abs(x - existing.startX) + abs(y - existing.startY))
                    contacts[id] = existing
                } else {
                    contacts[id] = Contact(began: now, startX: x, startY: y, x: x, y: y, drift: 0)
                }
            }

            if session == nil { session = Session(began: now) }
            update(&session!, with: points, at: now)
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
        // Разброс — средняя удалённость пальцев от их общего средоточия.
        // По его изменению отличаем сведение от разведения.
        let spread = points
            .map { hypot($0.0 - cx, $0.1 - cy) }
            .reduce(0, +) / Float(points.count)

        var angle = Float.nan
        if points.count >= 2 {
            let dx = points[1].0 - points[0].0, dy = points[1].1 - points[0].1
            angle = atan2(dy, dx) * 180 / .pi
        }

        // Начальные величины снимаем не в первом кадре, а когда пальцы уже
        // легли: в самом начале координаты скачут, и разброс выходит ложным.
        if !s.measured, now.timeIntervalSince(s.began) >= 0.03 {
            s.startCentre = (cx, cy); s.startSpread = spread; s.startAngle = angle
            s.measured = true
        }
        s.endCentre = (cx, cy); s.endSpread = spread; s.endAngle = angle
    }

    // MARK: - Разбор снятого пальца

    /// Палец убран — не был ли это тап при опорных пальцах.
    private func evaluateLift(of lifted: Contact, at now: Date) {
        let duration = now.timeIntervalSince(lifted.began)
        guard duration <= tapDuration, lifted.drift <= maxTapDrift else { return }

        // Опорные — пальцы, легшие заметно раньше и всё ещё лежащие.
        // Оба условия обязательны: без первого сюда попадал бы обычный тап
        // двумя пальцами, без второго — разведение пальцев.
        let anchors = contacts.values.filter {
            lifted.began.timeIntervalSince($0.began) >= anchorLead
        }
        guard anchors.count == 1 || anchors.count == 2 else { return }

        let anchorX = anchors.map(\.x).reduce(0, +) / Float(anchors.count)
        let sideways = lifted.startX - anchorX
        guard abs(sideways) >= minSideways else { return }

        session?.tipFired = true
        switch (anchors.count, sideways < 0) {
        case (1, true):  fire(.tipLeft)
        case (1, false): fire(.tipRight)
        case (2, true):  fire(.tipLeft2)
        default:         fire(.tipRight2)
        }
    }

    // MARK: - Разбор законченного касания

    private func classify(_ s: Session, at now: Date) {
        // Жест при опорном пальце уже выдан внутри касания — второй раз
        // разбирать то же самое движение не нужно.
        guard !s.tipFired else { return }

        let fingers = s.peakFingers
        let duration = now.timeIntervalSince(s.began)
        let dx = s.endCentre.0 - s.startCentre.0
        let dy = s.endCentre.1 - s.startCentre.1
        let travel = hypot(dx, dy)
        let spreadChange = s.endSpread - s.startSpread

        // Порядок разбора важен: движение перекрывает постукивание.
        if fingers >= 3, travel >= minSwipe, abs(spreadChange) < minPinch {
            // У трекпада начало отсчёта внизу слева, поэтому рост y — вверх.
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
            // Приводим к промежутку от -180 до 180: иначе переход через ноль
            // давал бы поворот на сотни градусов на ровном месте.
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

        guard fingers >= 2,
              let single = Gesture(rawValue: "tap" + String(min(fingers, 5))) else { return }
        let double = Gesture(rawValue: "doubleTap" + String(min(fingers, 4)))

        // Второе такое же постукивание подряд — это двойное.
        if let pending = pendingTap, pending.gesture == single,
           now.timeIntervalSince(pending.at) <= doubleGap, let double {
            pendingWork?.cancel()
            pendingTap = nil
            fire(double)
            return
        }

        // Одиночное придерживаем, только если двойное кому-то назначено:
        // иначе задержка была бы заметна на ровном месте.
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
        let now = Date()
        guard now.timeIntervalSince(lastFired) > cooldown else { return }
        lastFired = now
        DispatchQueue.main.async { [weak self] in self?.onGesture?(gesture) }
    }
}
