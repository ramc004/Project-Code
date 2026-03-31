import SwiftUI

struct RegisterEmailView: View {
    @State private var email = ""
    @State private var usernameValid = false
    @State private var atSignValid = false
    @State private var domainValid = false
    @State private var emailAvailable = false
    @State private var showPasswordView = false
    @State private var sendingCode = false
    @State private var checkingEmail = false
    @State private var errorMessage = ""
    @State private var verificationCode = ""
    @State private var serverOnline = true
    @State private var showServerAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Register Account").font(.largeTitle).bold()

                // ── Server Offline Banner ──────────────────────────────────
                if !serverOnline {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 22))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Server is switched off")
                                .font(.subheadline).bold()
                                .foregroundColor(.white)
                            Text("Start the Flask server on your Mac, then tap Retry.")
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

                // ── Validation Checklist ───────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email Validation:").font(.subheadline).bold()
                    Text(usernameValid ? "✅ Username before @ is valid" : "❌ Enter username before @")
                    Text(atSignValid   ? "✅ Contains @"                 : "❌ Missing @")
                    Text(domainValid   ? "✅ Domain is valid"             : "❌ Invalid domain (e.g., example.com)")

                    if !serverOnline {
                        Label("Server offline — availability check skipped", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if checkingEmail {
                        Label("Checking availability…", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else if email.isEmpty || !atSignValid || !domainValid {
                        Text("❌ Email availability unchecked")
                    } else {
                        Text(emailAvailable ? "✅ Email available" : "❌ Email already registered")
                    }
                }
                .foregroundColor(.gray)

                // ── Verify Button ──────────────────────────────────────────
                Button(action: sendVerificationCode) {
                    Text(sendingCode ? "Sending…" : "Verify Email").frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle(backgroundColor: .green))
                .disabled(!allEmailRulesValid() || sendingCode || checkingEmail || !serverOnline)
                .padding(.top, 10)

                // ── Inline error (only shown when server IS online) ─────────
                if !errorMessage.isEmpty && serverOnline {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

                NavigationLink(
                    "",
                    destination: RegisterPasswordView(email: email, verificationCode: verificationCode),
                    isActive: $showPasswordView
                )
            }
            .padding()
        }
        .navigationTitle("Step 1: Email")
        .onAppear { checkServerStatus() }
        .alert("Server Connection Required", isPresented: $showServerAlert) {
            Button("OK", role: .cancel) {}
            Button("Retry") { checkServerStatus() }
        } message: {
            Text("Cannot connect to the server. Please make sure the Flask server is running at \(APIConfig.baseURL).")
        }
    }

    // MARK: - Server Health
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
                // Clear any stale availability result so no false "already registered" appears
                emailAvailable = false
                errorMessage = ""
            }
        }
    }

    // MARK: - Email Validation
    func validateEmail() {
        let parts = email.split(separator: "@")
        usernameValid = parts.first?.isEmpty == false
        atSignValid   = email.contains("@")
        domainValid   = parts.count == 2 && parts[1].contains(".")

        emailAvailable = false
        errorMessage   = ""

        if usernameValid && atSignValid && domainValid && serverOnline {
            checkEmailAvailability()
        }
    }

    func checkEmailAvailability() {
        guard serverOnline else {
            emailAvailable = false
            return
        }

        checkingEmail  = true
        errorMessage   = ""

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
                    serverOnline   = false
                    emailAvailable = false
                    errorMessage   = ""        // banner handles the messaging
                } else {
                    errorMessage   = error.userMessage
                    emailAvailable = false
                }
            }
        }
    }

    func allEmailRulesValid() -> Bool {
        usernameValid && atSignValid && domainValid && emailAvailable && serverOnline
    }

    // MARK: - Send Code
    func sendVerificationCode() {
        guard allEmailRulesValid() else { return }

        sendingCode    = true
        errorMessage   = ""
        verificationCode = String(format: "%06d", Int.random(in: 0...999999))

        NetworkManager.shared.post(endpoint: "/send_code", body: ["email": email, "code": verificationCode]) { result in
            sendingCode = false
            switch result {
            case .success:
                showPasswordView = true
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline   = false
                    emailAvailable = false
                    errorMessage   = ""
                    showServerAlert = true
                } else {
                    errorMessage = error.userMessage
                }
            }
        }
    }
}
