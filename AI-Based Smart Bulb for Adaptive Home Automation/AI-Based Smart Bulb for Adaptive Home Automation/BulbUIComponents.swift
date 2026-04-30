// BulbUIComponents.swift
// AI-Based Smart Bulb for Adaptive Home Automation

// Defines reusable UI components shared across bulb control views, including the animated bulb visual and effect mode selection buttons

import SwiftUI

// MARK: - Bulb Visual

/// A view that renders an animated lightbulb icon reflecting the current bulb state

/// When the bulb is on, a radial glow is displayed behind the icon, tinted according to the current colour temperature
/// The icon opacity scales with the brightness value
/// When off, the icon is shown in grey with no glow

/// - Parameter state: A "BulbState" value describing the current power, brightness, and colour temperature of the bulb
struct BulbVisualView: View {

    /// The current state of the bulb (power, brightness, colour temperature)
    let state: BulbState

    /// Computes the display colour by interpolating between warm amber and cool white based on "state.colourTemp"
    
    /// - "colourTemp" of 255 produces warm amber (high red/green, low blue)
    /// - "colourTemp" of 0 produces cool white (full red, green, and blue)
    /// - "t" is a normalised interpolation factor: 0.0 = fully warm, 1.0 = fully cool
    private var bulbColour: Color {
        // Normalise colourTemp to a 0–1 scale where 1 = fully cool
        let t = 1.0 - (Double(state.colourTemp) / 255.0)
        let r = 1.0                    // Red is always full
        let g = 0.75 + 0.25 * t       // Warm = 0.75 (amber tint), cool = 1.0 (white)
        let b = 0.4 + 0.6 * t         // Warm = 0.4 (low blue), cool = 1.0 (white)
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        ZStack {
            // Radial glow — only visible when the bulb is powered on
            if state.power {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                bulbColour.opacity(0.6),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 20)
            }

            // Bulb icon — filled when on, outline when off
            // Opacity reflects the current brightness level (0–255 → 0.0–1.0)
            Image(systemName: state.power ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 100))
                .foregroundColor(
                    state.power
                    ? bulbColour.opacity(Double(state.brightness) / 255.0)
                    : .gray
                )
        }
        // Animate smoothly between on and off states
        .animation(.easeInOut(duration: 0.3), value: state.power)
    }
}

// MARK: - Effect Button

/// A selectable button used to choose a lighting effect mode (e.g. Solid, Fade, Rainbow, Pulse)

/// Displays a system icon above a label
/// When selected, the button is highlighted with a blue tint and border; otherwise it appears with a neutral background

/// - Parameters:
///   - title: The display label shown below the icon
///   - icon: The SF Symbol name used for the button icon
///   - isSelected: Whether this effect is currently active
///   - action: The closure executed when the button is tapped
struct EffectButton: View {

    /// The display label shown beneath the icon
    let title: String

    /// The SF Symbol name for the effect icon
    let icon: String

    /// Indicates whether this effect button is currently selected
    let isSelected: Bool

    /// The action to perform when the button is tapped
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                Text(title)
                    .font(.caption)
                    .bold()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            // Highlight background and border when this effect is active
            .background(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.5))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2))
        }
    }
}
