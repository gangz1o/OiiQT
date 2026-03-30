import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ManualPosterMatchViewModel {
    var searchText: String
    var items: [PosterSearchCandidate] = []
    var isLoading = false
    var hasMore = true
    var hasSearched = false

    @ObservationIgnored
    private let taskName: String

    @ObservationIgnored
    private let taskHash: String

    @ObservationIgnored
    private let posterArtworkService: PosterArtworkService

    @ObservationIgnored
    private var currentTMDBPage = 1

    init(
        taskName: String,
        taskHash: String,
        posterArtworkService: PosterArtworkService? = nil
    ) {
        self.taskName = taskName
        self.taskHash = taskHash
        self.posterArtworkService = posterArtworkService ?? .shared
        self.searchText = OiiQTParser.parse(taskName).title
    }

    func performSearch() async {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        isLoading = true
        hasSearched = true
        currentTMDBPage = 1
        items = []
        hasMore = true
        defer { isLoading = false }

        let batch = await posterArtworkService.searchManualCandidates(query: trimmedQuery, tmdbPage: 1)
        items = batch.items
        hasMore = batch.hasMoreTMDB
    }

    func loadNextPageIfNeeded() async {
        guard !isLoading, hasMore else { return }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let nextPage = currentTMDBPage + 1
        let batch = await posterArtworkService.searchManualCandidates(query: trimmedQuery, tmdbPage: nextPage)
        if batch.items.isEmpty {
            hasMore = false
            return
        }

        currentTMDBPage = nextPage
        items.append(contentsOf: batch.items.filter { candidate in
            !items.contains(where: { $0.id == candidate.id })
        })
        hasMore = batch.hasMoreTMDB
    }

    func saveSelection(_ candidate: PosterSearchCandidate, context: ModelContext) {
        posterArtworkService.saveManualOverride(
            hash: taskHash,
            name: taskName,
            candidate: candidate,
            context: context
        )
    }
}
