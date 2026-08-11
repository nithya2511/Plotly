import SwiftUI

struct SplashScreen: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBlue).opacity(0.14),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.regularMaterial)
                        .frame(width: 116, height: 116)
                        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)

                    RouteSplashMark()
                        .frame(width: 88, height: 88)
                }

                VStack(spacing: 8) {
                    Text("Plotly")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("Plan the route before the day starts")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plotly loading")
    }
}

struct RouteSplashMark: View {
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 12, y: 72))
                path.addCurve(
                    to: CGPoint(x: 30, y: 47),
                    control1: CGPoint(x: 24, y: 72),
                    control2: CGPoint(x: 20, y: 47)
                )
                path.addCurve(
                    to: CGPoint(x: 54, y: 58),
                    control1: CGPoint(x: 39, y: 47),
                    control2: CGPoint(x: 42, y: 58)
                )
                path.addCurve(
                    to: CGPoint(x: 74, y: 16),
                    control1: CGPoint(x: 69, y: 58),
                    control2: CGPoint(x: 58, y: 17)
                )
            }
            .stroke(
                Color(.systemBlue),
                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color(.systemBlue).opacity(0.24), radius: 4, y: 2)

            stopDot(color: Color(.systemGreen), size: 21)
                .position(x: 12, y: 72)

            stopDot(color: Color(.systemBlue), size: 15)
                .position(x: 30, y: 47)

            stopDot(color: Color(.systemBlue), size: 15)
                .position(x: 54, y: 58)

            DestinationMarker()
                .frame(width: 31, height: 40)
                .position(x: 74, y: 17)
        }
    }

    private func stopDot(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: max(size * 0.18, 2))
            }
    }
}

private struct DestinationMarker: View {
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 15.5, y: 39))
                path.addCurve(
                    to: CGPoint(x: 3, y: 16),
                    control1: CGPoint(x: 11, y: 31),
                    control2: CGPoint(x: 3, y: 25)
                )
                path.addCurve(
                    to: CGPoint(x: 15.5, y: 3),
                    control1: CGPoint(x: 3, y: 8.8),
                    control2: CGPoint(x: 8.6, y: 3)
                )
                path.addCurve(
                    to: CGPoint(x: 28, y: 16),
                    control1: CGPoint(x: 22.4, y: 3),
                    control2: CGPoint(x: 28, y: 8.8)
                )
                path.addCurve(
                    to: CGPoint(x: 15.5, y: 39),
                    control1: CGPoint(x: 28, y: 25),
                    control2: CGPoint(x: 20, y: 31)
                )
                path.closeSubpath()
            }
            .fill(Color(.systemRed))

            Circle()
                .fill(.white)
                .frame(width: 11, height: 11)
                .position(x: 15.5, y: 16)
        }
    }
}

#Preview {
    SplashScreen()
}
