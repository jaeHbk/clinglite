import CoreGraphics

/// Single source of truth for the search panel's geometry. BOTH the live panel and the
/// offscreen render/self-test use these numbers, so the window the user sees can never
/// diverge from what verification measures (the bug that hid the clipped result list).
public enum PanelLayout {
    public static let width: CGFloat = 720
    public static let searchBarHeight: CGFloat = 56
    public static let footerHeight: CGFloat = 28
    public static let rowHeight: CGFloat = 46
    public static let listVerticalPadding: CGFloat = 12
    public static let maxVisibleRows = 8
    public static let previewWidth: CGFloat = 300
    /// The preview pane needs room for a thumbnail + metadata; the content area is at least this
    /// tall whenever results (and thus a preview) are shown, so the preview never overflows.
    public static let minContentHeightWithPreview: CGFloat = 320

    /// Height of the content area (results list beside the preview pane) for a visible row count.
    /// Clamped to at least `minContentHeightWithPreview` so the preview fits, and capped so a long
    /// list scrolls rather than growing the window unbounded.
    public static func contentHeight(rowCount: Int) -> CGFloat {
        if rowCount == 0 { return 0 }
        let visible = min(rowCount, maxVisibleRows)
        let listHeight = CGFloat(visible) * rowHeight + listVerticalPadding
        return max(listHeight, minContentHeightWithPreview)
    }

    /// Total panel height: search bar (+ content + footer only when there are results).
    public static func totalHeight(rowCount: Int) -> CGFloat {
        if rowCount == 0 { return searchBarHeight }
        return searchBarHeight + contentHeight(rowCount: rowCount) + footerHeight
    }
}
