import Foundation

/// One color preference with separate values per theme, stored as
/// `"#RRGGBB"` hex so it JSON-encodes cleanly.
struct AdaptiveColorSetting: Codable, Equatable {
    var light: String
    var dark: String

    /// Same value in both themes — for colors that historically didn't
    /// adapt (like the grid header).
    init(both value: String) {
        self.light = value
        self.dark = value
    }

    init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }
}

/// The whole persisted preference set. Every field has a baked-in default
/// mirroring the values that used to be hardcoded, and decoding falls back
/// field-by-field (`decodeIfPresent`) so a settings.json written by an
/// older version keeps working when new keys appear.
struct AppSettings: Codable, Equatable {
    struct General: Codable, Equatable {
        var confirmRowDeletion = true

        init() {}
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            confirmRowDeletion = try container.decodeIfPresent(Bool.self, forKey: .confirmRowDeletion) ?? true
        }
    }

    struct Grid: Codable, Equatable {
        var rowHeight: Double = 20
        var cellFontSize: Double = 12
        var headerFontSize: Double = 15
        var defaultPageSize = 1000
        var headerBackground = AdaptiveColorSetting(both: "#3c3c3c")
        var headerText = AdaptiveColorSetting(both: "#c5c5c5")
        var gridLine = AdaptiveColorSetting(light: "#c5c5c5", dark: "#484848")
        var selectedRowBackground = AdaptiveColorSetting(light: "#dcdcdc", dark: "#555555")
        var selectedRowText = AdaptiveColorSetting(light: "#221a14", dark: "#f5f0e8")

        init() {}
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Grid()
            rowHeight = try container.decodeIfPresent(Double.self, forKey: .rowHeight) ?? defaults.rowHeight
            cellFontSize = try container.decodeIfPresent(Double.self, forKey: .cellFontSize) ?? defaults.cellFontSize
            headerFontSize = try container.decodeIfPresent(Double.self, forKey: .headerFontSize) ?? defaults.headerFontSize
            defaultPageSize = try container.decodeIfPresent(Int.self, forKey: .defaultPageSize) ?? defaults.defaultPageSize
            headerBackground = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .headerBackground) ?? defaults.headerBackground
            headerText = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .headerText) ?? defaults.headerText
            gridLine = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .gridLine) ?? defaults.gridLine
            selectedRowBackground = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .selectedRowBackground) ?? defaults.selectedRowBackground
            selectedRowText = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .selectedRowText) ?? defaults.selectedRowText
        }
    }

    struct Editor: Codable, Equatable {
        var fontSize: Double = 13
        var autoUppercaseKeywords = true
        var showLineNumbers = true
        var defaultSelectLimit = 1000
        // Hex equivalents of the systemBlue/Green/Gray the editor shipped
        // with — stored as single values (syntax colors read fine on both
        // themes).
        var keywordColor = AdaptiveColorSetting(both: "#007aff")
        var stringColor = AdaptiveColorSetting(both: "#28cd41")
        var commentColor = AdaptiveColorSetting(both: "#8e8e93")
        /// The status row under the editor (hata/bilgi mesajları).
        var statusFontSize: Double = 13
        var errorColor = AdaptiveColorSetting(light: "#d70015", dark: "#ff6961")

        init() {}
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Editor()
            fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
            autoUppercaseKeywords = try container.decodeIfPresent(Bool.self, forKey: .autoUppercaseKeywords) ?? defaults.autoUppercaseKeywords
            showLineNumbers = try container.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? defaults.showLineNumbers
            defaultSelectLimit = try container.decodeIfPresent(Int.self, forKey: .defaultSelectLimit) ?? defaults.defaultSelectLimit
            keywordColor = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .keywordColor) ?? defaults.keywordColor
            stringColor = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .stringColor) ?? defaults.stringColor
            commentColor = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .commentColor) ?? defaults.commentColor
            statusFontSize = try container.decodeIfPresent(Double.self, forKey: .statusFontSize) ?? defaults.statusFontSize
            errorColor = try container.decodeIfPresent(AdaptiveColorSetting.self, forKey: .errorColor) ?? defaults.errorColor
        }
    }

    /// Sidebar schema tree (Tree view).
    struct Sidebar: Codable, Equatable {
        var fontSize: Double = 13
        /// Vertical padding per row — the "satır aralığı" knob.
        var rowVerticalPadding: Double = 4

        init() {}
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Sidebar()
            fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? defaults.fontSize
            rowVerticalPadding = try container.decodeIfPresent(Double.self, forKey: .rowVerticalPadding) ?? defaults.rowVerticalPadding
        }
    }

    var general = General()
    var grid = Grid()
    var editor = Editor()
    var sidebar = Sidebar()

    init() {}
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = try container.decodeIfPresent(General.self, forKey: .general) ?? General()
        grid = try container.decodeIfPresent(Grid.self, forKey: .grid) ?? Grid()
        editor = try container.decodeIfPresent(Editor.self, forKey: .editor) ?? Editor()
        sidebar = try container.decodeIfPresent(Sidebar.self, forKey: .sidebar) ?? Sidebar()
    }

    static let defaults = AppSettings()
}
