import SwiftUI
import AppKit

/// Right-hand preview pane for the selected result: thumbnail + name + metadata.
/// Fixed to the content height and clipped so it never overflows the panel.
struct PreviewView: View {
    let row: RowModel?
    let height: CGFloat
    @State private var image: NSImage?
    @State private var info: FilePreviewInfo?
    @State private var loadedPath: String = ""

    var body: some View {
        VStack(spacing: 10) {
            if let row {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: row.isDir ? "folder.fill" : "doc.fill")
                            .resizable().aspectRatio(contentMode: .fit)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 150, maxHeight: 150)
                .frame(maxWidth: .infinity)   // center horizontally

                Text(row.name).font(.subheadline).bold()
                    .multilineTextAlignment(.center).lineLimit(2)

                if let info {
                    VStack(alignment: .leading, spacing: 5) {
                        metaRow("Kind", info.kind)
                        metaRow("Size", info.sizeText)
                        metaRow("Modified", info.modifiedText)
                        metaRow("Where", info.realPath)
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
            Text(label).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(value).foregroundStyle(.primary).textSelection(.enabled)
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
