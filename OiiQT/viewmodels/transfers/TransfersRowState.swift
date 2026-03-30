import Foundation
import Observation

@Observable
@MainActor
final class TransfersRowState: Identifiable {
    let id: String
    var snapshot: TransfersRowDisplayModel

    init(snapshot: TransfersRowDisplayModel) {
        self.id = snapshot.id
        self.snapshot = snapshot
    }

    func apply(_ snapshot: TransfersRowDisplayModel) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}
