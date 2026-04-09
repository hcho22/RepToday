import Foundation
import SwiftData

/// Real AI service that calls backend proxy endpoints for personalized insights.
/// Falls back to template-based text (MockAIService) on any error.
final class AIService: AIServiceProtocol {

    private let session: URLSession
    private let baseURL: URL
    private let fallback: MockAIService
    private let modelContext: ModelContext

    /// Timeout for all AI requests (10 seconds).
    private static let requestTimeout: TimeInterval = 10

    /// HTTP 429 — Too Many Requests
    private static let rateLimitStatusCode = 429

    init(baseURL: URL, modelContext: ModelContext) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.requestTimeout
        self.session = URLSession(configuration: config)
        self.baseURL = baseURL
        self.fallback = MockAIService()
        self.modelContext = modelContext
    }

    // MARK: - AIServiceProtocol

    func generatePostWorkoutSummary(
        workout: Workout,
        userProfile: UserProfile,
        recentHistory: [Workout]
    ) async throws -> AITextResponse {
        // Check cache first
        if let cached = try cachedSummary(for: workout.id) {
            return AITextResponse(text: cached, isFromCache: true)
        }

        let prompt = AIPromptBuilder.postWorkoutPrompt(
            workout: workout,
            profile: userProfile,
            recentHistory: recentHistory
        )

        do {
            let text = try await callEndpoint(
                path: "/api/ai/summary",
                prompt: prompt,
                maxTokens: 100
            )
            // Cache the result
            try cacheSummary(text, for: workout.id)
            return AITextResponse(text: text)
        } catch {
            let response = try await fallback.generatePostWorkoutSummary(
                workout: workout,
                userProfile: userProfile,
                recentHistory: recentHistory
            )
            return AITextResponse(text: response.text, isFallback: true)
        }
    }

    func generateWeeklyReport(
        workouts: [Workout],
        userProfile: UserProfile,
        stats: GamificationStats
    ) async throws -> String {
        let prompt = AIPromptBuilder.weeklyReportPrompt(
            workouts: workouts,
            profile: userProfile,
            streak: stats.currentWeeklyStreak,
            xp: stats.xp,
            level: stats.level
        )

        do {
            return try await callEndpoint(
                path: "/api/ai/weekly-report",
                prompt: prompt,
                maxTokens: 300
            )
        } catch {
            return try await fallback.generateWeeklyReport(
                workouts: workouts,
                userProfile: userProfile,
                stats: stats
            )
        }
    }

    func generateNextWorkoutPreview(
        userProfile: UserProfile,
        recentHistory: [Workout],
        tomorrowsFocus: String
    ) async throws -> String {
        let prompt = AIPromptBuilder.nextWorkoutPreviewPrompt(
            recentHistory: recentHistory,
            profile: userProfile
        )

        do {
            return try await callEndpoint(
                path: "/api/ai/next-workout-preview",
                prompt: prompt,
                maxTokens: 150
            )
        } catch {
            return try await fallback.generateNextWorkoutPreview(
                userProfile: userProfile,
                recentHistory: recentHistory,
                tomorrowsFocus: tomorrowsFocus
            )
        }
    }

    // MARK: - HTTP Client

    private func callEndpoint(path: String, prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = APIKeyManager.retrieve() else {
            throw AIServiceError.noAPIKey
        }

        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "prompt": prompt,
            "max_tokens": maxTokens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(AIProxyResponse.self, from: data)
            return decoded.text
        case Self.rateLimitStatusCode:
            throw AIServiceError.rateLimited
        case 400..<500:
            throw AIServiceError.clientError(httpResponse.statusCode)
        case 500...:
            throw AIServiceError.serverError(httpResponse.statusCode)
        default:
            throw AIServiceError.unexpectedStatus(httpResponse.statusCode)
        }
    }

    // MARK: - Response Caching (SDWorkout)

    private func cachedSummary(for workoutId: String) throws -> String? {
        let descriptor = FetchDescriptor<SDWorkout>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )
        guard let sdWorkout = try modelContext.fetch(descriptor).first else { return nil }
        return sdWorkout.aiSummary
    }

    private func cacheSummary(_ summary: String, for workoutId: String) throws {
        let descriptor = FetchDescriptor<SDWorkout>(
            predicate: #Predicate { $0.workoutId == workoutId }
        )
        guard let sdWorkout = try modelContext.fetch(descriptor).first else { return }
        sdWorkout.aiSummary = summary
        try modelContext.save()
    }
}

// MARK: - Supporting Types

enum AIServiceError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case rateLimited
    case clientError(Int)
    case serverError(Int)
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No API key configured. Set your API key in Settings."
        case .invalidResponse: "Invalid response from AI service."
        case .rateLimited: "AI service rate limit reached. Please try again later."
        case .clientError(let code): "AI request failed (HTTP \(code))."
        case .serverError(let code): "AI service error (HTTP \(code))."
        case .unexpectedStatus(let code): "Unexpected AI response (HTTP \(code))."
        }
    }
}

/// Expected JSON response from the backend proxy.
struct AIProxyResponse: Decodable {
    let text: String
}
