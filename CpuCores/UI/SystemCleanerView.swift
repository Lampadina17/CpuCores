import Foundation
import SwiftUI

struct CleanerActionControl: View {
    @ObservedObject var cleaner: SystemCleanerService
    let action: CleanerAction

    private var isRunning: Bool {
        cleaner.activeAction == action
    }

    private var isDisabled: Bool {
        cleaner.activeAction != nil && !isRunning
    }

    private var title: String {
        switch action {
        case .ram:
            return CCLocalized("clean.ram.title")
        case .disk:
            return CCLocalized("clean.disk.title")
        }
    }

    private var subtitle: String {
        switch action {
        case .ram:
            return CCLocalized("clean.ram.subtitle")
        case .disk:
            return CCLocalized("clean.disk.subtitle")
        }
    }

    private var message: String? {
        switch action {
        case .ram:
            return cleaner.ramMessage
        case .disk:
            return cleaner.diskMessage
        }
    }

    private var accent: Color {
        switch action {
        case .ram:
            return Color(red: 0.08, green: 0.70, blue: 0.82)
        case .disk:
            return Color(red: 1.0, green: 0.40, blue: 0.12)
        }
    }

    private var buttonForeground: Color {
        switch action {
        case .ram:
            return Color(red: 0.03, green: 0.24, blue: 0.29)
        case .disk:
            return Color(red: 0.36, green: 0.14, blue: 0.03)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .background(Color.white.opacity(0.10))

            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if isRunning {
                    cleaner.cancel()
                } else {
                    start()
                }
            } label: {
                HStack(spacing: 9) {
                    if isRunning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: buttonForeground))
                            .scaleEffect(0.78)
                        Text(CCLocalized("action.cancel").uppercased(with: Locale.current))
                    } else {
                        Image(systemName: "sparkles")
                        Text(title.uppercased(with: Locale.current))
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(buttonForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        accent
                        Color.white.opacity(0.68)
                    }
                    .opacity(isDisabled ? 0.34 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDisabled)
            .accessibilityLabel(
                isRunning ? CCFormatted("accessibility.cancel_format", title) : title
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isDisabled ? 0.58 : 1)
        .animation(.easeOut(duration: 0.2), value: isDisabled)
    }

    private func start() {
        switch action {
        case .ram:
            cleaner.cleanRAM()
        case .disk:
            cleaner.cleanDisk()
        }
    }
}

struct CleanerDisclaimer: View {
    var body: some View {
        Text(CCLocalized("clean.disclaimer"))
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.54))
            .padding(.horizontal, 4)
    }
}
