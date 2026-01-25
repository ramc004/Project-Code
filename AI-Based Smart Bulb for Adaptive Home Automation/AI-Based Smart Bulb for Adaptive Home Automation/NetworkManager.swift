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
    
    // Check if server is reachable
    func checkServerHealth(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(APIConfig.baseURL)/check_email") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3.0 // Short timeout for health check
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": "health@check.com"])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse {
                    // Server responded (even with error status means it's available)
                    completion(true)
                } else {
                    // No response means server is down
                    completion(false)
                }
            }
        }.resume()
    }
    
    // Generic POST request with error handling
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
                // Check for connection errors
                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain &&
                       (error.code == NSURLErrorCannotConnectToHost ||
                        error.code == NSURLErrorCannotFindHost ||
                        error.code == NSURLErrorTimedOut) {
                        completion(.failure(.serverUnavailable))
                        return
                    }
                }
                
                // Check for HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(.failure(.serverUnavailable))
                    return
                }
                
                // Parse response data
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
