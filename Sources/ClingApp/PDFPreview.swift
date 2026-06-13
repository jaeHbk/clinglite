import SwiftUI
import PDFKit

/// SwiftUI wrapper over PDFKit's PDFView so the preview pane can SCROLL through a multi-page
/// PDF (vertical, single-page-continuous). Reloads the document only when the path changes,
/// so re-selecting the same row (or the panel's focus-tick re-render) doesn't reset scroll.
struct PDFPreview: NSViewRepresentable {
    /// Real on-disk path (already resolved via FilePreviewInfo.realPath).
    let path: String

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        loadIfNeeded(view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        loadIfNeeded(view, context: context)
    }

    private func loadIfNeeded(_ view: PDFView, context: Context) {
        guard context.coordinator.loadedPath != path else { return }
        context.coordinator.loadedPath = path
        // PDFDocument loads pages lazily; safe for large PDFs. Defaults to the top of page 1.
        view.document = PDFDocument(url: URL(fileURLWithPath: path))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loadedPath: String = "" }
}
