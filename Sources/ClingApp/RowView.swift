import SwiftUI

/// One result row: icon, basename with highlighted matched chars, dimmed parent dir.
struct RowView: View {
    let row: RowModel
    let selected: Bool

    /// Build an AttributedString bolding the highlighted byte ranges of the name.
    private var styledName: AttributedString {
        var s = AttributedString(row.name)
        let bytes = Array(row.name.utf8)
        for r in row.highlight {
            guard r.lowerBound >= 0, r.upperBound <= bytes.count else { continue }
            // Map UTF-8 byte offsets to String indices via prefix decoding.
            let lo = String(decoding: bytes[0 ..< r.lowerBound], as: UTF8.self).count
            let hi = String(decoding: bytes[0 ..< r.upperBound], as: UTF8.self).count
            if let lb = s.index(s.startIndex, offsetByCharacters: lo, limitedBy: s.endIndex),
               let ub = s.index(s.startIndex, offsetByCharacters: hi, limitedBy: s.endIndex),
               lb < ub {
                s[lb ..< ub].font = .system(.body, design: .default).bold()
                s[lb ..< ub].foregroundColor = .yellow
            }
        }
        return s
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.isDir ? "folder.fill" : "doc.fill")
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(styledName).foregroundStyle(selected ? .white : .primary).lineLimit(1)
                Text(row.dir).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.85) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private extension AttributedString {
    func index(_ i: AttributedString.Index, offsetByCharacters n: Int, limitedBy limit: AttributedString.Index) -> AttributedString.Index? {
        characters.index(i, offsetBy: n, limitedBy: limit)
    }
}
