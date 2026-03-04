import SwiftUI

// MARK: - Bulb Visual
// Renders the strip icon tinted between warm amber and cool white
struct BulbVisualView: View {
    let state: BulbState
    
    /// Colour interpolated between warm white (amber) and cool white
    private var bulbColour: Color {
        // colourTemp: 255 = warm amber, 0 = cool white
        // t=0 at full warm, t=1 at full cool
        let t = 1.0 - (Double(state.colourTemp) / 255.0)
        let r = 1.0
        let g = 0.75 + 0.25 * t   // warm = more amber (0.75), cool = bright white (1.0)
        let b = 0.4 + 0.6 * t     // warm = low blue (0.4), cool = full white (1.0)
        return Color(red: r, green: g, blue: b)
    }
    
    var body: some View {
        ZStack {
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
            
            Image(systemName: state.power ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 100))
                .foregroundColor(
                    state.power
                    ? bulbColour.opacity(Double(state.brightness) / 255.0)
                    : .gray
                )
        }
        .animation(.easeInOut(duration: 0.3), value: state.power)
    }
}

// MARK: - Effect Button
struct EffectButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
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
            .background(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.5))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2))
        }
    }
}
