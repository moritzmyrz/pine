import Foundation

extension Notification.Name {
    static let pineNewTab = Notification.Name("pine.newTab")
    static let pineNewPrivateTab = Notification.Name("pine.newPrivateTab")
    static let pineCloseTab = Notification.Name("pine.closeTab")
    static let pineReload = Notification.Name("pine.reload")
    static let pineGoBack = Notification.Name("pine.goBack")
    static let pineGoForward = Notification.Name("pine.goForward")
    static let pineShowHistory = Notification.Name("pine.showHistory")
    static let pineShowBookmarks = Notification.Name("pine.showBookmarks")
    static let pineShowTabSearch = Notification.Name("pine.showTabSearch")
    static let pineCycleTabsBackward = Notification.Name("pine.cycleTabsBackward")
    static let pineCycleTabsForward = Notification.Name("pine.cycleTabsForward")
    static let pineSelectTabAtIndex = Notification.Name("pine.selectTabAtIndex")
    static let pineReopenClosedTab = Notification.Name("pine.reopenClosedTab")
    static let pineZoomIn = Notification.Name("pine.zoomIn")
    static let pineZoomOut = Notification.Name("pine.zoomOut")
    static let pineZoomReset = Notification.Name("pine.zoomReset")
    static let pineToggleReaderMode = Notification.Name("pine.toggleReaderMode")
    static let pineViewSource = Notification.Name("pine.viewSource")
    static let pineOpenCurrentPageInSafari = Notification.Name("pine.openCurrentPageInSafari")
    static let pineCopyCleanLink = Notification.Name("pine.copyCleanLink")
}
