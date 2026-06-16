// TableViewerView.swift
import OpenrowDBCore
import SwiftUI

/// A standalone tab viewing one table's rows. A thin wrapper around the shared
/// `TableDataView`, which provides browsing, search, and row editing.
struct TableViewerView: View {
    let connectionID: UUID
    let table: TableRef
    /// Leading inset for the result grid, matching the sidebar overlap so the
    /// first column doesn't render under the translucent sidebar.
    var leadingInset: CGFloat = 0

    var body: some View {
        TableDataView(connectionID: connectionID, table: table, leadingInset: leadingInset)
    }
}
