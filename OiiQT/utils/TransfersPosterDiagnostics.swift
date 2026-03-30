import Foundation
import OSLog

enum TransfersPosterDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gangz1o.oiiqt.app",
        category: "TransfersPoster"
    )

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-OiiQTTransfersPosterDiagnostics") {
            return true
        }

        if UserDefaults.standard.object(forKey: "debug.transfers.posterDiagnostics") != nil {
            return UserDefaults.standard.bool(forKey: "debug.transfers.posterDiagnostics")
        }

        return false
    }

    static var isBodyTraceEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-OiiQTTransfersBodyTrace")
            || UserDefaults.standard.bool(forKey: "debug.transfers.bodyTrace")
#else
        return false
#endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let value = message()
        logger.debug("\(value, privacy: .public)")
    }
}
