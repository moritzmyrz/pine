//
//  pineApp.swift
//  pine
//
//  Created by Moritz André Myrseth on 2026-03-05.
//

import SwiftUI

@main
struct pineApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    NotificationCenter.default.post(name: .pineNewTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Private Tab") {
                    NotificationCenter.default.post(name: .pineNewPrivateTab, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Close Tab") {
                    NotificationCenter.default.post(name: .pineCloseTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    NotificationCenter.default.post(name: .pineReload, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Back") {
                    NotificationCenter.default.post(name: .pineGoBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    NotificationCenter.default.post(name: .pineGoForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }

            CommandMenu("History") {
                Button("Show History") {
                    NotificationCenter.default.post(name: .pineShowHistory, object: nil)
                }
                .keyboardShortcut("y", modifiers: .command)
            }

            CommandMenu("Bookmarks") {
                Button("Show Bookmarks") {
                    NotificationCenter.default.post(name: .pineShowBookmarks, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }

            CommandMenu("Tabs") {
                Button("Tab Search") {
                    NotificationCenter.default.post(name: .pineShowTabSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Previous Tab") {
                    NotificationCenter.default.post(name: .pineCycleTabsBackward, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Tab") {
                    NotificationCenter.default.post(name: .pineCycleTabsForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Select Tab \(index)") {
                        NotificationCenter.default.post(
                            name: .pineSelectTabAtIndex,
                            object: nil,
                            userInfo: ["index": index]
                        )
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }
        }
    }
}
