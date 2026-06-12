import SwiftUI

/// The panel's content: a query field above a scrollable result list. Bound to a SearchController.
struct SearchView: View {
    @ObservedObject var controller: SearchController
    var onSubmit: () -> Void = {}
    var onReveal: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search files…", text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .onSubmit(onSubmit)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if !controller.rows.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(controller.rows.enumerated()), id: \.element.id) { idx, row in
                            RowView(row: row, selected: idx == controller.selection)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 620)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
