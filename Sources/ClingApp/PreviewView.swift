import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Right-hand preview pane for the selected result. Shows a type-appropriate preview
/// (scrollable PDF, large image, or QuickLook thumbnail) plus the four labeled fields the
/// user asked for: Name, Path, Size, Date Modified. Fixed to the content height and clipped.
struct PreviewView: View {
    let row: RowModel?
    let height: CGFloat
    @State private var image: NSImage?
    @State private var info: FilePreviewInfo?
    @State private var loadedPath: String = ""

    private enum PreviewKind { case pdf, image, other }
    private func previewKind(for info: FilePreviewInfo?) -> PreviewKind {
        guard let info, !info.isDir else { return .other }
        let url = URL(fileURLWithPath: info.realPath)
        if let t = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if t.conforms(to: .pdf) { return .pdf }
            if t.conforms(to: .image) { return .image }
        }
        let ext = (info.realPath as NSString).pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp"].contains(ext) { return .image }
        return .other
    }

    @ViewBuilder
    private func previewArea(_ row: RowModel) -> some View {
        switch previewKind(for: info) {
        case .pdf:
            PDFPreview(path: info!.realPath)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.5).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .image:
            previewImage(row)
                .frame(maxWidth: .infinity, maxHeight: 320)
        case .other:
            previewImage(row)
                .frame(maxWidth: 180, maxHeight: 180)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func previewImage(_ row: RowModel) -> some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: row.isDir ? "folder.fill" : "doc.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let row {
                previewArea(row)

                Text(row.name).font(.subheadline).bold()
                    .multilineTextAlignment(.center).lineLimit(2)

                if let info {
                    // The four fields the user asked for, clearly labeled.
                    VStack(alignment: .leading, spacing: 5) {
                        metaRow("Name", info.name)
                        metaRow("Path", info.realPath)
                        metaRow("Size", info.sizeText)
                        metaRow("Date Modified", info.modifiedText)
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("No selection").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: PanelLayout.previewWidth, height: height, alignment: .top)
        .clipped()
        .onChange(of: row?.path ?? "") { _, newPath in load(newPath) }
        .onAppear { load(row?.path ?? "") }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).foregroundStyle(.secondary).frame(width: 88, alignment: .leading)
            Text(value).foregroundStyle(.primary).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load(_ path: String) {
        guard !path.isEmpty, path != loadedPath, let row else {
            if path.isEmpty { image = nil; info = nil }
            return
        }
        loadedPath = path
        let preview = FilePreviewInfo(indexPath: path, isDir: row.isDir)
        info = preview
        image = ThumbnailLoader.shared.icon(for: preview.realPath)  // immediate icon
        ThumbnailLoader.shared.thumbnail(for: preview.realPath) { img in
            if self.loadedPath == path { self.image = img }          // upgrade to real thumbnail
        }
    }
}
