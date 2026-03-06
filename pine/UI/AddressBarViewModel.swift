import Combine
import Foundation

struct AddressBarState {
    var isEditing = false
    var isFocused = false
}

final class AddressBarViewModel: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var state = AddressBarState()

    private var activeTabID: UUID?
    private var wasActiveTabLoading = false

    func initialize(activeTab: Tab?, settings: BrowserSettings) {
        activeTabID = activeTab?.id
        wasActiveTabLoading = activeTab?.isLoading ?? false
        inputText = displayText(for: activeTab?.urlString ?? "", settings: settings, isEditing: false)
    }

    func didChangeFocus(isFocused: Bool, activeURLString: String, settings: BrowserSettings) {
        state.isFocused = isFocused
        state.isEditing = isFocused
        inputText = displayText(for: activeURLString, settings: settings, isEditing: isFocused)
    }

    func didSelectActiveTab(_ activeTab: Tab?, settings: BrowserSettings) {
        let incomingID = activeTab?.id
        guard incomingID != activeTabID else { return }

        activeTabID = incomingID
        wasActiveTabLoading = activeTab?.isLoading ?? false

        guard !state.isFocused else { return }
        inputText = displayText(for: activeTab?.urlString ?? "", settings: settings, isEditing: false)
    }

    func didUpdateActiveTab(_ activeTab: Tab?, settings: BrowserSettings) {
        let incomingID = activeTab?.id
        if incomingID != activeTabID {
            activeTabID = incomingID
            wasActiveTabLoading = activeTab?.isLoading ?? false
            return
        }

        guard let activeTab else {
            wasActiveTabLoading = false
            guard !state.isFocused else { return }
            inputText = ""
            return
        }

        let didFinishNavigation = wasActiveTabLoading && !activeTab.isLoading
        wasActiveTabLoading = activeTab.isLoading

        guard didFinishNavigation, !state.isFocused else { return }
        inputText = displayText(for: activeTab.urlString, settings: settings, isEditing: false)
    }

    func didChangeDisplaySettings(activeURLString: String, settings: BrowserSettings) {
        guard !state.isFocused else { return }
        inputText = displayText(for: activeURLString, settings: settings, isEditing: false)
    }

    private func displayText(for urlString: String, settings: BrowserSettings, isEditing: Bool) -> String {
        guard !urlString.isEmpty else { return "" }
        if isEditing || settings.alwaysShowFullURLInAddressBar {
            return urlString
        }
        return Self.simplifiedURLString(
            urlString,
            hideHTTPS: settings.hideHTTPSInAddressBar,
            hideWWW: settings.hideWWWInAddressBar
        )
    }

    private static func simplifiedURLString(_ urlString: String, hideHTTPS: Bool, hideWWW: Bool) -> String {
        guard var components = URLComponents(string: urlString) else { return urlString }

        if hideHTTPS, components.scheme?.lowercased() == "https" {
            components.scheme = nil
        }

        if hideWWW, let host = components.host, host.lowercased().hasPrefix("www.") {
            components.host = String(host.dropFirst(4))
        }

        guard var rendered = components.string else { return urlString }
        if rendered.hasPrefix("//") {
            rendered.removeFirst(2)
        }
        return rendered
    }
}
