import SwiftUI
import UIKit

struct CodexMarkdownText: View, Equatable {
    let text: String
    let messageID: String

    var body: some View {
        let document = CodexMarkdownDocument(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(document.blocks) { block in
                blockView(block)
                    .id("\(messageID):block:\(block.id)")
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: CodexReadingBlockKey.self, value: [
                            "\(messageID):block:\(block.id)": CodexReadingBlock(messageID: messageID, frame: geometry.frame(in: .named("conversation-scroll")))
                        ])
                    })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: CodexMarkdownBlock) -> some View {
        switch block.kind {
        case .code(let language):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language.isEmpty ? "Code" : language).font(.caption)
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = String(block.text.characters)
                    }
                    .font(.caption).buttonStyle(.plain).frame(minHeight: 44)
                    .accessibilityLabel("Copy code")
                }
                .padding(.horizontal, 10)
                ScrollView(.horizontal) {
                    Text(block.text).font(.system(.callout, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled).padding(10)
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        case .table:
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(block.rows.enumerated()), id: \.offset) { rowIndex, cells in
                        GridRow(alignment: .top) {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                Text(cell).font(rowIndex == 0 ? .callout.weight(.semibold) : .callout)
                                    .textSelection(.enabled)
                                    .frame(minWidth: 100, maxWidth: 300, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(8)
                                    .background(rowIndex == 0 ? Color.sandstone : Color.cardBackground)
                                    .overlay(Rectangle().stroke(Color.charcoal.opacity(0.1), lineWidth: 0.5))
                            }
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        case .divider: Divider()
        case .heading(let level):
            Text(block.text).font(level == 1 ? .title2.weight(.bold) : (level == 2 ? .title3.weight(.semibold) : .headline))
                .textSelection(.enabled).accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph:
            HStack(alignment: .top, spacing: 8) {
                if block.quoteDepth > 0 { Rectangle().fill(Color.ochre).frame(width: 3) }
                if let marker = block.marker { Text(marker).monospacedDigit().accessibilityHidden(true) }
                Text(block.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, CGFloat(max(0, block.listDepth - 1)) * 16)
            .foregroundStyle(block.quoteDepth > 0 ? Color.charcoal.opacity(0.8) : Color.charcoal)
        }
    }
}
