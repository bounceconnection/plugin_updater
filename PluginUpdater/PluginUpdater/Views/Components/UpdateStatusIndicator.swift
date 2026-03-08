import SwiftUI

/// Visual indicator for a plugin's update status.
enum UpdateStatus {
    case upToDate
    case updateAvailable
    case unknown

    var color: Color {
        switch self {
        case .upToDate: .green
        case .updateAvailable: .orange
        case .unknown: .secondary
        }
    }

    var icon: String {
        switch self {
        case .upToDate: "checkmark.circle.fill"
        case .updateAvailable: "arrow.up.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .upToDate: "Up to date"
        case .updateAvailable: "Update available"
        case .unknown: "Unknown"
        }
    }
}

struct UpdateStatusIndicator: View {
    let status: UpdateStatus

    init(installedVersion: String, latestVersion: String?) {
        if let latest = latestVersion {
            self.status = latest.isNewerVersion(than: installedVersion) ? .updateAvailable : .upToDate
        } else {
            self.status = .unknown
        }
    }

    init(status: UpdateStatus) {
        self.status = status
    }

    var body: some View {
        Label(status.label, systemImage: status.icon)
            .foregroundStyle(status.color)
            .font(.caption)
    }
}
