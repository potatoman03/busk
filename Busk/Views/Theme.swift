import SwiftUI

enum Theme {
    static let orange = Color(red: 0.98, green: 0.42, blue: 0.12)
    static let court = LinearGradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.04), .black],
                                      startPoint: .top, endPoint: .bottom)

    static func color(for grade: Grade) -> Color {
        switch grade {
        case .good: return .green
        case .ok: return .yellow
        case .needsWork: return .red
        }
    }

    static func color(forScore score: Int) -> Color {
        score >= 85 ? .green : score >= 65 ? .yellow : .red
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    /// Scrolled content never shows through the title bar.
    func opaqueNavigationBar() -> some View {
        toolbarBackground(Color(red: 0.16, green: 0.08, blue: 0.04), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
