import Foundation

struct NetworkService {
    func submit(_ payload: SubmissionPayload, to serverURL: URL) async throws {
        let url = serverURL.appendingPathComponent("api/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.badResponse
        }
    }

    func healthCheck(_ serverURL: URL) async throws -> HealthResponse {
        let url = serverURL.appendingPathComponent("api/health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.badResponse
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    enum NetworkError: LocalizedError {
        case badResponse
        var errorDescription: String? { "Server returned an error." }
    }
}
