import Foundation

// MARK: - Network Error Types
enum NetworkError: Error {
    case serverUnavailable
    case invalidResponse
    case requestFailed(String)
    
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
class NetworkManager {
    static let shared = NetworkManager()
    
    private init() {}
    
    // MARK: - Health Check
    // Uses the dedicated /health endpoint — no DB queries, no side-effects.
    // A real 200 response means the server is up; anything else (timeout,
    // connection refused, non-200) means it is down.
    func checkServerHealth(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(APIConfig.baseURL)/health") else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
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
                // Connection-level errors → treat as server unavailable
                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain &&
                       (error.code == NSURLErrorCannotConnectToHost ||
                        error.code == NSURLErrorCannotFindHost ||
                        error.code == NSURLErrorTimedOut ||
                        error.code == NSURLErrorNetworkConnectionLost ||
                        error.code == NSURLErrorNotConnectedToInternet) {
                        completion(.failure(.serverUnavailable))
                        return
                    }
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(.serverUnavailable))
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        completion(.success(json))
                    } else {
                        let message = json["message"] as? String ?? "Request failed"
                        completion(.failure(.requestFailed(message)))
                    }
                } else {
                    completion(.failure(.invalidResponse))
                }
            }
        }.resume()
    }
}
