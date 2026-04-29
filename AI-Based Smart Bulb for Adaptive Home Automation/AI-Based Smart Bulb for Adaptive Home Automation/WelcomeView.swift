// WelcomeView.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// The app's landing screen, presented on launch. Displays the app title and
// provides navigation entry points for user registration and login.
// Also defines ModernButtonStyle, the shared full-width button style used
// throughout the authentication flow.

import SwiftUI

// MARK: - Modern Button Style

/// A full-width rounded button style used throughout the authentication flow.
///
/// Features a semi-transparent filled background, a subtle grey border, a drop
/// shadow, and press/hover animations for tactile and visual feedback.
///
/// - Parameter backgroundColor: The tint colour applied to the button background.
///   Opacity is reduced when pressed (0.4) and at rest (0.65).
struct ModernButtonStyle: ButtonStyle {

    /// The tint colour of the button background.
    var backgroundColor: Color

    /// Tracks hover state on macOS to apply a slight scale-up effect.
    @State private var isHovered = false

    /// Builds the styled button body.
    ///
    /// - Opacity drops from 0.65 → 0.4 when pressed.
    /// - Scale shrinks from 1.0 → 0.97 when pressed.
    /// - On macOS, scale grows to 1.02 when hovered.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    // Dim background on press for visual feedback
                    .fill(backgroundColor.opacity(configuration.isPressed ? 0.4 : 0.65))
            )
            .overlay(
                // Subtle grey border around the button
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 4)
            .foregroundColor(.white)
            // Shrink on press; expand slightly on hover (macOS only)
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering in
                // Hover state is only meaningful on macOS; ignored on iOS/iPadOS
                #if os(macOS)
                isHovered = hovering
                #endif
            }
    }
}

// MARK: - Welcome View

/// The root landing screen presented when the app launches.
///
/// Displays the app title over a soft purple-to-blue linear gradient background,
/// with two navigation buttons leading to the registration and login flows.
/// `WelcomeView` owns the root `NavigationStack` for the authentication journey.
struct WelcomeView: View {

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft purple-to-blue gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.92, blue: 1.0),
                        Color(red: 0.9,  green: 0.95, blue: 1.0),
                        Color(red: 0.85, green: 0.97, blue: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    // App title
                    Text("AI-Based Smart Bulb")
                        .font(.largeTitle)
                        .bold()
                        .padding(.top, 40)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 22) {
                        // Navigate to the email registration flow (Step 1)
                        NavigationLink {
                            RegisterEmailView()
                        } label: {
                            Text("Register").font(.headline)
                        }
                        .buttonStyle(ModernButtonStyle(backgroundColor: .blue))
                        .padding(.horizontal, 50)

                        // Navigate to the login screen
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

// MARK: - Preview

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
    }
}
