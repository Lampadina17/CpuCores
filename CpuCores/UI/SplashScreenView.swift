import SwiftUI

struct AppRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            ContentView()
                .scaleEffect(isShowingSplash && !reduceMotion ? 1.015 : 1)

            if isShowingSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            let delay = reduceMotion ? 0.55 : 1.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if reduceMotion {
                    isShowingSplash = false
                } else {
                    withAnimation(.easeInOut(duration: 0.42)) {
                        isShowingSplash = false
                    }
                }
            }
        }
    }
}

private struct SplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let shortestSide = min(proxy.size.width, proxy.size.height)
            let markSize = min(max(shortestSide * 0.25, 104), 148)

            ZStack {
                SystemBackground()

                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.24, green: 0.84, blue: 1.0).opacity(0.16),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: shortestSide * 0.58
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    SplashLogoMark(size: markSize, isAnimating: isAnimating && !reduceMotion)
                        .scaleEffect(isAnimating || reduceMotion ? 1 : 0.86)
                        .opacity(isAnimating || reduceMotion ? 1 : 0)

                    VStack(spacing: 7) {
                        Text(CCLocalized("app.title"))
                            .font(.system(size: min(max(shortestSide * 0.068, 27), 39), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(1.2)

                        Text(CCLocalized("dashboard.subtitle"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.66))
                    }
                    .opacity(isAnimating || reduceMotion ? 1 : 0)
                    .offset(y: isAnimating || reduceMotion ? 0 : 8)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.72)))
                        .scaleEffect(0.82)
                        .opacity(isAnimating || reduceMotion ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            guard !reduceMotion else {
                isAnimating = true
                return
            }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                isAnimating = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SplashLogoMark: View {
    let size: CGFloat
    let isAnimating: Bool

    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(red: 0.24, green: 0.84, blue: 1.0).opacity(0.28), lineWidth: 2)
                .frame(width: size * 0.92, height: size * 0.92)
                .scaleEffect(isAnimating ? 1.38 : 0.82)
                .opacity(isAnimating ? 0 : 0.72)
                .animation(
                    .easeOut(duration: 1.35).repeatForever(autoreverses: false),
                    value: isAnimating
                )

            shape
                .fill(Color.white.opacity(0.10))
                .overlay(
                    shape.stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 16, x: 0, y: 8)

            Image(systemName: "cpu")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(.white)

            coreDot(color: Color(red: 0.24, green: 0.84, blue: 1.0), x: -0.31, y: -0.31)
            coreDot(color: Color(red: 0.78, green: 0.48, blue: 1.0), x: 0.31, y: -0.31)
            coreDot(color: Color(red: 0.29, green: 0.95, blue: 0.67), x: -0.31, y: 0.31)
            coreDot(color: Color(red: 1.0, green: 0.64, blue: 0.30), x: 0.31, y: 0.31)
        }
        .frame(width: size, height: size)
    }

    private func coreDot(color: Color, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().fill(Color.white.opacity(0.58)))
            .frame(width: size * 0.085, height: size * 0.085)
            .offset(x: size * x, y: size * y)
            .shadow(color: color.opacity(0.34), radius: 5)
    }
}
