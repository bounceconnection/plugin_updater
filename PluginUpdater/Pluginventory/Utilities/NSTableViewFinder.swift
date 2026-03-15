import AppKit
import SwiftUI

/// Invisible NSViewRepresentable that introspects the backing NSTableView
/// of a SwiftUI Table, enabling double-click-to-auto-size on column dividers.
struct NSTableViewFinder: NSViewRepresentable {
    var configure: (NSTableView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let contentView = view.window?.contentView else { return }
            if let tableView = Self.findTableView(in: contentView) {
                configure(tableView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView {
            return tableView
        }
        for subview in view.subviews {
            if let found = findTableView(in: subview) {
                return found
            }
        }
        return nil
    }

    static func enableColumnAutoResize() -> some View {
        NSTableViewFinder { tableView in
            tableView.columnAutoresizingStyle = .noColumnAutoresizing
            for column in tableView.tableColumns {
                column.resizingMask = .userResizingMask
                column.maxWidth = 500
            }
        }
        .frame(width: 0, height: 0)
    }
}
