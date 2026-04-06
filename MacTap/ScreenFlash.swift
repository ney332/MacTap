// ScreenFlash.swift
// MacTap — Full-screen white flash that intensifies with combo

import AppKit
import SwiftUI

final class ScreenFlash {

    private static var windows: [NSWindow] = []

    static func flash(intensity: Double, combo: Int) {
        DispatchQueue.main.async {
            for screen in NSScreen.screens {
                flashScreen(screen, intensity: intensity, combo: combo)
            }
        }
    }

    private static func flashScreen(_ screen: NSScreen, intensity: Double, combo: Int) {
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.level = .screenSaver
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.alphaValue = 0

        // Colour intensifies with combo
        let flashColor: NSColor
        switch combo {
        case 0...1: flashColor = .white
        case 2...3: flashColor = NSColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        case 4...6: flashColor = NSColor(red: 1, green: 0.4, blue: 0.1, alpha: 1)
        default:    flashColor = NSColor(red: 0.8, green: 0.1, blue: 1.0, alpha: 1)
        }

        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = flashColor.cgColor
        win.contentView = view

        windows.append(win)
        win.makeKeyAndOrderFront(nil)

        // Base opacity scales with intensity + combo
        let baseOpacity = min(0.15 + intensity * 0.25 + Double(min(combo, 8)) * 0.03, 0.55)
        let duration    = min(0.08 + Double(min(combo, 8)) * 0.015, 0.22)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.05
            win.animator().alphaValue = baseOpacity
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
                windows.removeAll { $0 === win }
            })
        })
    }
}
