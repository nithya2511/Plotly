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
                        .frame(width: 78, height: 78)
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
                path.move(to: CGPoint(x: 19, y: 57))
                path.addCurve(
                    to: CGPoint(x: 59, y: 20),
                    control1: CGPoint(x: 34, y: 58),
                    control2: CGPoint(x: 33, y: 18)
                )
            }
            .trim(from: 0, to: 0.94)
            .stroke(
                Color(.systemBlue),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )

            Circle()
                .fill(Color(.systemGreen))
                .frame(width: 19, height: 19)
                .position(x: 18, y: 58)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color(.systemRed))
                .position(x: 60, y: 18)
        }
    }
}

#Preview {
    SplashScreen()
}
