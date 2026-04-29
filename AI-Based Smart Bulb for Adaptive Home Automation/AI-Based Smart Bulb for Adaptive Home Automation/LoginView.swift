// LoginView.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// Presents the login screen where registered users authenticate with their
// email and password. Also handles the forgot-password flow by verifying the
// email exists, generating a reset code, and navigating to ResetPasswordView.

import SwiftUI

/// The login screen for returning users.
///
/// Authenticates the user against the Flask `/login` endpoint. On success,
/// the email and login state are persisted to `UserDefaults` and the user
/// is navigated to `HomeView`.
///
/// Also provides a "Forgot Password?" flow that:
/// 1. Confirms the email is registered via `/check_email`.
/// 2. Generates and sends a six-digit reset code via `/send_code`.
/// 3. Navigates to `ResetPasswordView` to complete the reset.
///
/// A server-offline banner is shown if the backend cannot be reached, disabling
/// all input and actions until connectivity is restored.
struct LoginView: View {

    // MARK: - State

    /// The email address entered by the user.
    @State private var email = ""

    /// The password entered by the user.
    @State private var password = ""

    /// Whether the password field is displayed as plain text or obscured.
    @State private var showPassword = false

    /// Whether the email field contains a valid non-empty value.
    @State private var emailValid = true

    /// Whether the password field contains a non-empty value.
    @State private var passwordValid = true

    /// An inline error message shown when login or forgot-password requests fail.
    @State private var errorMessage = ""

    /// A success message passed back from `ResetPasswordView` on successful reset.
    @State private var loginMessage = ""

    /// True while the login request is in flight.
    @State private var loggingIn = false

    /// Whether the Flask backend server is currently reachable.
    @State private var serverOnline = true

    /// Controls presentation of the server-unavailable alert dialog.
    @State private var showServerAlert = false

    /// Controls navigation to `ResetPasswordView` once the reset code has been sent.
    @State private var showResetPassword = false

    /// The six-digit password reset code generated locally and sent to the user's email.
    @State private var resetCode = ""

    /// Controls navigation to `HomeView` after a successful login.
    @State private var navigateToHome = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Login")
                    .font(.largeTitle)
                    .bold()

                // ── Server Offline Banner ──────────────────────────────────
                // Replaces inline error messages when the server cannot be reached.
                // Disables all input fields and action buttons until the user retries.
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

                // ── Email Field ────────────────────────────────────────────
                // Clears error and success messages on every keystroke to keep
                // the UI state consistent with what the user has typed.
                VStack(alignment: .leading) {
                    Text("Email").font(.headline)
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .onChange(of: email) { _ in
                            emailValid   = true
                            errorMessage = ""
                            loginMessage = ""
                        }
                        .disabled(!serverOnline)
                        .opacity(serverOnline ? 1.0 : 0.5)
                }

                // ── Password Field ─────────────────────────────────────────
                // Toggle between SecureField and TextField to allow the user
                // to reveal their password while typing.
                VStack(alignment: .leading) {
                    Text("Password").font(.headline)
                    HStack {
                        if showPassword {
                            TextField("Enter password", text: $password)
                        } else {
                            SecureField("Enter password", text: $password)
                        }
                        // Eye icon toggles password visibility
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: password) { _ in
                        passwordValid = true
                        errorMessage  = ""
                    }
                    .disabled(!serverOnline)
                    .opacity(serverOnline ? 1.0 : 0.5)
                }

                // ── Inline Error Message ───────────────────────────────────
                // Only shown when the server is online; the offline banner
                // handles all messaging when the server cannot be reached.
                if !errorMessage.isEmpty && serverOnline {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                // ── Success Message ────────────────────────────────────────
                // Displayed when navigating back from ResetPasswordView after
                // a successful password reset, prompting the user to log in again.
                if !loginMessage.isEmpty {
                    Text(loginMessage)
                        .foregroundColor(.green)
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }

                // ── Login Button ───────────────────────────────────────────
                // Disabled while a request is in flight or the server is offline.
                Button(action: loginUser) {
                    Text(loggingIn ? "Logging in…" : "Login").frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                .disabled(loggingIn || !serverOnline)
                .padding(.top, 20)

                // ── Forgot Password ────────────────────────────────────────
                // Requires the email field to be populated before proceeding.
                // Disabled when the server is offline.
                Button(action: initiateForgotPassword) {
                    Text("Forgot Password?").foregroundColor(.red).underline()
                }
                .padding(.top, 10)
                .disabled(!serverOnline)

                // Hidden NavigationLinks — activated programmatically
                NavigationLink(
                    "",
                    destination: ResetPasswordView(email: email, verificationCode: resetCode, loginMessage: $loginMessage),
                    isActive: $showResetPassword
                )
                NavigationLink("", destination: HomeView(), isActive: $navigateToHome)
            }
            .padding()
        }
        .navigationTitle("Login")
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

