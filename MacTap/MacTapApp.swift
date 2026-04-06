// MacTapApp.swift
// MacTap — Slap your Mac, it talks back.

import SwiftUI
import AppKit

@main
struct MacTapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (opened via menu bar)
        Settings {
            EmptyView()
        }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var detector: ImpactDetector?
    var audioEngine: AudioEngine?
    var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock — pure menu bar app
        NSApp.setActivationPolicy(.accessory)

        audioEngine = AudioEngine.shared
        detector = ImpactDetector.shared

        setupMenuBar()
        detector?.start()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "MacTap")
            button.imagePosition = .imageLeft
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Update menu bar icon with combo count
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarTitle(_:)),
            name: .comboUpdated,
            object: nil
        )
    }

    @objc func togglePopover() {
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        if popover == nil {
            let p = NSPopover()
            p.contentSize = NSSize(width: 340, height: 480)
            p.behavior = .transient
            p.animates = true
            p.contentViewController = NSHostingController(
                rootView: MenuBarView()
                    .environmentObject(AppSettings.shared)
                    .environmentObject(ImpactDetector.shared)
            )
            popover = p
        }
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc func updateMenuBarTitle(_ notification: Notification) {
        guard AppSettings.shared.showComboInMenuBar else {
            statusItem?.button?.title = ""
            return
        }
        let combo = ImpactDetector.shared.comboCount
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.title = combo > 0 ? " ×\(combo)" : ""
        }
    }
}
