import AppKit
import Combine
import Foundation

final class BrowserWindowManager: ObservableObject {
    private final class WeakBrowserViewModel {
        weak var value: BrowserViewModel?

        init(_ value: BrowserViewModel) {
            self.value = value
        }
    }

    static let shared = BrowserWindowManager()

    @Published private(set) var activeBrowserWindowNumber: Int?

    private var viewModelsByWindowNumber: [Int: WeakBrowserViewModel] = [:]
    private var notificationObservers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        let observedNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSApplication.didBecomeActiveNotification
        ]

        notificationObservers = observedNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshActiveWindow()
            }
        }
    }

    deinit {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
    }

    func register(windowNumber: Int, viewModel: BrowserViewModel) {
        viewModelsByWindowNumber[windowNumber] = WeakBrowserViewModel(viewModel)
        refreshActiveWindow()
    }

    func unregister(windowNumber: Int) {
        viewModelsByWindowNumber[windowNumber] = nil
        refreshActiveWindow()
    }

    func frontmostBrowserViewModel() -> BrowserViewModel? {
        cleanupReleasedViewModels()

        let candidates = [
            NSApp.keyWindow?.windowNumber,
            NSApp.mainWindow?.windowNumber,
            activeBrowserWindowNumber
        ]

        for case let windowNumber? in candidates {
            if let viewModel = viewModelsByWindowNumber[windowNumber]?.value {
                return viewModel
            }
        }

        return viewModelsByWindowNumber.values.compactMap(\.value).first
    }

    func openURLInFrontmostWindow(_ urlString: String) {
        guard let viewModel = frontmostBrowserViewModel() else { return }
        viewModel.loadSelectedTab(from: urlString)
        viewModel.focusActiveWebViewIfPossible()
    }

    private func refreshActiveWindow() {
        cleanupReleasedViewModels()

        if let keyWindowNumber = NSApp.keyWindow?.windowNumber,
           viewModelsByWindowNumber[keyWindowNumber]?.value != nil {
            activeBrowserWindowNumber = keyWindowNumber
            return
        }

        if let mainWindowNumber = NSApp.mainWindow?.windowNumber,
           viewModelsByWindowNumber[mainWindowNumber]?.value != nil {
            activeBrowserWindowNumber = mainWindowNumber
            return
        }

        activeBrowserWindowNumber = viewModelsByWindowNumber.keys.sorted().last
    }

    private func cleanupReleasedViewModels() {
        viewModelsByWindowNumber = viewModelsByWindowNumber.filter { _, weakViewModel in
            weakViewModel.value != nil
        }
    }
}
