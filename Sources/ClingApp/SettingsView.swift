import SwiftUI

/// Minimal settings: list of roots (add/remove), max results, dock-icon toggle. Hotkey display
/// is read-only here (changing it live is a Phase-C nicety); editing roots triggers a reindex.
struct SettingsView: View {
    @State var roots: [String]
    @State var maxResults: Double
    @State var showDockIcon: Bool
    var onSave: (_ roots: [String], _ maxResults: Int, _ showDockIcon: Bool) -> Void
    var onAddRoot: () -> String?   // returns a chosen directory path or nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ClingLite Settings").font(.title2).bold()

            Text("Search roots").font(.headline)
            List {
                ForEach(roots, id: \.self) { r in Text(r).font(.system(.body, design: .monospaced)) }
                    .onDelete { roots.remove(atOffsets: $0) }
            }
            .frame(height: 140)
            Button("Add Folder…") { if let p = onAddRoot() { roots.append(p) } }

            HStack {
                Text("Max results: \(Int(maxResults))")
                Slider(value: $maxResults, in: 20 ... 500, step: 10)
            }
            Toggle("Show Dock icon", isOn: $showDockIcon)

            HStack {
                Spacer()
                Button("Save") { onSave(roots, Int(maxResults), showDockIcon) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }
}
