// AppSettings.swift
// MacTap — Centralized settings with UserDefaults persistence

import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var isEnabled: Bool          { didSet { save("isEnabled", isEnabled) } }
    @Published var sensitivity: Double      { didSet { save("sensitivity", sensitivity) } }
    @Published var cooldown: Double         { didSet { save("cooldown", cooldown) } }
    @Published var dynamicVolume: Bool      { didSet { save("dynamicVolume", dynamicVolume) } }
    @Published var volume: Double           { didSet { save("volume", volume) } }
    @Published var selectedPack: SoundPack  { didSet { save("selectedPack", selectedPack.rawValue) } }
    @Published var screenFlashEnabled: Bool { didSet { save("screenFlash", screenFlashEnabled) } }
    @Published var comboEnabled: Bool       { didSet { save("comboEnabled", comboEnabled) } }
    @Published var showComboInMenuBar: Bool  { didSet { save("showComboInMenuBar", showComboInMenuBar) } }
    @Published var launchAtLogin: Bool      {
        didSet {
            save("launchAtLogin", launchAtLogin)
            LaunchAtLoginManager.setEnabled(launchAtLogin)
        }
    }

    private func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private init() {
        let d = UserDefaults.standard
        isEnabled          = d.object(forKey: "isEnabled")          as? Bool   ?? true
        sensitivity        = d.object(forKey: "sensitivity")        as? Double ?? 0.5
        cooldown           = d.object(forKey: "cooldown")           as? Double ?? 0.4
        dynamicVolume      = d.object(forKey: "dynamicVolume")      as? Bool   ?? true
        volume             = d.object(forKey: "volume")             as? Double ?? 0.8
        screenFlashEnabled = d.object(forKey: "screenFlash")        as? Bool   ?? true
        comboEnabled       = d.object(forKey: "comboEnabled")       as? Bool   ?? true
        showComboInMenuBar = d.object(forKey: "showComboInMenuBar") as? Bool   ?? true
        launchAtLogin      = d.object(forKey: "launchAtLogin")      as? Bool   ?? false
        let packRaw        = d.string(forKey: "selectedPack") ?? SoundPack.punch.rawValue
        selectedPack       = SoundPack(rawValue: packRaw) ?? .punch
    }
}

// MARK: - Sound Packs

enum SoundPack: String, CaseIterable, Identifiable {
    case punch  = "punch"
    case yamete = "yamete"
    case goat   = "goat"
    case sexy   = "sexy"
    case fart   = "fart"
    case male   = "male"
    case wtf    = "wtf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .punch:  return "Punch"
        case .yamete: return "Yamete"
        case .goat:   return "Goat"
        case .sexy:   return "Sexy"
        case .fart:   return "Fart"
        case .male:   return "Male Screams"
        case .wtf:    return "WTF"
        }
    }

    var emoji: String {
        switch self {
        case .punch:  return "👊"
        case .yamete: return "🇯🇵"
        case .goat:   return "🐐"
        case .sexy:   return "🔥"
        case .fart:   return "💨"
        case .male:   return "🗣️"
        case .wtf:    return "😱"
        }
    }

    var description: String {
        switch self {
        case .punch:  return "Classic fighting game punch SFX"
        case .yamete: return "Dramatic anime reactions"
        case .goat:   return "Goat screams. Only goat screams."
        case .sexy:   return "Suggestive responses to your hits"
        case .fart:   return "Bodily percussion, SFW edition"
        case .male:   return "Male pain reactions — Ow, Ouch…"
        case .wtf:    return "Random WTF reaction sounds"
        }
    }

    // Exact filenames present in Resources/ (no extension)
    var allFileNames: [String] {
        switch self {
        case .punch:
            return (1...26).map { String(format: "punch_%02d", $0) }
        case .yamete:
            return (1...6).map  { String(format: "yamete_%02d", $0) }
        case .goat:
            return (1...10).map { "goat_\($0)" }
        case .sexy:
            return (0...41).map { String(format: "sexy_%02d", $0) }
        case .fart:
            return (1...13).map { String(format: "fart_%02d", $0) }
        case .male:
            return ["male_00_Ow","male_01_Ouch","male_02_Owwie",
                    "male_03_Hey_that_hurts","male_04_Ow_stop_it",
                    "male_05_What_was_that_for","male_06_Ow_ow_ow",
                    "male_07_Hey","male_08_Yowch","male_09_That_stings"]
        case .wtf:
            return (1...7).map  { String(format: "wtf_%02d", $0) }
        }
    }
}

// MARK: - Launch at Login

enum LaunchAtLoginManager {
    static func setEnabled(_ enabled: Bool) {
        // In a signed build: SMAppService.mainApp.register() / unregister()
        _ = enabled
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let impactDetected = Notification.Name("impactDetected")
    static let comboUpdated   = Notification.Name("comboUpdated")
}
