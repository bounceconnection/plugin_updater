import SwiftUI

struct VersionHistoryView: View {
    let versions: [PluginVersion]

    private var sortedVersions: [PluginVersion] {
        versions.sorted { $0.detectedDate > $1.detectedDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version History")
                .font(.headline)

            if sortedVersions.isEmpty {
                Text("No version changes recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedVersions) { version in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.version)
                                .font(.body.monospaced())
                            if let prev = version.previousVersion {
                                Text("from \(prev)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(version.detectedDate.formatted(.dateTime.month().day().year()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if version.id != sortedVersions.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}
