// APIConfig.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Centralises the backend base URL for all API calls throughout the app
// Uses conditional compilation to automatically select the correct URL depending on whether the app is running in the iOS Simulator or on a physical device

import Foundation

struct APIConfig {

    /// The base URL of the Flask backend server
     
    /// Simulator: points to localhost (127.0.0.1:5000) since the simulator shares the Mac's network stack
    /// Physical device: points to the public ngrok tunnel URL, which forwards traffic to the local Flask server running on port 5000
    /// Update this URL whenever a new ngrok session is started
    #if targetEnvironment(simulator)
    static let baseURL = "http://127.0.0.1:5000"
    #else
    static let baseURL = "https://enrique-unspying-addilyn.ngrok-free.dev"
    #endif
}
