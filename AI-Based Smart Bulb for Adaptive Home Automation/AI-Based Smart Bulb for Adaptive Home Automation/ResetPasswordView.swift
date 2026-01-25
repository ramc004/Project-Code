import SwiftUI
import Combine

struct ResetPasswordView: View {
   var email: String
   @State var verificationCode: String

   @Binding var loginMessage: String

   @State private var codeInput = ""
   @State private var newPassword = ""
   @State private var showPassword = false
   @State private var codeValid = false
   @State private var passwordLengthValid = false
   @State private var passwordUppercaseValid = false
   @State private var passwordNumberValid = false
   @State private var passwordSpecialCharValid = false
   @State private var resetting = false
   @State private var errorMessage = ""
   
   @State private var timeRemaining = 300
   @State private var timerActive = true
   @State private var codeExpired = false
   @State private var resendingCode = false
   @State private var resendMessage = ""
   
   let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

   @Environment(\.presentationMode) var presentationMode

   var body: some View {
       ScrollView {
           VStack(alignment: .leading, spacing: 20) {
               Text("Reset Password")
                   .font(.largeTitle)
                   .bold()

               VStack(alignment: .leading) {
                   Text("Enter 6-digit code sent to \(email)")
                       .font(.headline)
                   
                   HStack {
                       Text(codeExpired ? "Code expired" : "Code expires in: \(formattedTime())")
                           .font(.subheadline)
                           .foregroundColor(codeExpired ? .red : (timeRemaining <= 60 ? .orange : .gray))
                           .bold()
                       
                       Spacer()
                       
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

                   TextField("6-digit code", text: $codeInput)
                       .textFieldStyle(RoundedBorderTextFieldStyle())
                       .keyboardType(.numberPad)
                       .disabled(codeExpired)
                       .onChange(of: codeInput) { _ in
                           codeInput = codeInput.filter { $0.isNumber }
                           if codeInput.count > 6 { codeInput = String(codeInput.prefix(6)) }

                           if codeInput.count == 6 && !codeExpired {
                               codeValid = codeInput.trimmingCharacters(in: .whitespacesAndNewlines) == verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
                           } else {
                               codeValid = false
                           }
                       }

                   if !codeInput.isEmpty && !codeExpired {
                       Text(codeValid ? "Code correct" : "Code incorrect")
                           .foregroundColor(codeValid ? .green : .red)
                           .bold()
                   }
                   
                   if !resendMessage.isEmpty {
                       Text(resendMessage)
                           .font(.subheadline)
                           .foregroundColor(resendMessage.contains("sent") ? .green : .red)
                           .bold()
                   }
               }

               VStack(alignment: .leading) {
                   Text("New Password")
                       .font(.headline)
                   HStack {
                       if showPassword {
                           TextField("Enter new password", text: $newPassword)
                       } else {
                           SecureField("Enter new password", text: $newPassword)
                       }
                       Button(action: { showPassword.toggle() }) {
                           Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                               .foregroundColor(.gray)
                       }
                   }
                   .textFieldStyle(RoundedBorderTextFieldStyle())
                   .onChange(of: newPassword) { _ in validatePassword() }
               }

               VStack(alignment: .leading, spacing: 6) {
                   Text("Password Rules:")
                       .font(.subheadline)
                       .bold()
                   Text("\(passwordLengthValid ? "✅" : "❌") At least 8 characters")
                   Text("\(passwordUppercaseValid ? "✅" : "❌") At least one uppercase letter")
                   Text("\(passwordNumberValid ? "✅" : "❌") At least one number")
                   Text("\(passwordSpecialCharValid ? "✅" : "❌") At least one special character (!@#$%^&*)")
               }
               .foregroundColor(.gray)
               
               if !errorMessage.isEmpty {
                   Text(errorMessage).foregroundColor(.red).bold()
               }

               Button(action: resetPassword) {
                   Text(resetting ? "Resetting..." : "Reset Password")
                       .frame(maxWidth: .infinity)
               }
               .buttonStyle(ModernButtonStyle(backgroundColor: .green))
               .disabled(!allPasswordRulesValid() || !codeValid || codeExpired || resetting)
               .padding(.top, 20)
           }
           .padding()
       }
       .navigationTitle("Reset Password")
       .onReceive(timer) { _ in
           if timerActive && timeRemaining > 0 {
               timeRemaining -= 1
           } else if timeRemaining == 0 {
               codeExpired = true
               codeValid = false
               timerActive = false
           }
       }
   }
   
   func formattedTime() -> String {
       let minutes = timeRemaining / 60
       let seconds = timeRemaining % 60
       return String(format: "%d:%02d", minutes, seconds)
   }

   func validatePassword() {
       passwordLengthValid = newPassword.count >= 8
       passwordUppercaseValid = newPassword.range(of: "[A-Z]", options: .regularExpression) != nil
       passwordNumberValid = newPassword.range(of: "[0-9]", options: .regularExpression) != nil
       passwordSpecialCharValid = newPassword.range(of: "[!@#$%^&*()_+{}:<>?]", options: .regularExpression) != nil
   }

   func allPasswordRulesValid() -> Bool {
       return passwordLengthValid && passwordUppercaseValid && passwordNumberValid && passwordSpecialCharValid
   }

   func resetPassword() {
       resetting = true
       errorMessage = ""
       
       guard let url = URL(string: "\(APIConfig.baseURL)/reset_password") else { return }
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": newPassword])
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")

       URLSession.shared.dataTask(with: request) { data, response, error in
           DispatchQueue.main.async {
               resetting = false
               
               if let httpResponse = response as? HTTPURLResponse {
                   if httpResponse.statusCode == 200 {
                       loginMessage = "Password has been reset successfully. Please login with your new password."
                       presentationMode.wrappedValue.dismiss()
                   } else if let data = data,
                             let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                             let message = json["message"] as? String {
                       errorMessage = message
                   } else {
                       errorMessage = "Password reset failed. Please try again."
                   }
               } else {
                   errorMessage = "Network error. Please check your connection."
               }
           }
       }.resume()
   }
   
   func resendVerificationCode() {
       resendingCode = true
       resendMessage = ""
       verificationCode = String(format: "%06d", Int.random(in: 0...999999)).trimmingCharacters(in: .whitespacesAndNewlines)
       
       guard let url = URL(string: "\(APIConfig.baseURL)/send_code") else { return }
       var request = URLRequest(url: url)
       request.httpMethod = "POST"
       request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "code": verificationCode])
       request.setValue("application/json", forHTTPHeaderField: "Content-Type")

       URLSession.shared.dataTask(with: request) { _, _, error in
           DispatchQueue.main.async {
               resendingCode = false
               if error != nil {
                   resendMessage = "Failed to resend code"
               } else {
                   resendMessage = "New code sent!"
                   timeRemaining = 300
                   codeExpired = false
                   timerActive = true
                   codeInput = ""
                   codeValid = false
                   
                   DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                       resendMessage = ""
                   }
               }
           }
       }.resume()
   }
}
