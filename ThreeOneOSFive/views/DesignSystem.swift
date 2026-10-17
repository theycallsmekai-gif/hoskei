import SwiftUI

enum AppTheme {
    // Premium black-and-white theme
    static let accent = Color.white
    static let accentSecondary = Color(white: 0.85)
    static let accentDark = Color(white: 0.20)
    
    static let pageBackground = Color(red: 9/255, green: 9/255, blue: 11/255) // Near-black #09090B
    static let consoleBackground = Color(red: 14/255, green: 14/255, blue: 16/255)
    static let cardBackground = Color(red: 18/255, green: 18/255, blue: 20/255) // Modern dark card #121214
    static let cardBorder = Color(white: 0.28).opacity(0.4) // Subtle gray border
    
    static let gradient = LinearGradient(
        colors: [Color.white, Color(white: 0.82)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 18
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            AppTheme.cardBorder,
            lineWidth: 1
        )
        .accessibilityHidden(true)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = Color.white
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.16))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(.white)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(
            AppTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
    }
}

struct AppLogo: View {
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let uiImage = UIImage(named: "AppLogo")
                ?? UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color(white: 0.35).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}
