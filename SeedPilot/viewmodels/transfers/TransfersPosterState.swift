import Foundation
import Observation

@MainActor
@Observable
final class TransfersPosterState {
    let taskID: String
    var url: URL?
    var isResolved = false
    var isResolving = false

    init(taskID: String) {
        self.taskID = taskID
    }

    func reset() {
        if url != nil {
            url = nil
        }
        if isResolved {
            isResolved = false
        }
        if isResolving {
            isResolving = false
        }
    }

    func markResolving() {
        if !isResolving {
            isResolving = true
        }
    }

    func applyResolvedURL(_ nextURL: URL?) {
        if url != nextURL {
            url = nextURL
        }
        if isResolving {
            isResolving = false
        }
        if !isResolved {
            isResolved = true
        }
    }
}
