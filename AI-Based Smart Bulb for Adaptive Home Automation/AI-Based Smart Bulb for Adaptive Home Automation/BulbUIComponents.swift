import SwiftUI

// Bulb Visual
struct BulbVisualView: View {
    let state: BulbState
    
    var body: some View {
        ZStack {
            if state.power {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: Double(state.red) / 255.0, green: Double(state.green) / 255.0, blue: Double(state.blue) / 255.0).opacity(0.6),
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
                    state.power ?
                    Color(red: Double(state.red) / 255.0, green: Double(state.green) / 255.0, blue: Double(state.blue) / 255.0).opacity(Double(state.brightness) / 255.0) : .gray
                )
        }
        .animation(.easeInOut(duration: 0.3), value: state.power)
    }
}

// Quick Color Button
struct QuickColorButton: View {
    let color: Color
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

// Effect Button
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
