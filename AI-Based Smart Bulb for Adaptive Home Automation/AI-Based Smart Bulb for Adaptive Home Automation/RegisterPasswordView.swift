// RegisterPasswordView.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// Step 2 of the two-step registration flow. Collects the six-digit verification
// code sent to the user's email and a new password meeting all complexity rules.
// On successful registration, navigates the user to LoginView.

import SwiftUI
import Combine

/// The second step of the user registration flow.
///
/// Receives the email address and verification code generated in `RegisterEmailView`.
/// The user must:
/// 1. Enter the six-digit code before it expires (5-minute countdown).
/// 2. Create a password satisfying all four complexity rules.
///
/// The Register button is enabled only when both conditions are met. If the code
/// expires, a Resend button appears to generate and send a fresh code, resetting
/// the countdown. On successful registration the user's email is stored in
/// `UserDefaults` and the view navigates to `LoginView`.
struct RegisterPasswordView: View {

    // MARK: - Inputs

    /// The email address carried over from `RegisterEmailView`.
    var email: String

    /// The six-digit verification code generated and sent in `RegisterEmailView`.
    /// Declared as `@State` so it can be replaced when the user requests a resend.
    @State var verificationCode: String

    // MARK: - State

    /// The code entered by the user in the verification field.
    @State private var codeInput = ""

    /// The password entered by the user.
    @State private var password = ""

    /// Whether the password is displayed as plain text or obscured.
    @State private var showPassword = false

    /// Whether the password meets the minimum length requirement (8+ characters).
    @State private var passwordLengthValid = false

    /// Whether the password contains at least one uppercase letter.
    @State private var passwordUppercaseValid = false

    /// Whether the password contains at least one numeric digit.
    @State private var passwordNumberValid = false

    /// Whether the password contains at least one special character.
    @State private var passwordSpecialCharValid = false

    /// Whether the entered code matches the expected verification code.
    @State private var codeValid = false

    /// Controls navigation to `LoginView` after successful registration.
    @State private var navigateToLogin = false

    /// True while the registration request is in flight.
    @State private var registering = false

    /// An error message displayed inline when registration fails.
    @State private var errorMessage = ""

    /// Remaining seconds before the verification code expires (starts at 300 = 5 minutes).
    @State private var timeRemaining = 300

    /// Whether the countdown timer is currently running.
    @State private var timerActive = true

    /// Whether the verification code has expired (countdown reached zero).
    @State private var codeExpired = false

    /// True while a resend code request is in flight.
    @State private var resendingCode = false

    /// A brief status message shown after a resend attempt ("New code sent!" or error).
    @State private var resendMessage = ""

    /// A one-second repeating timer used to drive the code expiry countdown.
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Create Password").font(.largeTitle).bold()

                // ── Verification Code Section ──────────────────────────────
                VStack(alignment: .leading) {
                    Text("Enter 6-digit code sent to \(email)").font(.headline)

                    // Countdown timer display — turns orange below 60 s, red when expired.
                    // Resend button appears when the code is close to or has expired.
                    HStack {
                        Text(codeExpired ? "Code expired" : "Code expires in: \(formattedTime())")
                            .font(.subheadline)
                            .foregroundColor(codeExpired ? .red : (timeRemaining <= 60 ? .orange : .gray))
                            .bold()

                        Spacer()

                        // Show Resend button when the code is expiring soon or has expired
                        if codeExpired || timeRemaining <= 60 {
                            Button(action: resendVerificationCode) {
                                Text(resendingCode ? "Sending..." : "Resend Code")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .underline()
                            }
                            .disabled(resendingCode)
                        }
                    }
                    .padding(.vertical, 5)

                    // Code input field — numeric only, capped at 6 digits, disabled once expired
                    TextField("6-digit code", text: $codeInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .disabled(codeExpired)
                        .onChange(of: codeInput) { _ in
                            // Strip non-numeric characters and enforce a 6-digit maximum
                            codeInput = codeInput.filter { $0.isNumber }
                            if codeInput.count > 6 { codeInput = String(codeInput.prefix(6)) }
                            // Compare against the expected code only if not expired
                            if !codeExpired {
                                codeValid = (codeInput.trimmingCharacters(in: .whitespacesAndNewlines) == verificationCode)
                            } else {
                                codeValid = false
                            }
                        }

                    // Inline correctness indicator — only shown once the user starts typing
                    if !codeInput.isEmpty && !codeExpired {
                        Text(codeValid ? "Code correct" : "Code incorrect")
                            .foregroundColor(codeValid ? .green : .red)
                            .bold()
                    }

                    // Resend status message — auto-clears after 3 seconds on success
                    if !resendMessage.isEmpty {
                        Text(resendMessage)
                            .font(.subheadline)
                            .foregroundColor(resendMessage.contains("sent") ? .green : .red)
                            .bold()
                    }
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
                    .onChange(of: password) { _ in validatePassword() }
                }

                // ── Password Rules Checklist ───────────────────────────────
                // Provides real-time feedback as the user types their password.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password Rules:").font(.subheadline).bold()
                    Text(passwordLengthValid      ? "✅ At least 8 characters"    : "❌ At least 8 characters")
                    Text(passwordUppercaseValid   ? "✅ One uppercase letter"      : "❌ One uppercase letter")
                    Text(passwordNumberValid      ? "✅ One number"                : "❌ One number")
                    Text(passwordSpecialCharValid ? "✅ One special (!@#$%^&*)"   : "❌ One special (!@#$%^&*)")
                }
                .foregroundColor(.gray)

