import SwiftUI

// MARK: - Modern Button Style
struct ModernButtonStyle: ButtonStyle {
   var backgroundColor: Color
   @State private var isHovered = false

   func makeBody(configuration: Configuration) -> some View {
       configuration.label
           .padding()
           .frame(maxWidth: .infinity)
           .background(
               RoundedRectangle(cornerRadius: 20)
                   .fill(backgroundColor.opacity(configuration.isPressed ? 0.4 : 0.65))
           )
           .overlay(
               RoundedRectangle(cornerRadius: 20)
                   .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
           )
           .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 4)
           .foregroundColor(.white)
           .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
           .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
           .onHover { hovering in
               #if os(macOS)
               isHovered = hovering
               #endif
           }
   }
}

// MARK: - Welcome View
struct WelcomeView: View {
   var body: some View {
       NavigationStack {
           ZStack {
               LinearGradient(
                   colors: [
                       Color(red: 0.95, green: 0.92, blue: 1.0),
                       Color(red: 0.9, green: 0.95, blue: 1.0),
                       Color(red: 0.85, green: 0.97, blue: 1.0)
                   ],
                   startPoint: .top,
                   endPoint: .bottom
               )
               .ignoresSafeArea()

               VStack(spacing: 40) {
                   Text("AI-Based Smart Bulb")
                       .font(.largeTitle)
                       .bold()
                       .padding(.top, 40)
                       .multilineTextAlignment(.center)

                   VStack(spacing: 22) {
                       NavigationLink {
                           RegisterEmailView()
                       } label: {
                           Text("Register").font(.headline)
                       }
                       .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                       .padding(.horizontal, 50)

                       NavigationLink {
                           LoginView()
                       } label: {
                           Text("Login").font(.headline)
                       }
                       .buttonStyle(ModernButtonStyle(backgroundColor: .purple))
                       .padding(.horizontal, 50)
                   }

                   Spacer()
               }
           }
       }
   }
}

struct WelcomeView_Previews: PreviewProvider {
   static var previews: some View {
       WelcomeView()
   }
}
