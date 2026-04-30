// RegisterEmailView.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Step 1 of the two-step registration flow
// Collects and validates the user's email address, checks its availability against the backend, then sends a six-digit verification code before navigating to RegisterPasswordView

import SwiftUI

/// The first step of the user registration flow

/// Presents an email input field with a real-time validation checklist covering:
/// - Presence of a username before the `@` symbol
/// - Presence of the `@` symbol
/// - Presence of a valid domain
/// - Email availability confirmed via the "/check_email" backend endpoint

/// Once all checks pass, a six-digit verification code is generated and sent to the address via the "/send_code" endpoint
/// On success, the user is navigated to "RegisterPasswordView" (Step 2)

/// A server-offline banner is shown if the backend cannot be reached, disabling input and the verify button until connectivity is restored
struct RegisterEmailView: View {

    // MARK: - State

    /// The email address entered by the user
    @State private var email = ""

    /// Whether the portion of the email before "@" is non-empty
    @State private var usernameValid = false

    /// Whether the email contains an "@" symbol.
    @State private var atSignValid = false

    /// Whether the email contains a valid domain (text after "@" containing ".")
    @State private var domainValid = false

    /// Whether the backend confirmed this email address is not already registered
    @State private var emailAvailable = false

    /// Controls navigation to "RegisterPasswordView" once the code has been sent
    @State private var showPasswordView = false

    /// True while the verification code is being sent to the backend
    @State private var sendingCode = false

    /// True while an availability check request is in flight
    @State private var checkingEmail = false

    /// An error message displayed inline when a request fails (server online only)
    @State private var errorMessage = ""

    /// The six-digit verification code generated locally and sent to the user's email
    @State private var verificationCode = ""

    /// Whether the Flask backend server is currently reachable
    @State private var serverOnline = true

    /// Controls presentation of the server-unavailable alert dialog
    @State private var showServerAlert = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Register Account").font(.largeTitle).bold()

