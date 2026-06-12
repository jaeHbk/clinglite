import Testing
import CoreGraphics
@testable import ClingApp

@Suite struct PanelLayoutTests {
    @Test func emptyShowsOnlySearchBar() {
        #expect(PanelLayout.totalHeight(rowCount: 0) == PanelLayout.searchBarHeight)
        #expect(PanelLayout.contentHeight(rowCount: 0) == 0)
    }

    @Test func resultsGrowThePanelToFitPreview() {
        // Any number of results must grow the panel enough to show the preview pane (the bug:
        // the live window stayed at the search-bar height and clipped everything).
        let oneRow = PanelLayout.totalHeight(rowCount: 1)
        #expect(oneRow >= PanelLayout.searchBarHeight + PanelLayout.minContentHeightWithPreview)
        #expect(oneRow > PanelLayout.searchBarHeight)
    }

    @Test func heightCapsAtMaxVisibleRows() {
        let capped = PanelLayout.totalHeight(rowCount: PanelLayout.maxVisibleRows)
        let beyond = PanelLayout.totalHeight(rowCount: PanelLayout.maxVisibleRows + 50)
        #expect(beyond == capped)                       // overflow scrolls, doesn't grow the window
    }
}
