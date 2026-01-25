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
                   Text("Email Address").font(.headline)
                   TextField("Enter your email", text: $email)
                       .textFieldStyle(RoundedBorderTextFieldStyle())
                       .autocapitalization(.none)
                       .keyboardType(.emailAddress)
                       .onChange(of: email) { _ in validateEmail() }
                       .disabled(!serverOnline)
               }

               VStack(alignment: .leading, spacing: 6) {
                   Text("Email Validation:").font(.subheadline).bold()
                   Text(usernameValid ? "✅ Username before @ is valid" : "❌ Enter username before @")
                   Text(atSignValid ? "✅ Contains @" : "❌ Missing @")
                   Text(domainValid ? "✅ Domain is valid" : "❌ Invalid domain (e.g., example.com)")
                   
                   if !serverOnline {
                       Text("⚠️ Cannot check availability - server offline")
                           .foregroundColor(.orange)
                   } else if checkingEmail {
                       Text("⏳ Checking availability...")
                   } else if email.isEmpty || !atSignValid || !domainValid {
                       Text("❌ Email availability unchecked")
                   } else {
                       Text(emailAvailable ? "✅ Email available" : "❌ Email already registered")
                   }
               }
               .foregroundColor(.gray)

               Button(action: sendVerificationCode) {
                   Text(sendingCode ? "Sending..." : "Verify Email").frame(maxWidth: .infinity)
               }
               .buttonStyle(ModernButtonStyle(backgroundColor: .green))
               .disabled(!allEmailRulesValid() || sendingCode || checkingEmail || !serverOnline)
               .padding(.top, 10)

               if !errorMessage.isEmpty {
                   Text(errorMessage)
                       .foregroundColor(.red)
                       .bold()
                       .padding()
                       .frame(maxWidth: .infinity)
                       .background(Color.red.opacity(0.1))
                       .cornerRadius(8)
               }

               NavigationLink("", destination: RegisterPasswordView(email: email, verificationCode: verificationCode), isActive: $showPasswordView)
           }
           .padding()
       }
       .navigationTitle("Step 1: Email")
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
               emailAvailable = false
           } else {
               errorMessage = ""
               // Re-validate email if format is correct
               if usernameValid && atSignValid && domainValid {
                   checkEmailAvailability()
               }
           }
       }
   }

   func validateEmail() {
       let parts = email.split(separator: "@")
       usernameValid = (parts.first?.isEmpty == false)
       atSignValid = email.contains("@")
       domainValid = parts.count == 2 && parts[1].contains(".")
       
       // Reset availability when email changes
       emailAvailable = false
       errorMessage = ""
       
       // Check email availability with backend if format is valid and server is online
       if usernameValid && atSignValid && domainValid && serverOnline {
           checkEmailAvailability()
       }
   }
   
   func checkEmailAvailability() {
       guard serverOnline else {
           emailAvailable = false
           return
       }
       
       checkingEmail = true
       errorMessage = ""
       
       NetworkManager.shared.post(endpoint: "/check_email", body: ["email": email]) { result in
           checkingEmail = false
           
           switch result {
           case .success(let json):
               if let available = json["available"] as? Bool {
                   emailAvailable = available
                   if !available {
                       errorMessage = "This email is already registered. Please login instead."
                   }
               }
               
           case .failure(let error):
               if case .serverUnavailable = error {
                   serverOnline = false
                   emailAvailable = false
                   errorMessage = "Server connection lost. Please check if the server is running."
               } else {
                   errorMessage = error.userMessage
                   emailAvailable = false
               }
           }
       }
   }

   func allEmailRulesValid() -> Bool {
       return usernameValid && atSignValid && domainValid && emailAvailable && serverOnline
   }

   func sendVerificationCode() {
       guard allEmailRulesValid() else {
           errorMessage = "Please fix all validation errors before continuing"
           return
       }
       
       guard serverOnline else {
           errorMessage = "Cannot send verification code - server is offline"
           showServerAlert = true
           return
       }

       sendingCode = true
       errorMessage = ""
       verificationCode = String(format: "%06d", Int.random(in: 0...999999)).trimmingCharacters(in: .whitespacesAndNewlines)

       NetworkManager.shared.post(endpoint: "/send_code", body: ["email": email, "code": verificationCode]) { result in
           sendingCode = false
           
           switch result {
           case .success(_):
               showPasswordView = true
               
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
