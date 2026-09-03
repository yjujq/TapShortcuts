import Foundation

/// Работа с быстрыми командами через входящую в систему программу `shortcuts`.
///
/// Схема адреса `shortcuts://run-shortcut` тоже существует, но она выводит
/// на передний план само приложение «Быстрые команды». Через программу
/// запуск происходит тихо, а это для жеста и нужно.
enum Shortcuts {
    private static let binary = "/usr/bin/shortcuts"

    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: binary)
    }

    /// Список установленных команд. Читается при открытии настроек,
    /// а не постоянно: вызов недешёвый.
    static func list() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch {
            NSLog("TapShortcuts: не удалось получить список команд: \(error)")
            return []
        }
    }

    /// Запуск по имени. Не ждём завершения: команда может работать долго,
    /// а жест должен отпускать нас сразу.
    static func run(_ name: String) {
        guard !name.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["run", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch {
            NSLog("TapShortcuts: команда «\(name)» не запустилась: \(error)")
        }
    }
}
