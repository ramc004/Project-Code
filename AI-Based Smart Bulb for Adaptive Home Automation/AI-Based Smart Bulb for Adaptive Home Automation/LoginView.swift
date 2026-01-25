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
              
              // Server Status Indicator
              if !serverOnline {
                  HStack(spacing: 10) {
                      Image(systemName: "exclamationmark.triangle.fill")
                          .foregroundColor(.red)
                      VStack(alignment: .leading, spacing: 4) {
                          Text("Server Offline")
                              .font(.subheadline)
                              .bold()
                              .foregroundColor(.red)
                          Text("Please start the Flask server on your Mac")
                              .font(.caption)
                              .foregroundColor(.gray)
                      }
                      Spacer()
                      Button("Retry") {
                          checkServerStatus()
                      }
                      .font(.caption)
                      .padding(.horizontal, 12)
                      .padding(.vertical, 6)
                      .background(Color.blue)
                      .foregroundColor(.white)
                      .cornerRadius(8)
                  }
                  .padding()
                  .background(Color.red.opacity(0.1))
                  .cornerRadius(10)
              }

              VStack(alignment: .leading) {
                  Text("Email").font(.headline)
                  TextField("Enter your email", text: $email)
                      .textFieldStyle(RoundedBorderTextFieldStyle())
                      .autocapitalization(.none)
                      .keyboardType(.emailAddress)
                      .onChange(of: email) { _ in
                          emailValid = true
                          errorMessage = ""
                          loginMessage = ""
                      }
                      .disabled(!serverOnline)
              }

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
                      errorMessage = ""
                  }
                  .disabled(!serverOnline)
              }

              if !errorMessage.isEmpty {
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

              Button(action: loginUser) {
                  Text(loggingIn ? "Logging in..." : "Login").frame(maxWidth: .infinity)
              }
              .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
              .disabled(loggingIn || !serverOnline)
              .padding(.top, 20)

              Button(action: initiateForgotPassword) {
                  Text("Forgot Password?").foregroundColor(.red).underline()
              }
              .padding(.top, 10)
              .disabled(!serverOnline)

              NavigationLink("", destination: ResetPasswordView(email: email, verificationCode: resetCode, loginMessage: $loginMessage), isActive: $showResetPassword)
              NavigationLink("", destination: HomeView(), isActive: $navigateToHome)
          }
          .padding()
      }
      .navigationTitle("Login")
      .onAppear {
          checkServerStatus()
      }
      .alert("Server Connection Required", isPresented: $showServerAlert) {
          Button("OK", role: .cancel) {}
          Button("Retry") {
              checkServerStatus()
          }
      } message: {
          Text("Cannot connect to the server. Please make sure the Flask server is running on your Mac at \(APIConfig.baseURL)")
      }
  }
  
  func checkServerStatus() {
      NetworkManager.shared.checkServerHealth { isOnline in
          serverOnline = isOnline
          if !isOnline {
              errorMessage = "Server is offline. Please start the Flask server."
          } else {
              errorMessage = ""
          }
      }
  }

  func loginUser() {
      loginMessage = ""
      errorMessage = ""

      if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          emailValid = false
          errorMessage = "Email cannot be empty."
          return
      }

      if password.isEmpty {
          passwordValid = false
          errorMessage = "Password cannot be empty."
          return
      }
      
      guard serverOnline else {
          errorMessage = "Cannot login - server is offline"
          showServerAlert = true
          return
      }
      
      loggingIn = true

      NetworkManager.shared.post(endpoint: "/login", body: ["email": email, "password": password]) { result in
          loggingIn = false
          
          switch result {
          case .success(_):
              // Store email locally for session management
              UserDefaults.standard.set(email, forKey: "currentUserEmail")
              UserDefaults.standard.set(true, forKey: "isLoggedIn")
              navigateToHome = true
              
          case .failure(let error):
              if case .serverUnavailable = error {
                  serverOnline = false
                  showServerAlert = true
              } else if case .requestFailed(let message) = error {
                  if message.contains("not registered") {
                      errorMessage = "This email has not been registered. Please register first."
                  } else if message.contains("password") {
                      errorMessage = "Incorrect password. Please try again."
                  } else {
                      errorMessage = message
                  }
              } else {
                  errorMessage = error.userMessage
              }
          }
      }
  }

    func initiateForgotPassword() {
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Please enter your email address first."
            return
        }
        
        guard serverOnline else {
            errorMessage = "Cannot reset password - server is offline"
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
                    
                    // Email exists, send reset code
                    resetCode = String(format: "%06d", Int.random(in: 0...999999))
                    
                    NetworkManager.shared.post(endpoint: "/send_code", body: ["email": email, "code": resetCode]) { sendResult in
                        switch sendResult {
                        case .success(_):
                            showResetPassword = true
                        case .failure(let error):
                            if case .serverUnavailable = error {
                                serverOnline = false
                                showServerAlert = true
                            }
                            errorMessage = error.userMessage
                        }
                    }
                }
                
            case .failure(let error):
                if case .serverUnavailable = error {
                    serverOnline = false
                    showServerAlert = true
                }
                errorMessage = error.userMessage
            }
        }
    }
}
