import OSLog

struct HermesLogger: Sendable {
    private let logger: Logger

    init(category: String) {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.slashmike.Hermes"
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func info(_ message: StaticString) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: StaticString, code: String) {
        logger.error("\(message, privacy: .public) code=\(code, privacy: .public)")
    }
}
