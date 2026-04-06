// MenuBarView.swift
// MacTap — Main popover view shown when clicking the menu bar icon

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var detector: ImpactDetector
    @State private var selectedTab: Tab = .main

    enum Tab: String, CaseIterable {
        case main   = "hand.raised.fill"
        case sounds = "music.note"
        case config = "gearshape.fill"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header
            header

            Divider()

            // ── Tab Content
            ZStack {
                switch selectedTab {
                case .main:   MainTab()
                case .sounds: SoundsTab()
                case .config: ConfigTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // ── Tab Bar
            tabBar

            Divider()

            // ── Quit Row
            quitRow
        }
        .frame(width: 340, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(settings.isEnabled
                          ? Color.accentColor.opacity(0.18)
                          : Color.secondary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: settings.isEnabled ? "hand.raised.fill" : "hand.raised.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(settings.isEnabled ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: detector.lastImpactIntensity)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("MacTap")
                    .font(.system(size: 15, weight: .bold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(settings.isEnabled && detector.isListening ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Combo badge
            if detector.comboCount > 1 {
                comboBadge
                    .transition(.scale.combined(with: .opacity))
            }

            // Enable toggle
            Toggle("", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: settings.isEnabled) { _, enabled in
                    if enabled { detector.start() } else { detector.stop() }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.spring(duration: 0.3), value: detector.comboCount)
    }

    var statusText: String {
        if !detector.accelerometerFound {
            return "No accelerometer found"
        }
        return settings.isEnabled ? "Listening…" : "Disabled"
    }

    var comboBadge: some View {
        VStack(spacing: 0) {
            Text(detector.comboTier.rawValue)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(detector.comboTier.color)
            Text("×\(detector.comboCount)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(detector.comboTier.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(detector.comboTier.color.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(detector.comboTier.color.opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Tab Bar
    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: tab.rawValue)
                        .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            selectedTab == tab
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quit Row
    var quitRow: some View {
        HStack {
            Text("MacTap v1.0")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit MacTap") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

// MARK: - Main Tab (slap counter + live feedback)
struct MainTab: View {
    @EnvironmentObject var detector: ImpactDetector
    @EnvironmentObject var settings: AppSettings
    @State private var showResetAlert = false
    @State private var pulseAmount: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Big slap counter
            VStack(spacing: 4) {
                Text("\(detector.totalSlapCount)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .scaleEffect(pulseAmount)
                    .animation(.spring(response: 0.2, dampingFraction: 0.5), value: pulseAmount)

                Text("total slaps")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Impact bar
            ImpactBar(intensity: detector.lastImpactIntensity)
                .frame(height: 8)
                .padding(.horizontal, 24)

            // Hint
            Text(hintText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .animation(.easeInOut, value: detector.accelerometerFound)

            Spacer()

            // Reset button
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset Count", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)
        }
        .onChange(of: detector.totalSlapCount) { _, _ in
            pulseAmount = 1.12
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pulseAmount = 1.0
            }
        }
        .alert("Reset Slap Count?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { detector.resetSlapCount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your total slap count to zero. This cannot be undone.")
        }
    }

    var hintText: String {
        if !detector.accelerometerFound {
            return "⚠️ No accelerometer found.\nThis Mac may not have a compatible sensor."
        }
        if !settings.isEnabled {
            return "Detection is disabled.\nToggle the switch to start."
        }
        return "Give your Mac a slap! 👊"
    }
}

// MARK: - Sounds Tab
struct SoundsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sound Pack")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                ForEach(SoundPack.allCases) { pack in
                    SoundPackRow(pack: pack, isSelected: settings.selectedPack == pack) {
                        settings.selectedPack = pack
                    }
                }

                Divider().padding(.horizontal, 16).padding(.top, 4)

                // Volume
                VStack(alignment: .leading, spacing: 10) {
                    Label("Volume", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .medium))

                    HStack {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.volume)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Dynamic Volume (harder hit = louder)", isOn: $settings.dynamicVolume)
                        .font(.system(size: 12))
                        .toggleStyle(.checkbox)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }
}

struct SoundPackRow: View {
    let pack: SoundPack
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(pack.emoji)
                    .font(.system(size: 22))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(pack.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(pack.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                isSelected
                ? Color.accentColor.opacity(0.08)
                : Color.clear
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Config Tab
struct ConfigTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Detection
                SectionHeader("Detection")

                ConfigSlider(
                    label: "Sensitivity",
                    description: "Higher = triggers on lighter taps",
                    icon: "waveform",
                    value: $settings.sensitivity
                )

                ConfigSlider(
                    label: "Cooldown",
                    description: "Minimum time between sounds (\(String(format: "%.1fs", settings.cooldown)))",
                    icon: "timer",
                    value: $settings.cooldown,
                    range: 0.1...2.0
                )

                Divider().padding(.horizontal, 16).padding(.vertical, 4)

                // ── Effects
                SectionHeader("Effects")

                ToggleRow(
                    label: "Screen Flash",
                    description: "Flash the screen on each hit",
                    icon: "bolt.fill",
                    isOn: $settings.screenFlashEnabled
                )

                ToggleRow(
                    label: "Combo System",
                    description: "Track consecutive hits",
                    icon: "flame.fill",
                    isOn: $settings.comboEnabled
                )

                ToggleRow(
                    label: "Show Combo in Menu Bar",
                    description: "Display ×N counter next to icon",
                    icon: "menubar.rectangle",
                    isOn: $settings.showComboInMenuBar
                )

                Divider().padding(.horizontal, 16).padding(.vertical, 4)

                // ── System
                SectionHeader("System")

                ToggleRow(
                    label: "Launch at Login",
                    description: "Start MacTap automatically",
                    icon: "power",
                    isOn: $settings.launchAtLogin
                )
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Sub-components

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

struct ConfigSlider: View {
    let label: String
    let description: String
    let icon: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                Slider(value: $value, in: range)
                Text(String(format: "%.0f%%", (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ToggleRow: View {
    let label: String
    let description: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}

// MARK: - Impact Bar
struct ImpactBar: View {
    let intensity: Double
    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))

                RoundedRectangle(cornerRadius: 4)
                    .fill(barGradient)
                    .frame(width: geo.size.width * animated)
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: animated)
            }
        }
        .onChange(of: intensity) { _, newVal in
            animated = newVal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.4)) { animated = 0 }
            }
        }
    }

    var barGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