                // Inline error message from a failed registration attempt
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundColor(.red).bold()
                }

                // ── Register Button ────────────────────────────────────────
                // Enabled only when all password rules pass, the code is correct,
                // the code has not expired, and no request is currently in flight.
                Button(action: registerUser) {
                    Text(registering ? "Registering..." : "Register").frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle(backgroundColor: .green))
                .disabled(!allPasswordRulesValid() || !codeValid || codeExpired || registering)
                .padding(.top, 20)

                // Hidden NavigationLink — activated programmatically on successful registration
                NavigationLink("", destination: LoginView(), isActive: $navigateToLogin)
            }
            .padding()
        }
        .navigationTitle("Step 2: Password")
        // Drive the countdown timer — stops when timeRemaining reaches zero
        .onReceive(timer) { _ in
            if timerActive && timeRemaining > 0 {
                timeRemaining -= 1
            } else if timeRemaining == 0 {
                // Code has expired — disable the input field and invalidate the code
                codeExpired = true
                codeValid   = false
                timerActive = false
            }
        }
    }

    // MARK: - Helpers

    /// Formats `timeRemaining` as a `M:SS` string for the countdown display.
    ///
    /// - Returns: A string such as `"4:32"` or `"0:09"`.
    func formattedTime() -> String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Password Validation

    /// Validates the current password against all four complexity rules using
    /// regular expressions, updating the corresponding boolean state properties.
    func validatePassword() {
        passwordLengthValid      = password.count >= 8
        passwordUppercaseValid   = password.range(of: "[A-Z]",            options: .regularExpression) != nil
        passwordNumberValid      = password.range(of: "[0-9]",            options: .regularExpression) != nil
        passwordSpecialCharValid = password.range(of: "[!@#$%^&*()_+{}:<>?]", options: .regularExpression) != nil
    }

    /// Returns `true` only when all four password complexity rules are satisfied.
    func allPasswordRulesValid() -> Bool {
        return passwordLengthValid && passwordUppercaseValid && passwordNumberValid && passwordSpecialCharValid
    }

    // MARK: - Registration

    /// Submits the email and password to the `/register` endpoint.
    ///
    /// On a HTTP 200 response the user's email is persisted to `UserDefaults`
    /// for session management and the view navigates to `LoginView`. Non-200
    /// responses display the server's error message inline.
    func registerUser() {
        registering  = true
        errorMessage = ""

        guard let url = URL(string: "\(APIConfig.baseURL)/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["email": email, "password": password] as [String: Any],
            options: []
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                registering = false

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        // Registration successful — persist email and navigate to login
                        UserDefaults.standard.set(email, forKey: "currentUserEmail")
                        navigateToLogin = true
                    } else if let data = data,
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? String {
                        // Server returned a descriptive error message
                        errorMessage = message
                    } else {
                        errorMessage = "Registration failed. Please try again."
                    }
                } else {
                    errorMessage = "Network error. Please check your connection."
                }
            }
        }.resume()
    }

    // MARK: - Resend Verification Code

    /// Generates a new six-digit verification code, sends it to the user's email,
    /// and resets the countdown timer to 5 minutes.
    ///
    /// Replaces `verificationCode` with the newly generated value so subsequent
    /// comparisons in the code input field use the latest code. The resend status
    /// message auto-clears after 3 seconds on success.
    func resendVerificationCode() {
        resendingCode    = true
        resendMessage    = ""
        // Generate a fresh zero-padded six-digit code
        verificationCode = String(format: "%06d", Int.random(in: 0...999999))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(APIConfig.baseURL)/send_code") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["email": email, "code": verificationCode] as [String: Any],
            options: []
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                resendingCode = false
                if error != nil {
                    resendMessage = "Failed to resend code"
                } else {
                    resendMessage = "New code sent!"
                    // Reset the countdown and re-enable the input field
                    timeRemaining = 300
                    codeExpired   = false
                    timerActive   = true
                    codeInput     = ""
                    codeValid     = false

                    // Auto-clear the success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        resendMessage = ""
                    }
                }
            }
        }.resume()
    }
}
