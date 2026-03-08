import SwiftUI

struct AvailableVersionCell: View {
    let availableVersion: String
    let hasUpdate: Bool

    var body: some View {
        if hasUpdate {
            Label(availableVersion, systemImage: "arrow.up.circle.fill")
                .monospacedDigit()
                .foregroundStyle(.green)
                .symbolRenderingMode(.multicolor)
        } else if availableVersion != "—" {
            Text(availableVersion)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }
}
