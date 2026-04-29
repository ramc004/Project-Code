// CircularButtonStyle.swift
// AI-Based Smart Bulb for Adaptive Home Automation
//
// Defines a reusable circular icon button style used throughout the app's
// navigation headers and action areas.

import SwiftUI

/// A custom `ButtonStyle` that renders a fixed-size circular button with
/// a drop shadow and press animations.
///
/// Used across the app wherever a compact circular icon button is needed,
/// such as the dismiss (✕) button in `SettingsView`.
///
/// - Parameters:
///   - backgroundColor: Fill colour of the circle. Defaults to `.blue`.
///   - foregroundColor: Colour applied to the button label (icon). Defaults to `.white`.
///   - size: Diameter of the circle in points. Defaults to `44`.
struct CircularIconButtonStyle: ButtonStyle {

    /// Fill colour of the circular button background.
    var backgroundColor: Color = .blue

    /// Colour of the icon or label rendered inside the button.
    var foregroundColor: Color = .white

    /// Diameter of the circular button in points.
    var size: CGFloat = 44

    /// Builds the styled button body.
    ///
    /// Applies a circular clip, drop shadow, and press animations:
    /// - Opacity drops from 0.8 → 0.6 when pressed.
    /// - Scale shrinks from 1.0 → 0.9 when pressed, giving tactile feedback.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            // Dim the background slightly when the button is pressed
            .background(backgroundColor.opacity(configuration.isPressed ? 0.6 : 0.8))
            .foregroundColor(foregroundColor)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            // Shrink slightly on press for tactile feedback
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
