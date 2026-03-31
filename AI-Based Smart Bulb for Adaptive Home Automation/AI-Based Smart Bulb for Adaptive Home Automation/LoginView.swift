import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var emailValid = true
    @State private var passwordValid = true
    @State private var errorMessage = ""
    @State private var loginMessage = ""
    @State private var loggingIn = false
    @State private var serverOnline = true
    @State private var showServerAlert = false

    @State private var showResetPassword = false
    @State private var resetCode = ""
    @State private var navigateToHome = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Login")
                    .font(.largeTitle)
                    .bold()

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

                // ── Email ──────────────────────────────────────────────────
                VStack(alignment: .leading) {
                    Text("Email").font(.headline)
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .onChange(of: email) { _ in
                            emailValid    = true
                            errorMessage  = ""
                            loginMessage  = ""
                        }
                        .disabled(!serverOnline)
                        .opacity(serverOnline ? 1.0 : 0.5)
                }

                // ── Password ───────────────────────────────────────────────
                VStack(alignment: .leading) {
                    Text("Password").font(.headline)
                    HStack {
                        if showPassword {
                            TextField("Enter password", text: $password)
                        } else {
                            SecureField("Enter password", text: $password)
                        }
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

                // ── Inline messages (only when server is ON) ───────────────
                if !errorMessage.isEmpty && serverOnline {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }

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
                Button(action: loginUser) {
                    Text(loggingIn ? "Logging in…" : "Login").frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                .disabled(loggingIn || !serverOnline)
                .padding(.top, 20)

                // ── Forgot Password ────────────────────────────────────────
                Button(action: initiateForgotPassword) {
                    Text("Forgot Password?").foregroundColor(.red).underline()
                }
                .padding(.top, 10)
                .disabled(!serverOnline)

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
            } else {
                // Wipe any stale error so the banner is the sole message
                errorMessage = ""
            }
        }
    }

    // MARK: - Login
    func loginUser() {
        loginMessage = ""
        errorMessage = ""

        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            emailValid   = false
            errorMessage = "Email cannot be empty."
            return
        }
        guard !password.isEmpty else {
            passwordValid = false
            errorMessage  = "Password cannot be empty."
            return
        }
        guard serverOnline else {
            showServerAlert = true
            return
        }

        loggingIn = true

        NetworkManager.shared.post(endpoint: "/login", body: ["email": email, "password": password]) { result in
            loggingIn = false
            switch result {
            case .success:
                UserDefaults.standard.set(email, forKey: "currentUserEmail")
                UserDefaults.standard.set(true,  forKey: "isLoggedIn")
                navigateToHome = true

            case .failure(let error):
                switch error {
                case .serverUnavailable:
                    serverOnline  = false
                    errorMessage  = ""
                    showServerAlert = true
                case .requestFailed(let message):
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
    func initiateForgotPassword() {
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
                        errorMessage = "This email is not registered."
                        return
                    }
                    resetCode = String(format: "%06d", Int.random(in: 0...999999))
                    NetworkManager.shared.post(endpoint: "/send_code", body: ["email": email, "code": resetCode]) { sendResult in
                        switch sendResult {
                        case .success:
                            showResetPassword = true
                        case .failure(let error):
                            if case .serverUnavailable = error {
                                serverOnline  = false
                                errorMessage  = ""
                                showServerAlert = true
                            } else {
                                errorMessage = error.userMessage
                            }
                        }
                    }
                }
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline  = false
                    errorMessage  = ""
                    showServerAlert = true
                } else {
                    errorMessage = error.userMessage
                }
            }
        }
    }
}
