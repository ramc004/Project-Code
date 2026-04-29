// NetworkManager.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// Provides a centralised networking layer for all HTTP communication
// between the iOS app and the Flask backend server. Includes a shared
// singleton, a lightweight health check, and a generic JSON POST helper.

import Foundation

// MARK: - Network Error Types

/// Describes the possible failure modes for network requests made by the app.
enum NetworkError: Error {

    /// The server could not be reached — connection refused, timed out, or no internet.
    case serverUnavailable

    /// A response was received but could not be parsed into the expected format.
    case invalidResponse

    /// The server returned a non-2xx status code with an explanatory message.
    case requestFailed(String)

    /// A human-readable description of the error, suitable for displaying in the UI.
    var userMessage: String {
        switch self {
        case .serverUnavailable:
            return "Cannot connect to server. Please make sure the server is running."
        case .invalidResponse:
            return "Invalid response from server."
        case .requestFailed(let message):
            return message
        }
    }
}

// MARK: - Network Manager

/// A singleton class responsible for all HTTP communication with the Flask backend.
///
/// All completion handlers are dispatched on the main thread, so callers can
/// update the UI directly inside the closure without additional dispatching.
class NetworkManager {

    /// The shared singleton instance used throughout the app.
    static let shared = NetworkManager()

    /// Private initialiser — use `NetworkManager.shared` instead.
    private init() {}

    // MARK: - Health Check

    /// Checks whether the Flask backend server is reachable and responding.
    ///
    /// Sends a lightweight GET request to the `/health` endpoint, which performs
    /// no database queries or side-effects. A HTTP 200 response indicates the
    /// server is up; any error, timeout, or non-200 status is treated as down.
    ///
    /// - Parameter completion: Called on the main thread with `true` if the server
    ///   is reachable, or `false` otherwise.
    func checkServerHealth(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(APIConfig.baseURL)/health") else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0   // Short timeout — this is a quick liveness check

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                // Require no error and an HTTP 200 status to consider the server healthy
                guard error == nil,
                      let http = response as? HTTPURLResponse,
                      http.statusCode == 200 else {
                    completion(false)
                    return
                }
                completion(true)
            }
        }.resume()
    }

    // MARK: - Generic POST

    /// Sends a JSON POST request to the specified backend endpoint.
    ///
    /// Serialises `body` as JSON, attaches the appropriate `Content-Type` header,
    /// and calls `completion` with either the decoded JSON response dictionary on
    /// success, or a `NetworkError` on failure.
    ///
    /// Connection-level URL errors (host unreachable, timeout, no internet) are
    /// mapped to `.serverUnavailable`. Non-2xx HTTP responses are mapped to
    /// `.requestFailed` using the `message` field from the response JSON.
    ///
    /// - Parameters:
    ///   - endpoint: The path component to append to `APIConfig.baseURL` (e.g. `"/login"`).
    ///   - body: A dictionary of key-value pairs to encode as the JSON request body.
    ///   - completion: Called on the main thread with a `Result` containing either
    ///     the decoded response dictionary or a `NetworkError`.
    func post(
        endpoint: String,
        body: [String: Any],
        completion: @escaping (Result<[String: Any], NetworkError>) -> Void
    ) {
        guard let url = URL(string: "\(APIConfig.baseURL)\(endpoint)") else {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {

                // Map known connection-level URL errors to .serverUnavailable
                if let error = error as NSError?, error.domain == NSURLErrorDomain {
                    let connectionErrors = [
                        NSURLErrorCannotConnectToHost,
                        NSURLErrorCannotFindHost,
                        NSURLErrorTimedOut,
                        NSURLErrorNetworkConnectionLost,
                        NSURLErrorNotConnectedToInternet
                    ]
                    if connectionErrors.contains(error.code) {
                        completion(.failure(.serverUnavailable))
                        return
                    }
                }

                // Ensure we received a valid HTTP response object
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(.serverUnavailable))
                    return
                }

                // Attempt to decode the response body as a JSON dictionary
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        // 2xx — success
                        completion(.success(json))
                    } else {
                        // Non-2xx — extract the server's error message if available
                        let message = json["message"] as? String ?? "Request failed"
                        completion(.failure(.requestFailed(message)))
                    }
                } else {
                    // Response body could not be decoded
                    completion(.failure(.invalidResponse))
                }
            }
        }.resume()
    }
}
