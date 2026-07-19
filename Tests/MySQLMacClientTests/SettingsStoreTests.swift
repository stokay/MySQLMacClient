import XCTest
@testable import MySQLMacClient

/// Pure persistence/formatting tests — no database needed. Each test uses
/// its own temp file URL, never the real settings.json or the shared
/// singleton.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private var tempFileURL: URL!

    override func setUp() {
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
    }

    func testFreshStoreStartsWithDefaults() {
        let store = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(store.settings, .defaults)
        XCTAssertEqual(store.settings.grid.rowHeight, 20)
        XCTAssertEqual(store.settings.grid.defaultPageSize, 1000)
        XCTAssertTrue(store.settings.editor.autoUppercaseKeywords)
        XCTAssertTrue(store.settings.general.confirmRowDeletion)
        XCTAssertEqual(store.settings.sidebar.fontSize, 13)
        XCTAssertEqual(store.settings.sidebar.rowVerticalPadding, 4)
        XCTAssertEqual(store.settings.editor.statusFontSize, 13)
        XCTAssertEqual(store.settings.info.fontSize, 12)
    }

    func testInfoSettingsPersist() {
        let store = SettingsStore(fileURL: tempFileURL)
        store.settings.info.fontSize = 14
        store.settings.info.textColor.dark = "#ffffff"

        let reloaded = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(reloaded.settings.info.fontSize, 14)
        XCTAssertEqual(reloaded.settings.info.textColor.dark, "#ffffff")
    }

    func testSidebarAndStatusSettingsPersist() {
        let store = SettingsStore(fileURL: tempFileURL)
        store.settings.sidebar.fontSize = 16
        store.settings.sidebar.rowVerticalPadding = 8
        store.settings.editor.statusFontSize = 15
        store.settings.editor.errorColor.light = "#aa0000"

        let reloaded = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(reloaded.settings.sidebar.fontSize, 16)
        XCTAssertEqual(reloaded.settings.sidebar.rowVerticalPadding, 8)
        XCTAssertEqual(reloaded.settings.editor.statusFontSize, 15)
        XCTAssertEqual(reloaded.settings.editor.errorColor.light, "#aa0000")
    }

    func testChangesPersistAcrossStoreInstances() {
        let store = SettingsStore(fileURL: tempFileURL)
        store.settings.grid.rowHeight = 28
        store.settings.editor.autoUppercaseKeywords = false
        store.settings.grid.selectedRowBackground.dark = "#123456"

        let reloaded = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(reloaded.settings.grid.rowHeight, 28)
        XCTAssertFalse(reloaded.settings.editor.autoUppercaseKeywords)
        XCTAssertEqual(reloaded.settings.grid.selectedRowBackground.dark, "#123456")
    }

    func testMissingKeysFallBackToDefaults() throws {
        // An old settings.json knowing only one nested field.
        try Data(#"{"grid": {"rowHeight": 30}}"#.utf8).write(to: tempFileURL)

        let store = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(store.settings.grid.rowHeight, 30)
        XCTAssertEqual(store.settings.grid.cellFontSize, 12, "eksik alan varsayılana düşmeli")
        XCTAssertEqual(store.settings.editor.fontSize, 13, "eksik bölüm varsayılana düşmeli")
    }

    func testCorruptFileFallsBackToDefaults() throws {
        try Data("bozuk { json".utf8).write(to: tempFileURL)
        let store = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(store.settings, .defaults)
    }

    func testResetToDefaultsPersists() {
        let store = SettingsStore(fileURL: tempFileURL)
        store.settings.editor.fontSize = 18
        store.resetToDefaults()

        XCTAssertEqual(store.settings, .defaults)
        let reloaded = SettingsStore(fileURL: tempFileURL)
        XCTAssertEqual(reloaded.settings, .defaults)
    }

    func testHexRoundTrip() {
        let color = NSColor(hexString: "#3c8a2f")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.hexString, "#3c8a2f")
    }

    func testInvalidHexReturnsNil() {
        XCTAssertNil(NSColor(hexString: "3c8a2f"))
        XCTAssertNil(NSColor(hexString: "#zzzzzz"))
        XCTAssertNil(NSColor(hexString: "#fff"))
        XCTAssertNil(NSColor(hexString: ""))
    }
}
