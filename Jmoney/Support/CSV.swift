import Foundation

/// Minimal RFC 4180 CSV encoding/decoding for the import/export feature.
///
/// Only what this app needs — no generic CSV library:
/// * quoting fields containing `"`, `,`, `\n` or `\r`;
/// * doubling embedded quotes;
/// * CRLF and LF row endings on decode (both appear in spreadsheets);
/// * optional UTF-8 BOM on encode (Excel reads UTF-8 correctly with it) and
///   skipped on decode.
///
/// Embedded newlines inside a quoted field are preserved, so multi-line
/// descriptions survive a round trip. Rows may be ragged; callers validate
/// column counts (an imported row with too few columns is reported, not
/// silently padded).
enum CSV {
    /// Encodes rows of already-formatted field strings. `includeBOM` prefixes
    /// the UTF-8 byte-order mark so Excel detects the encoding.
    static func encode(_ rows: [[String]], includeBOM: Bool = true) -> String {
        var output = includeBOM ? "\u{FEFF}" : ""
        for (index, row) in rows.enumerated() {
            if index > 0 { output.append("\r\n") }
            output.append(row.map(escape).joined(separator: ","))
        }
        return output
    }

    /// Decodes CSV text into rows. A trailing newline does not produce an empty
    /// row; a BOM is skipped.
    static func decode(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var insideQuotes = false
        var index = text.startIndex
        let bomSkipped = text.hasPrefix("\u{FEFF}") ? text.index(after: text.startIndex) : text.startIndex
        index = bomSkipped

        while index < text.endIndex {
            let character = text[index]

            if insideQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        // Escaped quote ("").
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    insideQuotes = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    insideQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r", "\r\n":
                    // A CRLF pair is a *single* Character (grapheme cluster) in
                    // Swift, so it must be matched — and consumed — as one.
                    // A lone CR also ends the row (old Macs, but free).
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                case "\n":
                    row.append(field)
                    rows.append(row)
                    field = ""
                    row = []
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }

        // A final row without a trailing newline.
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// Quotes a field only when necessary — exposed for the export/import tests,
    /// which build rows against the export header.
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
