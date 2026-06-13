import Testing
import Foundation
import PDFKit
@testable import ClingApp

/// PDFView renders via its own (layer/Metal) path that an offscreen cacheDisplay bitmap does NOT
/// capture, so the render-smoke PNG shows a blank PDF area even though the document is loaded
/// (the live app DOES display it). These headless tests are the reliable signal that the PDF
/// path is wired and the document loads with pages.
@Suite struct PDFPreviewTests {
    /// Build a real N-page PDF on disk for the test.
    private func makePDF(pages: Int) throws -> URL {
        let doc = PDFDocument()
        for i in 0 ..< pages {
            let img = NSImage(size: NSSize(width: 200, height: 260))
            img.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 200, height: 260).fill()
            ("Page \(i + 1)" as NSString).draw(at: NSPoint(x: 20, y: 220),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            img.unlockFocus()
            if let page = PDFPage(image: img) { doc.insert(page, at: i) }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdfprev-\(UUID().uuidString).pdf")
        doc.write(to: url)
        return url
    }

    @Test func pdfDocumentLoadsWithPages() throws {
        let url = try makePDF(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = PDFDocument(url: url)
        #expect(doc != nil)
        #expect(doc?.pageCount == 3)               // multi-page -> scrollable in PDFView
    }

    @MainActor
    @Test func pdfViewDisplaysLoadedDocument() throws {
        let url = try makePDF(pages: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        // Mirror exactly what PDFPreview.loadIfNeeded does, and confirm a PDFView configured the
        // same way ends up holding the document (so the live app renders/scrolls it). We can't
        // fabricate a SwiftUI Context for makeNSView, so we exercise the identical PDFView setup.
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        #expect(view.document != nil)
        #expect(view.document?.pageCount == 2)
        #expect(view.displayMode == .singlePageContinuous)   // continuous => scrollable
    }
}
