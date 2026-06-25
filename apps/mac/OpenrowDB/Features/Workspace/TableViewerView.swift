// TableViewerView.swift
import OpenrowDBCore
import SwiftUI

/// A standalone tab viewing one table's rows. A thin wrapper around the shared
/// `TableDataView`, which provides browsing, search, and row editing.
struct TableViewerView: View {
    let connectionID: UUID
    let table: TableRef
    /// Width of the translucent NavigationSplitView sidebar overlapping the
    /// detail's leading edge, forwarded to the data grid so its first column
    /// isn't hidden under the sidebar.
    var leadingInset: CGFloat = 0

    var body: some View {
        TableDataView(connectionID: connectionID, table: table, leadingInset: leadingInset)
    }
}
