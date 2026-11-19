import Foundation

/**
 * The app's own screens and notices follow the page's language (`tvos-language`), among those the
 * web app has catalogs for, as the page's own text does: its own table, else one in the same
 * language (`pt` for `pt-BR`), else British English, which every table has.
 */
enum AppLanguage {
    static func pick<Text>(_ table: [String: Text], for language: String) -> Text {
        if let exact = table[language] { return exact }
        let base = baseOf(language)
        if let same = table.first(where: { baseOf($0.key) == base }) { return same.value }
        return table["en-GB"]!
    }

    private static func baseOf(_ tag: String) -> String {
        tag.split(separator: "-").first.map { String($0).lowercased() } ?? ""
    }
}
