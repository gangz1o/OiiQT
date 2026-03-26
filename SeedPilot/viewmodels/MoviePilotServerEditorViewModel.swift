import Foundation
import Observation

@MainActor
@Observable
final class MoviePilotServerEditorViewModel {
    enum TestResult {
        case success(String)
        case failure(String)
    }

    private let serverID: UUID?
    private let storedToken: String?

    var name: String
    var url: String
    var token: String
    var isTokenVisible = false
    var isTestingConnection = false
    var testResult: TestResult?

    init(server: MoviePilotServerConfiguration?, storedToken: String?) {
        self.serverID = server?.id
        self.storedToken = storedToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = server?.name ?? ""
        self.url = server?.baseURLString ?? ""
        self.token = ""
    }

    var canSave: Bool {
        !trimmedName.isEmpty && normalizedURL != nil && effectiveToken != nil
    }

    var canTestConnection: Bool {
        normalizedURL != nil && effectiveToken != nil && !isTestingConnection
    }

    var hasStoredToken: Bool {
        !(storedToken?.isEmpty ?? true)
    }

    func clearTestResult() {
        testResult = nil
    }

    func save(to store: MoviePilotServerStore) {
        guard let normalizedURL, let effectiveToken else { return }
        let typedToken = trimmedToken.isEmpty ? nil : effectiveToken

        store.upsert(
            id: serverID,
            name: trimmedName,
            baseURLString: normalizedURL,
            typedToken: typedToken
        )
    }

    func testConnection() async {
        guard let normalizedURL else {
            testResult = .failure(LanguageManager.shared.localized("Please enter a valid MoviePilot URL."))
            return
        }

        guard let effectiveToken else {
            testResult = .failure(LanguageManager.shared.localized("Please enter a token."))
            return
        }

        isTestingConnection = true
        testResult = nil

        defer {
            isTestingConnection = false
        }

        do {
            let user = try await MoviePilotAPIClient.shared.fetchCurrentUser(
                baseURLString: normalizedURL,
                token: effectiveToken
            )
            testResult = .success(
                String(format: LanguageManager.shared.localized("Connected as %@"), user.name)
            )
        } catch {
            testResult = .failure(
                String(format: LanguageManager.shared.localized("Connection failed: %@"), error.localizedDescription)
            )
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedURL: String? {
        MoviePilotURLNormalizer.normalize(url)
    }

    private var effectiveToken: String? {
        if !trimmedToken.isEmpty {
            return trimmedToken
        }
        guard let storedToken, !storedToken.isEmpty else {
            return nil
        }
        return storedToken
    }
}
