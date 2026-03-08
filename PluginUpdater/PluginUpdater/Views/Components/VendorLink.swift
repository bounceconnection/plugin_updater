import SwiftUI

/// A clickable vendor name that opens their website when a URL is available.
struct VendorLink: View {
    let vendorName: String
    let vendorURL: String?

    var body: some View {
        if let urlString = vendorURL, let url = URL(string: urlString) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(vendorName)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                }
            }
        } else {
            Text(vendorName)
        }
    }
}
