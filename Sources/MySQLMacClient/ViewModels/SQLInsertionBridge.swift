import Foundation

/// The sidebar tree (`TableListView`) and the SQL query panel
/// (`QueryPanelView`, inside `TableDataGridView`) live in separate branches
/// of the view hierarchy — `TableDataGridView` owns its own
/// `TableDataViewModel` privately, so the sidebar has no direct reference
/// to insert into. `MainWindowView` owns one of these and hands it to both
/// sides instead: a double-click writes here, the active grid's `.onChange`
/// forwards it into its view model's `pendingQueryInsertion`.
@MainActor
final class SQLInsertionBridge: ObservableObject {
    @Published var pendingText: String?
    /// A full statement template (from the sidebar's "SQL Sorgu Ekle"
    /// context menu) to be *appended* after the editor's existing content —
    /// unlike `pendingText`, which inserts at the cursor.
    @Published var pendingAppend: String?
}
