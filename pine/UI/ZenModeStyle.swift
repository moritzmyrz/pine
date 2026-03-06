import Foundation

struct ZenModeStyle {
    let isZenModeEnabled: Bool
    let hideToolbarInZenMode: Bool

    var shouldHideToolbar: Bool {
        isZenModeEnabled && hideToolbarInZenMode
    }

    var shouldHideTabStrip: Bool {
        isZenModeEnabled
    }

    var shouldHideBookmarksBar: Bool {
        isZenModeEnabled
    }

    var shouldHideDownloadsShelf: Bool {
        isZenModeEnabled
    }
}
