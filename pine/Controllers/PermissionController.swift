import AppKit
import Combine
import Foundation
import WebKit

final class PermissionController {
    private let store: BrowserStore
    private let sitePermissionsStore: SitePermissionsStore
    private let contentBlockerService: ContentBlockerService

    private var sitePermissionsByHost: [String: SitePermissionEntry] = [:]

    init(
        store: BrowserStore,
        sitePermissionsStore: SitePermissionsStore,
        contentBlockerService: ContentBlockerService
    ) {
        self.store = store
        self.sitePermissionsStore = sitePermissionsStore
        self.contentBlockerService = contentBlockerService
    }

    func loadInitialState() {
        store.permissionDefaults = sitePermissionsStore.loadPermissionDefaults()
        sitePermissionsByHost = sitePermissionsStore.loadSitePermissions()
        store.trackerBlockingMode = contentBlockerService.mode
    }

    func currentSiteHost() -> String? {
        guard let selectedTab = store.selectedTab else { return nil }
        return host(from: selectedTab.urlString)
    }

    func permissionValue(for type: SitePermissionType, host: String) -> SitePermissionValue {
        let normalized = normalizedHost(host)
        if let entry = sitePermissionsByHost[normalized] {
            return entry.value(for: type)
        }
        return defaultPermissionValue(for: type)
    }

    func setPermissionValue(_ value: SitePermissionValue, for type: SitePermissionType, host: String) {
        let normalized = normalizedHost(host)
        var entry = sitePermissionsByHost[normalized] ?? SitePermissionEntry.default
        entry.setValue(value, for: type)
        sitePermissionsByHost[normalized] = entry
        sitePermissionsStore.saveSitePermissions(sitePermissionsByHost)
        store.objectWillChange.send()
    }

    func setBlockPopupsByDefault(_ enabled: Bool) {
        store.permissionDefaults.blockPopupsByDefault = enabled
        sitePermissionsStore.savePermissionDefaults(store.permissionDefaults)
    }

    func setAskCameraAndMicrophoneAlways(_ enabled: Bool) {
        store.permissionDefaults.askForCameraAndMicrophoneAlways = enabled
        sitePermissionsStore.savePermissionDefaults(store.permissionDefaults)
    }

    func setTrackerBlockingMode(_ mode: TrackerBlockingMode) {
        contentBlockerService.setMode(mode)
    }

    func didReceiveTrackerModeChange(_ mode: TrackerBlockingMode) {
        store.trackerBlockingMode = mode
    }

    func shouldAllowPermissionRequest(
        type: SitePermissionType,
        host: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let host, !host.isEmpty else {
            completion(false)
            return
        }

        let resolved = permissionValue(for: type, host: host)
        if resolved == .block {
            completion(false)
            return
        }

        let shouldAlwaysAskCameraMic = store.permissionDefaults.askForCameraAndMicrophoneAlways &&
            (type == .camera || type == .microphone)
        if resolved == .allow, !shouldAlwaysAskCameraMic {
            completion(true)
            return
        }

        presentPermissionPrompt(for: type, host: host, completion: completion)
    }

    func clearWebsiteData(
        for host: String,
        selectedTabID: UUID?,
        webViewProvider: (UUID) -> WKWebView,
        completion: (() -> Void)? = nil
    ) {
        guard let selectedTabID else {
            completion?()
            return
        }
        let webView = webViewProvider(selectedTabID)
        let dataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let loweredHost = host.lowercased()
            let matchingRecords = records.filter { record in
                let displayName = record.displayName.lowercased()
                return displayName == loweredHost || displayName.contains(loweredHost) || loweredHost.contains(displayName)
            }
            dataStore.removeData(ofTypes: dataTypes, for: matchingRecords) {
                completion?()
            }
        }
    }

    private func host(from urlString: String) -> String? {
        URL(string: urlString)?.host?.lowercased()
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func defaultPermissionValue(for type: SitePermissionType) -> SitePermissionValue {
        if type == .popups, store.permissionDefaults.blockPopupsByDefault {
            return .block
        }
        return .ask
    }

    private func presentPermissionPrompt(
        for type: SitePermissionType,
        host: String,
        completion: @escaping (Bool) -> Void
    ) {
        let runPrompt = {
            let alert = NSAlert()
            alert.messageText = self.permissionPromptTitle(for: type)
            alert.informativeText = "\(host) wants to use \(type.title.lowercased())."
            alert.addButton(withTitle: "Allow Once")
            alert.addButton(withTitle: "Allow Always")
            alert.addButton(withTitle: "Block")
            alert.alertStyle = .informational

            let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
                switch response {
                case .alertFirstButtonReturn:
                    completion(true)
                case .alertSecondButtonReturn:
                    self.setPermissionValue(.allow, for: type, host: host)
                    completion(true)
                default:
                    self.setPermissionValue(.block, for: type, host: host)
                    completion(false)
                }
            }

            if let keyWindow = NSApp.keyWindow {
                alert.beginSheetModal(for: keyWindow, completionHandler: handleResponse)
            } else {
                handleResponse(alert.runModal())
            }
        }

        if Thread.isMainThread {
            runPrompt()
        } else {
            DispatchQueue.main.async(execute: runPrompt)
        }
    }

    private func permissionPromptTitle(for type: SitePermissionType) -> String {
        switch type {
        case .camera:
            return "Allow Camera Access?"
        case .microphone:
            return "Allow Microphone Access?"
        case .location:
            return "Allow Location Access?"
        case .notifications:
            return "Allow Notifications?"
        case .popups:
            return "Allow Pop-up Window?"
        }
    }
}
