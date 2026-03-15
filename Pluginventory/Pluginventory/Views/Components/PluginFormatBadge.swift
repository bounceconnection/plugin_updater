import SwiftUI

struct PluginFormatBadge: View {
    let format: PluginFormat

    private var color: Color {
        switch format {
        case .au: .purple
        case .clap: .orange
        case .vst2: .teal
        case .vst3: .blue
        }
    }

    var body: some View {
        Text(format.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}
