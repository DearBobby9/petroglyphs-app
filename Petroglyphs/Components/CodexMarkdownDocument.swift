import Foundation

/// Foundation's CommonMark parser supplies block structure and inline attributes.
/// Intent identities remain stable when a streaming reply appends more blocks.
struct CodexMarkdownDocument {
    let source: String
    let blocks: [CodexMarkdownBlock]

    init(_ source: String) {
        InteractionDiagnostics.shared.record(.markdownParseBegin)
        defer { InteractionDiagnostics.shared.record(.markdownParseEnd) }
        self.source = source
        guard let parsed = try? AttributedString(markdown: source) else {
            blocks = [CodexMarkdownBlock(id: "0", kind: .paragraph, text: AttributedString(source))]
            return
        }
        var output: [CodexMarkdownBlock] = []
        for run in parsed.runs {
            let intents = run.presentationIntent?.components ?? []
            var fragment = AttributedString(parsed[run.range])
            fragment.presentationIntent = nil
            let table = intents.first { if case .table = $0.kind { return true }; return false }
            if let table {
                let id = String(table.identity)
                if output.last?.id != id { output.append(CodexMarkdownBlock(id: id, kind: .table, text: AttributedString())) }
                let row = intents.compactMap { intent -> Int? in
                    switch intent.kind { case .tableHeaderRow: return 0; case .tableRow(let row): return row; default: return nil }
                }.first ?? 0
                let column = intents.compactMap { intent -> Int? in
                    if case .tableCell(let column) = intent.kind { return column }; return nil
                }.first ?? 0
                let index = output.count - 1
                while output[index].rows.count <= row { output[index].rows.append([]) }
                while output[index].rows[row].count <= column { output[index].rows[row].append(AttributedString()) }
                output[index].rows[row][column].append(fragment)
                continue
            }
            let identity = intents.first?.identity ?? 0
            let id = String(identity)
            if output.last?.id == id {
                output[output.count - 1].text.append(fragment)
                continue
            }
            let kind: CodexMarkdownBlock.Kind
            switch intents.first?.kind {
            case .header(let level): kind = .heading(level)
            case .codeBlock(let language): kind = .code(language ?? "")
            case .thematicBreak: kind = .divider
            default: kind = .paragraph
            }
            let ordinal = intents.compactMap { intent -> Int? in
                if case .listItem(let ordinal) = intent.kind { return ordinal }; return nil
            }.first
            let ordered = intents.contains { if case .orderedList = $0.kind { return true }; return false }
            let listDepth = intents.filter { if case .listItem = $0.kind { return true }; return false }.count
            let quoteDepth = intents.filter { if case .blockQuote = $0.kind { return true }; return false }.count
            output.append(CodexMarkdownBlock(id: id, kind: kind, text: fragment,
                                             marker: ordinal.map { ordered ? "\($0)." : "•" },
                                             listDepth: listDepth, quoteDepth: quoteDepth))
        }
        blocks = output
    }
}

struct CodexMarkdownBlock: Identifiable {
    enum Kind: Equatable { case paragraph, heading(Int), code(String), table, divider }
    let id: String
    let kind: Kind
    var text: AttributedString
    var marker: String? = nil
    var listDepth = 0
    var quoteDepth = 0
    var rows: [[AttributedString]] = []
}
