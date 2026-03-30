import CoreGraphics
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class TransfersPosterState: Identifiable {
    let id: String
    var posterURL: URL?
    var hasResolved = false
    var isResolving = false

    init(hash: String) {
        self.id = hash
    }

    func reset() {
        posterURL = nil
        hasResolved = false
        isResolving = false
    }
}

@Observable
@MainActor
final class TransfersPosterStore {
    @ObservationIgnored
    private static let maxConcurrentRequests = 2

    @ObservationIgnored
    private var modelContext: ModelContext?

    @ObservationIgnored
    private var posterStatesByHash: [String: TransfersPosterState] = [:]

    @ObservationIgnored
    private var pendingRequests: [PosterRequest] = []

    @ObservationIgnored
    private var inFlightTasks: [String: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var isPosterRenderingEnabled = false

    func updateConfiguration(isEnabled: Bool, modelContext: ModelContext) {
        self.isPosterRenderingEnabled = isEnabled
        self.modelContext = modelContext
        PosterArtworkService.shared.preparePosterCacheIfNeeded(context: modelContext)

        guard !isEnabled else {
            pumpQueue()
            return
        }

        pendingRequests.removeAll()
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()

        for state in posterStatesByHash.values where state.isResolving {
            state.isResolving = false
        }
    }

    func posterState(for hash: String) -> TransfersPosterState {
        if let existing = posterStatesByHash[hash] {
            return existing
        }

        let state = TransfersPosterState(hash: hash)
        if let cachedURL = PosterArtworkService.shared.cachedPosterURL(for: hash) {
            state.posterURL = cachedURL
            state.hasResolved = true
        }
        posterStatesByHash[hash] = state
        return state
    }

    func resolveIfNeeded(for hash: String, name: String) {
        guard isPosterRenderingEnabled else { return }

        let state = posterState(for: hash)
        if let cachedURL = PosterArtworkService.shared.cachedPosterURL(for: hash) {
            state.posterURL = cachedURL
            state.hasResolved = true
            state.isResolving = false
            return
        }

        guard !state.hasResolved else { return }
        guard inFlightTasks[hash] == nil else { return }

        pendingRequests.removeAll { $0.hash == hash }
        pendingRequests.append(PosterRequest(hash: hash, name: name))
        state.isResolving = true
        pumpQueue()
    }

    func invalidate(hash: String, name: String? = nil) {
        pendingRequests.removeAll { $0.hash == hash }
        inFlightTasks[hash]?.cancel()
        inFlightTasks[hash] = nil
        PosterArtworkService.shared.clearCache(for: hash, name: name)
        posterState(for: hash).reset()
        pumpQueue()
    }

    func refresh(hash: String, name: String) {
        pendingRequests.removeAll { $0.hash == hash }
        inFlightTasks[hash]?.cancel()
        inFlightTasks[hash] = nil
        posterState(for: hash).reset()
        resolveIfNeeded(for: hash, name: name)
    }

    private func pumpQueue() {
        guard isPosterRenderingEnabled else { return }
        guard let modelContext else { return }

        while inFlightTasks.count < Self.maxConcurrentRequests, let request = pendingRequests.popLast() {
            guard inFlightTasks[request.hash] == nil else { continue }

            let state = posterState(for: request.hash)
            state.isResolving = true

            inFlightTasks[request.hash] = Task { @MainActor [weak self] in
                guard let self else { return }
                let resolvedURL = await PosterArtworkService.shared.fetchPoster(
                    hash: request.hash,
                    name: request.name,
                    context: modelContext
                )
                guard !Task.isCancelled else { return }
                self.finishRequest(hash: request.hash, posterURL: resolvedURL)
            }
        }
    }

    private func finishRequest(hash: String, posterURL: URL?) {
        inFlightTasks[hash] = nil

        let state = posterState(for: hash)
        state.posterURL = posterURL
        state.hasResolved = true
        state.isResolving = false

        if let posterURL {
            OiiQTImagePreheater.prefetch(
                posterURL,
                downsampleSize: CGSize(width: 65, height: 97.5),
                cacheOriginal: false
            )
        }

        pumpQueue()
    }
}

private struct PosterRequest: Equatable {
    let hash: String
    let name: String
}