                // Server Offline Banner
                // Shown in place of normal error messages when the server cannot be reached
                // Disables input fields and the verify button until the user retries
                if !serverOnline {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 22))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Server is switched off")
                                .font(.subheadline).bold()
                                .foregroundColor(.white)
                            Text("Please tap Retry.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                        }

                        Spacer()

                        Button(action: checkServerStatus) {
                            Text("Retry")
                                .font(.subheadline).bold()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.white)
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.85))
                    )
                    .shadow(color: Color.red.opacity(0.25), radius: 6, x: 0, y: 3)
                }

                // Email Field
                // Triggers validateEmail() on every keystroke to keep the checklist and availability status up to date in real time
                VStack(alignment: .leading) {
                    Text("Email Address").font(.headline)
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .onChange(of: email) { _ in validateEmail() }
                        .disabled(!serverOnline)
                        .opacity(serverOnline ? 1.0 : 0.5)
                }

                // Validation Checklist
                // Provides real-time feedback on each email rule and the backend availability check. Availability is skipped when the server is offline to avoid misleading the user
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email Validation:").font(.subheadline).bold()
                    Text(usernameValid ? "✅ Username before @ is valid" : "❌ Enter username before @")
                    Text(atSignValid   ? "✅ Contains @"                 : "❌ Missing @")
                    Text(domainValid   ? "✅ Domain is valid"             : "❌ Invalid domain (e.g., example.com)")

                    if !serverOnline {
                        // Availability cannot be checked without a server connection
                        Label("Server offline - availability check skipped", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if checkingEmail {
                        // Availability request is in flight
                        Label("Checking availability…", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else if email.isEmpty || !atSignValid || !domainValid {
                        // Format invalid, no checking availability yet
                        Text("❌ Email availability unchecked")
                    } else {
                        // Display the result of the most recent availability check
                        Text(emailAvailable ? "✅ Email available" : "❌ Email already registered")
                    }
                }
                .foregroundColor(.gray)

                // Verify Button
                // Disabled until all format rules pass, availability is confirmed, no request is in flight, and the server is reachable
                Button(action: sendVerificationCode) {
                    Text(sendingCode ? "Sending…" : "Verify Email").frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle(backgroundColor: .green))
                .disabled(!allEmailRulesValid() || sendingCode || checkingEmail || !serverOnline)
                .padding(.top, 10)

                // Inline Error Message
                // Only shown when the server is online; the offline banner handles all messaging when the server cannot be reached
                if !errorMessage.isEmpty && serverOnline {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                // Hidden NavigationLink — activated programmatically once the verification code has been sent successfully
                NavigationLink(
                    "",
                    destination: RegisterPasswordView(email: email, verificationCode: verificationCode),
                    isActive: $showPasswordView
                )
            }
            .padding()
        }
        .navigationTitle("Step 1: Email")
        // Check server reachability each time this view appears
        .onAppear { checkServerStatus() }
        .alert("Server Connection Required", isPresented: $showServerAlert) {
            Button("OK", role: .cancel) {}
            Button("Retry") { checkServerStatus() }
        } message: {
            Text("Cannot connect to the server. Please retry \(APIConfig.baseURL).")
        }
    }

    // MARK: - Server Health

    /// Checks whether the Flask backend is reachable and updates "serverOnline"
    
    /// If the server comes back online and the email format is already valid, an availability check is immediately re-run so the checklist stays current
    /// If offline, any stale availability result is cleared to prevent false "already registered" messages being shown
    func checkServerStatus() {
        NetworkManager.shared.checkServerHealth { isOnline in
            serverOnline = isOnline
            if isOnline {
                errorMessage = ""
                // Re-run availability check if the email format is already valid
                if usernameValid && atSignValid && domainValid {
                    checkEmailAvailability()
                }
            } else {
                // Clear stale result so no false "already registered" message appears
                emailAvailable = false
                errorMessage = ""
            }
        }
    }

    // MARK: - Email Validation

    /// Validates the format of the current email address and triggers an availability check if all format rules pass and the server is online
    
    /// Splits the address on "@" to check for a non-empty username, the presence of "@", and a domain containing "."
    /// Resets "emailAvailable" and clears any existing error message on every call
    func validateEmail() {
        let parts = email.split(separator: "@")
        usernameValid = parts.first?.isEmpty == false
        atSignValid   = email.contains("@")
        domainValid   = parts.count == 2 && parts[1].contains(".")

        // Reset availability and errors before re-checking
        emailAvailable = false
        errorMessage   = ""

        if usernameValid && atSignValid && domainValid && serverOnline {
            checkEmailAvailability()
        }
    }

    /// Queries the "/check_email" endpoint to confirm the address is not already registered
    
    /// Sets "emailAvailable" based on the "available" boolean in the response
    /// If the server becomes unreachable during the check, "serverOnline" is set to "false" and the offline banner takes over messaging
    func checkEmailAvailability() {
        guard serverOnline else {
            emailAvailable = false
            return
        }

        checkingEmail = true
        errorMessage  = ""

        NetworkManager.shared.post(endpoint: "/check_email", body: ["email": email]) { result in
            checkingEmail = false
            switch result {
            case .success(let json):
                if let available = json["available"] as? Bool {
                    emailAvailable = available
                    if !available {
                        errorMessage = "This email is already registered. Please log in instead."
                    }
                }
            case .failure(let error):
                if case .serverUnavailable = error {
                    // Server went offline, let the banner handle messaging
                    serverOnline   = false
                    emailAvailable = false
                    errorMessage   = ""
                } else {
                    errorMessage   = error.userMessage
                    emailAvailable = false
                }
            }
        }
    }

    /// Returns "true" only when all format rules pass, the email is confirmed available, and the server is reachable
    func allEmailRulesValid() -> Bool {
        usernameValid && atSignValid && domainValid && emailAvailable && serverOnline
    }

    // MARK: - Send Verification Code

    /// Generates a six-digit verification code, sends it to the user's email via the "/send_code" endpoint, and navigates to "RegisterPasswordView" on success
    
    /// The code is generated locally as a zero-padded random integer and passed to the backend, which emails it to the user
    /// The same code is forwarded to "RegisterPasswordView" for local comparison during Step 2
    func sendVerificationCode() {
        guard allEmailRulesValid() else { return }

        sendingCode      = true
        errorMessage     = ""
        // Generate a zero-padded six-digit code (e.g. "042731")
        verificationCode = String(format: "%06d", Int.random(in: 0...999999))

        NetworkManager.shared.post(endpoint: "/send_code", body: ["email": email, "code": verificationCode]) { result in
            sendingCode = false
            switch result {
            case .success:
                // Code sent, proceed to password creation step
                showPasswordView = true
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline    = false
                    emailAvailable  = false
                    errorMessage    = ""
                    showServerAlert = true
                } else {
                    errorMessage = error.userMessage
                }
            }
        }
    }
}
