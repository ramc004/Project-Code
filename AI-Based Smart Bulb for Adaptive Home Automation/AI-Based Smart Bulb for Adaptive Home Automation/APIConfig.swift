import Foundation

struct APIConfig {
    // Change this to your Mac's IP address
    #if targetEnvironment(simulator)
    static let baseURL = "http://127.0.0.1:5000"
    #else
    static let baseURL = "https://enrique-unspying-addilyn.ngrok-free.dev" // Your Mac's IP
    #endif
}
