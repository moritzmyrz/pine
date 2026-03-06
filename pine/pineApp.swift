//
//  pineApp.swift
//  pine
//
//  Created by Moritz André Myrseth on 2026-03-05.
//

import AppKit
import SwiftUI

@main
struct pineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var libraryNavigation = LibraryNavigationState.shared

    var body: some Scene {
        WindowGroup(id: "browser-window") {
            BrowserRootView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openLibrary(.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    openWindow(id: "browser-window")
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("New Tab") {
                    postWindowCommand(.pineNewTab)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Private Tab") {
                    postWindowCommand(.pineNewPrivateTab)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Close Tab") {
                    postWindowCommand(.pineCloseTab)
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Reload") {
                    postWindowCommand(.pineReload)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Back") {
                    postWindowCommand(.pineGoBack)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    postWindowCommand(.pineGoForward)
                }
                .keyboardShortcut("]", modifiers: .command)
            }

            CommandMenu("History") {
                Button("Show History") {
                    openLibrary(.history)
                }
                .keyboardShortcut("y", modifiers: .command)
            }

            CommandMenu("Bookmarks") {
                Button("Bookmark Current Tab") {
                    postWindowCommand(.pineToggleBookmarkForCurrentTab)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Toggle Bookmark Bar") {
                    postWindowCommand(.pineToggleBookmarksBar)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button("Show Bookmarks") {
                    openLibrary(.bookmarks)
                }
            }

            CommandMenu("Downloads") {
                Button("Show Downloads") {
                    openLibrary(.downloads)
                }
            }

            CommandMenu("Tabs") {
                Button("Tabs Overview") {
                    postWindowCommand(.pineShowTabSearch)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Reopen Closed Tab") {
                    postWindowCommand(.pineReopenClosedTab)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Previous Tab") {
                    postWindowCommand(.pineCycleTabsBackward)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Tab") {
                    postWindowCommand(.pineCycleTabsForward)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                ForEach(1...9, id: \.self) { index in
                    Button("Select Tab \(index)") {
                        postWindowCommand(.pineSelectTabAtIndex, userInfo: ["index": index])
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }

            CommandMenu("Reading") {
                Button("Zoom In") {
                    postWindowCommand(.pineZoomIn)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    postWindowCommand(.pineZoomOut)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    postWindowCommand(.pineZoomReset)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Toggle Reader Mode (Lite)") {
                    postWindowCommand(.pineToggleReaderMode)
                }
            }

            CommandMenu("Page") {
                Button("View Source") {
                    postWindowCommand(.pineViewSource)
                }
                .keyboardShortcut("u", modifiers: [.command, .option])

                Button("Open Current Page in Safari") {
                    postWindowCommand(.pineOpenCurrentPageInSafari)
                }
                .keyboardShortcut("o", modifiers: [.command, .option])

                Button("Copy Clean Link") {
                    postWindowCommand(.pineCopyCleanLink)
                }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            }

            CommandMenu("View") {
                Button("Toggle Zen Mode") {
                    postWindowCommand(.pineToggleZenMode)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Split View") {
                    postWindowCommand(.pineToggleSplitView)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Focus Left Pane") {
                    postWindowCommand(.pineSwitchActivePaneLeft)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button("Focus Right Pane") {
                    postWindowCommand(.pineSwitchActivePaneRight)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button("Swap Split Panes") {
                    postWindowCommand(.pineSwapSplitPanes)
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])

                Button("Reset Split Divider") {
                    postWindowCommand(.pineResetSplitDivider)
                }

                Button("Flip Split Orientation") {}
                    .disabled(true)
            }
        }

        Window("Pine Library", id: "pine-library") {
            PineLibraryRootView()
        }
    }

    private func postWindowCommand(_ name: Notification.Name, userInfo: [String: Any] = [:]) {
        guard let windowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber else { return }
        var payload = userInfo
        payload[AppCommandUserInfoKey.windowNumber] = windowNumber
        NotificationCenter.default.post(name: name, object: nil, userInfo: payload)
    }

    private func openLibrary(_ section: LibrarySection) {
        libraryNavigation.open(section)
        openWindow(id: "pine-library")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