    /// Checks whether the Flask backend is reachable and updates `serverOnline`.
    ///
    /// Clears any stale error message regardless of the result so that the
    /// offline banner becomes the sole source of messaging when offline.
    func checkServerStatus() {
        NetworkManager.shared.checkServerHealth { isOnline in
            serverOnline = isOnline
            // Clear stale errors in both cases — the banner handles offline messaging
            errorMessage = ""
        }
    }

    // MARK: - Login

    /// Validates the input fields and submits credentials to the `/login` endpoint.
    ///
    /// On success, the user's email and login flag are persisted to `UserDefaults`
    /// and the view navigates to `HomeView`. Failure responses are mapped to
    /// user-friendly messages based on the error content returned by the server.
    func loginUser() {
        loginMessage = ""
        errorMessage = ""

        // Guard: email must not be blank
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            emailValid   = false
            errorMessage = "Email cannot be empty."
            return
        }
        // Guard: password must not be blank
        guard !password.isEmpty else {
            passwordValid = false
            errorMessage  = "Password cannot be empty."
            return
        }
        // Guard: server must be reachable before attempting the request
        guard serverOnline else {
            showServerAlert = true
            return
        }

        loggingIn = true

        NetworkManager.shared.post(endpoint: "/login", body: ["email": email, "password": password]) { result in
            loggingIn = false
            switch result {
            case .success:
                // Persist session data and navigate to the main app screen
                UserDefaults.standard.set(email, forKey: "currentUserEmail")
                UserDefaults.standard.set(true,  forKey: "isLoggedIn")
                navigateToHome = true

            case .failure(let error):
                switch error {
                case .serverUnavailable:
                    // Server went offline mid-request — show the banner
                    serverOnline    = false
                    errorMessage    = ""
                    showServerAlert = true
                case .requestFailed(let message):
                    // Map server error messages to user-friendly descriptions
                    if message.contains("not registered") {
                        errorMessage = "This email hasn't been registered. Please register first."
                    } else if message.lowercased().contains("password") {
                        errorMessage = "Incorrect password. Please try again."
                    } else {
                        errorMessage = message
                    }
                default:
                    errorMessage = error.userMessage
                }
            }
        }
    }

    // MARK: - Forgot Password

    /// Initiates the forgot-password flow for the email address currently in the field.
    ///
    /// First confirms the email is registered via `/check_email`. If registered,
    /// generates a six-digit reset code, sends it via `/send_code`, and navigates
    /// to `ResetPasswordView`. If the email is not registered, an inline error
    /// is shown prompting the user to register instead.
    func initiateForgotPassword() {
        // Guard: email field must contain an address before proceeding
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your email address first."
            return
        }
        guard serverOnline else {
            showServerAlert = true
            return
        }

        NetworkManager.shared.post(endpoint: "/check_email", body: ["email": email]) { result in
            switch result {
            case .success(let json):
                if let available = json["available"] as? Bool {
                    if available {
                        // `available = true` means the email is NOT yet registered
                        errorMessage = "This email is not registered."
                        return
                    }
                    // Email is registered — generate and send a reset code
                    resetCode = String(format: "%06d", Int.random(in: 0...999999))
                    NetworkManager.shared.post(endpoint: "/send_code", body: ["email": email, "code": resetCode]) { sendResult in
                        switch sendResult {
                        case .success:
                            // Code sent — navigate to the password reset screen
                            showResetPassword = true
                        case .failure(let error):
                            if case .serverUnavailable = error {
                                serverOnline    = false
                                errorMessage    = ""
                                showServerAlert = true
                            } else {
                                errorMessage = error.userMessage
                            }
                        }
                    }
                }
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline    = false
                    errorMessage    = ""
                    showServerAlert = true
                } else {
                    errorMessage = error.userMessage
                }
            }
        }
    }
}
