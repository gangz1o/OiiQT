import Foundation
import OSLog

enum TransfersPosterDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gangz1o.seedpilot.app",
        category: "TransfersPoster"
    )

    static var isEnabled: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SeedPilotDisableTransfersPosterDiagnostics") {
            return false
        }

        if ProcessInfo.processInfo.arguments.contains("-SeedPilotTransfersPosterDiagnostics") {
            return true
        }

        if UserDefaults.standard.object(forKey: "debug.transfers.posterDiagnostics") != nil {
            return UserDefaults.standard.bool(forKey: "debug.transfers.posterDiagnostics")
        }

        return true
#else
        return false
#endif
    }

    static var isBodyTraceEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SeedPilotTransfersBodyTrace")
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
