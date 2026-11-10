import AppKit

enum Kind { case line(prefix: String), paragraph, list(tag: String, depth: Int) }
enum Protected { case code(String), literal(String) }
struct Block { var kind: Kind; var text: String }
struct Style: Equatable { var bold = false, italic = false, mono = false, link: String? }

struct Document {
    var blocks: [Block] = []
    var protected: [Protected] = []
    var baseFont: NSFont?

    mutating func protect(_ value: Protected) -> String {
        protected.append(value)
        return "⟦\(protected.count - 1)⟧"
    }

    subscript(token: Substring) -> Protected { protected[Int(token)!] }
}

let bulletFormats: Set<NSTextList.MarkerFormat> = [.disc, .circle, .square, .hyphen, .box, .check, .diamond]

func richDocument(_ source: NSAttributedString) -> Document {
    var doc = Document()
    if let font = source.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
        doc.baseFont = NSFontManager.shared.convert(font, toNotHaveTrait: [.boldFontMask, .italicFontMask])
    }
    let string = source.string as NSString
    string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
        var range = range
        var kind = Kind.paragraph
        if range.length > 0,
           let lists = (source.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.textLists,
           let list = lists.last {
            kind = .list(tag: bulletFormats.contains(list.markerFormat) ? "ul" : "ol", depth: lists.count)
            if let marker = string.substring(with: range).prefixMatch(of: #/\t?[^\t]{0,10}\t/#) {
                let skip = marker.output.utf16.count
                range = NSRange(location: range.location + skip, length: range.length - skip)
            }
        }
        doc.blocks.append(Block(kind: kind, text: inlineMarkdown(source.attributedSubstring(from: range), &doc)))
    }
    return doc
}

func inlineMarkdown(_ source: NSAttributedString, _ doc: inout Document) -> String {
    var runs: [(style: Style, text: String)] = []
    source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
        let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
        let style = Style(bold: traits.contains(.bold), italic: traits.contains(.italic), mono: traits.contains(.monoSpace), link: link)
        let text = (source.string as NSString).substring(with: range)
        if runs.last?.style == style { runs[runs.count - 1].text += text } else { runs.append((style, text)) }
    }
    return runs.map { run in
        if run.style.mono, run.style.link == nil { return doc.protect(.code(run.text)) }
        let text = run.text.replacing(#/https?:\/\/[^\s)\]>]+|\*/#) { doc.protect(.literal(String($0.output))) }
        let core = text.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return text }
        let lead = String(text.prefix { $0.isWhitespace })
        let trail = String(text.reversed().prefix { $0.isWhitespace }.reversed())
        let marker = (run.style.bold ? "**" : "") + (run.style.italic ? "*" : "")
        var markdown = marker + core + marker
        if let link = run.style.link { markdown = "[\(markdown)](\(doc.protect(.literal(link))))" }
        return lead + markdown + trail
    }.joined()
}

func hasUnsupportedContent(_ source: NSAttributedString) -> Bool {
    var found = false
    source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, _, stop in
        let table = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.contains { $0 is NSTextTableBlock } ?? false
        if attributes[.attachment] != nil || table { found = true; stop.pointee = true }
    }
    return found
}

func plainDocument(_ text: String) -> Document {
    var doc = Document()
    for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        let prefixEnd = line.prefixMatch(of: #/\s*(?:[-*+•]\s+|\d+[.)]\s+|>\s*|#{1,6}\s+)?/#)?.range.upperBound ?? line.startIndex
        let body = line[prefixEnd...].replacing(#/`[^`]*`|https?:\/\/[^\s)\]>]+/#) { doc.protect(.literal(String($0.output))) }
        doc.blocks.append(Block(kind: .line(prefix: String(line[..<prefixEnd])), text: String(body)))
    }
    return doc
}

func signature(_ text: String) -> [String] {
    let tokens = text.matches(of: #/⟦\d+⟧|\]\(/#).map { String($0.output) }.sorted()
    let withoutBold = text.replacingOccurrences(of: "**", with: "")
    return tokens + ["**\((text.count - withoutBold.count) / 2)", "*\(withoutBold.filter { $0 == "*" }.count)"]
}

func escape(_ text: some StringProtocol) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

func inlineHTML(_ text: String, _ doc: Document) -> String {
    escape(text)
        .replacing(#/\*\*(.+?)\*\*/#) { "<b>\($0.1)</b>" }
        .replacing(#/\*(.+?)\*/#) { "<i>\($0.1)</i>" }
        .replacing(#/\[([^\]]*)\]\(⟦(\d+)⟧\)/#) { match in
            guard case .literal(let url) = doc[match.2] else { return String(match.1) }
            return "<a href=\"\(escape(url))\">\(match.1)</a>"
        }
        .replacing(#/⟦(\d+)⟧/#) { match in
            switch doc[match.1] {
            case .code(let code): "<code>\(escape(code))</code>"
            case .literal(let text): escape(text)
            }
        }
}

func html(_ doc: Document) -> String {
    var html = "<meta charset=\"utf-8\">"
    var open: [String] = []
    for block in doc.blocks {
        let inline = inlineHTML(block.text, doc)
        if case .list(let tag, let depth) = block.kind {
            while open.count > depth || (open.count == depth && open.last != tag) { html += "</li></\(open.removeLast())>" }
            if open.count == depth { html += "</li>" }
            while open.count < depth { html += "<\(tag)>"; open.append(tag) }
            html += "<li>\(inline)"
        } else {
            while let tag = open.popLast() { html += "</li></\(tag)>" }
            html += "<div>\(inline.isEmpty ? "<br>" : inline)</div>"
        }
    }
    while let tag = open.popLast() { html += "</li></\(tag)>" }
    return html
}

func plainText(_ doc: Document) -> String {
    doc.blocks.map { block in
        guard case .line(let prefix) = block.kind else { return block.text }
        return prefix + block.text.replacing(#/⟦(\d+)⟧/#) { match in
            guard case .literal(let text) = doc[match.1] else { return "" }
            return text
        }
    }.joined(separator: "\n")
}

func rebase(_ text: NSMutableAttributedString, _ base: NSFont) {
    let manager = NSFontManager.shared
    text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
        guard let font = value as? NSFont, !font.fontDescriptor.symbolicTraits.contains(.monoSpace) else { return }
        text.addAttribute(.font, value: manager.convert(base, toHaveTrait: manager.traits(of: font).intersection([.boldFontMask, .italicFontMask])), range: range)
    }
}
