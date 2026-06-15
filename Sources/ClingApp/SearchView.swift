import SwiftUI

/// The panel's content: a search bar on top, then (when there are results) a results list beside
/// a preview pane, then a hotkey-hint footer. Reports its desired total height to the host so the
/// panel window can resize to actually show the results (PanelLayout is the single source of truth).
struct SearchView: View {
    @ObservedObject var controller: SearchController
    /// Bumped by the panel each time it shows, to (re)focus the text field.
    var focusTick: Int = 0
    var onSubmit: () -> Void = {}
    var onReveal: () -> Void = {}
    /// Called whenever the desired panel height changes (row count changed).
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @FocusState private var queryFocused: Bool

    private var hasResults: Bool { !controller.rows.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // --- Search bar ---
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
                TextField("Search files…", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($queryFocused)
                    .onSubmit(onSubmit)
            }
            .padding(.horizontal, 16)
            .frame(height: PanelLayout.searchBarHeight)

            if hasResults {
                let contentH = PanelLayout.contentHeight(rowCount: controller.rows.count)
                Divider()
                HStack(spacing: 0) {
                    // --- Results list ---
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                // ONE identity per row (the path). Previously each row also had
                                // `.id(idx)`, giving it a second, conflicting identity — in a
                                // LazyVStack that lets recycled views keep stale content until
                                // enough re-layout flushes them (the "wrong for the first N
                                // interactions, then self-corrects" symptom). Scroll-to now targets
                                // the same identity, so there is exactly one identity scheme.
                                ForEach(Array(controller.rows.enumerated()), id: \.element.identity) { idx, row in
                                    RowView(row: row, selected: idx == controller.selection)
                                        .contentShape(Rectangle())
                                        .onTapGesture { controller.selection = idx; onSubmit() }
                                }
                            }
                            .padding(6)
                        }
                        .onChange(of: controller.selection) { _, sel in
                            guard controller.rows.indices.contains(sel) else { return }
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(controller.rows[sel].identity, anchor: .center)
                            }
                        }
                    }
                    .frame(width: PanelLayout.width - PanelLayout.previewWidth)

                    Divider()

                    // --- Preview pane (fixed to content height, clipped) ---
                    PreviewView(row: controller.selectedRow, height: contentH)
                        .background(Color.primary.opacity(0.04))
                }
                .frame(height: contentH)
                .clipped()

                Divider()
                // --- Hotkey footer ---
                HotkeyFooter()
                    .frame(height: PanelLayout.footerHeight)
            }
        }
        .frame(width: PanelLayout.width)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Resize the panel whenever the result count changes.
        .onChange(of: controller.rows.count) { _, n in
            onHeightChange(PanelLayout.totalHeight(rowCount: n))
        }
        .onAppear { onHeightChange(PanelLayout.totalHeight(rowCount: controller.rows.count)) }
        // Focus the field on first appear and whenever the panel re-shows.
        .onAppear { queryFocused = true }
        .onChange(of: focusTick) { _, _ in queryFocused = true }
    }
}

/// Footer showing the key commands, mirroring the original Cling's hotkey hints.
struct HotkeyFooter: View {
    var body: some View {
        HStack(spacing: 11) {
            hint("↩", "Open")
            hint("⌘↩", "Reveal")
            hint("⌘Y", "Quick Look")
            hint("⌘T", "Terminal")
            hint("⌘R", "Rename")
            hint("⌘C", "Copy Path")
            hint("↑↓", "Navigate")
            hint("esc", "Close")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label)
        }
    }
}
