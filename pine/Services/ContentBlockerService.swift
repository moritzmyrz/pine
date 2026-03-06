import Combine
import Foundation
import WebKit

enum TrackerBlockingMode: String, CaseIterable, Identifiable {
    case off
    case basic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .basic:
            return "Basic"
        }
    }
}

final class ContentBlockerService: ObservableObject {
    @Published private(set) var mode: TrackerBlockingMode

    var onRuleListDidChange: (() -> Void)?

    private let userDefaults: UserDefaults
    private let bundle: Bundle
    private let modeKey = "pine.trackerBlocking.mode"
    private let basicRulesIdentifier = "pine.trackerBlocking.basic.v1"
    private var compiledBasicList: WKContentRuleList?

    init(userDefaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.userDefaults = userDefaults
        self.bundle = bundle

        if let stored = userDefaults.string(forKey: modeKey),
           let parsed = TrackerBlockingMode(rawValue: stored) {
            mode = parsed
        } else {
            mode = .off
        }

        if mode == .basic {
            compileBasicRulesIfNeeded()
        }
    }

    func setMode(_ mode: TrackerBlockingMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        userDefaults.set(mode.rawValue, forKey: modeKey)

        if mode == .basic {
            compileBasicRulesIfNeeded()
        } else {
            onRuleListDidChange?()
        }
    }

    func apply(to userContentController: WKUserContentController) {
        userContentController.removeAllContentRuleLists()
        guard mode == .basic, let compiledBasicList else { return }
        userContentController.add(compiledBasicList)
    }

    private func compileBasicRulesIfNeeded() {
        if compiledBasicList != nil {
            onRuleListDidChange?()
            return
        }

        let rulesURL = bundle.url(forResource: "tracker-blocking-basic", withExtension: "json")
            ?? bundle.url(forResource: "tracker-blocking-basic", withExtension: "json", subdirectory: "Resources")
        guard let rulesURL else {
            return
        }

        guard let encodedRules = try? String(contentsOf: rulesURL, encoding: .utf8) else {
            return
        }

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: basicRulesIdentifier,
            encodedContentRuleList: encodedRules
        ) { [weak self] list, _ in
            guard let self else { return }
            if let list {
                self.compiledBasicList = list
            }
            self.onRuleListDidChange?()
        }
    }
}
