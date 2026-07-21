import Foundation

/// The sidebar tree (`TableListView`) has no direct reference to the
/// session's `SQLConsoleViewModel` — `MainWindowView` owns both and hands
/// this bridge to the sidebar instead: a double-click writes here, and
/// `MainWindowView`'s own `.onChange` forwards it into the console's
/// `pendingQueryInsertion`/`pendingQueryAppend`.
@MainActor
final class SQLInsertionBridge: ObservableObject {
    @Published var pendingText: String?
    /// A full statement template (from the sidebar's "SQL Sorgu Ekle"
    /// context menu) to be *appended* after the editor's existing content —
    /// unlike `pendingText`, which inserts at the cursor.
    @Published var pendingAppend: String?
    /// One-shot flag from the sidebar's "İnfo" context-menu action: the
    /// active grid should load and show its table's text info report.
    @Published var pendingShowInfo = false
}
