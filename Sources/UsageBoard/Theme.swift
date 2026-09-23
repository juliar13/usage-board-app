import SwiftUI

enum BoardTheme {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.077)
    static let surface = Color(red: 0.092, green: 0.105, blue: 0.119)
    static let border = Color.white.opacity(0.09)
    static let muted = Color(red: 0.58, green: 0.63, blue: 0.65)
    static let green = Color(red: 0.65, green: 0.88, blue: 0.54)
    static let blue = Color(red: 0.58, green: 0.75, blue: 0.98)
    static let amber = Color(red: 0.99, green: 0.72, blue: 0.38)

    static func tint(remaining: Double?, base: Color) -> Color {
        guard let remaining else { return muted }
        return remaining <= 10 ? .red : remaining <= 25 ? amber : base
    }
}

struct BoardIconButton: View {
    let title: String
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(BoardTheme.border))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
