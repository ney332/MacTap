// ImpactDetector.swift
// MacTap — Reads the MacBook's built-in accelerometer via IOHIDManager
// and detects physical impacts using a peak + threshold algorithm.

import Foundation
import IOKit.hid
import Combine

final class ImpactDetector: ObservableObject {
    static let shared = ImpactDetector()

    private enum SensorMode {
        case standardHID
        case appleVendorReport
    }

    private final class ReportBuffer {
        let pointer: UnsafeMutablePointer<UInt8>
        let size: Int

        init(size: Int) {
            self.size = size
            self.pointer = .allocate(capacity: size)
            self.pointer.initialize(repeating: 0, count: size)
        }

        deinit {
            pointer.deallocate()
        }
    }

    // MARK: - Published State
    @Published var isListening: Bool = false
    @Published var accelerometerFound: Bool = false
    @Published var comboCount: Int = 0
    @Published var comboTier: ComboTier = .none
    @Published var lastImpactIntensity: Double = 0   // 0–1 normalised
    @Published var totalSlapCount: Int = 0

    // MARK: - Private
    private var hidManager: IOHIDManager?
    private var reportBuffers: [UInt: ReportBuffer] = [:]
    private var connectedSensorIDs: Set<UInt> = []
    private var activeSensorMode: SensorMode?
    private var lastX: Double = 0
    private var lastY: Double = 0
    private var lastZ: Double = 0
    private var baselineX: Double = 0
    private var baselineY: Double = 0
    private var baselineZ: Double = 0
    private var hasBaseline = false
    private var lastImpactTime: Date = .distantPast
    private var comboResetTimer: Timer?
    private var settings: AppSettings { AppSettings.shared }

    // Thresholds are calibrated separately because Apple Silicon exposes
    // the accelerometer through a vendor-specific HID report.
    private let standardBaseThreshold: Double = 110.0
    private let vendorBaseThreshold: Double = 900.0

    private init() {
        totalSlapCount = UserDefaults.standard.integer(forKey: "totalSlapCount")
    }

    // MARK: - Start / Stop

    func start() {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        let matchingDictionaries: [[String: Any]] = [
            [
                kIOHIDPrimaryUsagePageKey: 0x000B,
                kIOHIDPrimaryUsageKey: 0x0053
            ],
            [
                kIOHIDPrimaryUsagePageKey: 0xFF00,
                kIOHIDPrimaryUsageKey: 0x0003
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDictionaries as CFArray)

        // Device callbacks
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            let detector = Unmanaged<ImpactDetector>.fromOpaque(ctx!).takeUnretainedValue()
            detector.attachIfSupported(device)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            let detector = Unmanaged<ImpactDetector>.fromOpaque(ctx!).takeUnretainedValue()
            detector.detach(device)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        DispatchQueue.main.async {
            self.isListening = (result == kIOReturnSuccess)
        }

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            devices.forEach { attachIfSupported($0) }
        }
    }

    func stop() {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidManager = nil
        reportBuffers.removeAll()
        connectedSensorIDs.removeAll()
        activeSensorMode = nil
        resetMotionState()
        DispatchQueue.main.async {
            self.isListening = false
            self.accelerometerFound = false
        }
    }

    // MARK: - HID Input Callback

    private func attachIfSupported(_ device: IOHIDDevice) {
        guard let mode = sensorMode(for: device) else { return }

        let deviceID = stableDeviceID(for: device)
        guard !connectedSensorIDs.contains(deviceID) else { return }
        connectedSensorIDs.insert(deviceID)
        activeSensorMode = mode

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            connectedSensorIDs.remove(deviceID)
            return
        }

        enableSensorStreamingIfNeeded(device)

        switch mode {
        case .standardHID:
            registerInputValueCallback(for: device)
        case .appleVendorReport:
            registerInputReportCallback(for: device)
        }

        DispatchQueue.main.async {
            self.accelerometerFound = true
        }
    }

    private func detach(_ device: IOHIDDevice) {
        let deviceID = stableDeviceID(for: device)
        connectedSensorIDs.remove(deviceID)
        reportBuffers.removeValue(forKey: deviceID)

        DispatchQueue.main.async {
            self.accelerometerFound = !self.connectedSensorIDs.isEmpty
        }
    }

    private func registerInputValueCallback(for device: IOHIDDevice) {
        IOHIDDeviceRegisterInputValueCallback(device, { ctx, _, _, value in
            let detector = Unmanaged<ImpactDetector>.fromOpaque(ctx!).takeUnretainedValue()
            detector.handleHIDValue(value)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func registerInputReportCallback(for device: IOHIDDevice) {
        let deviceID = stableDeviceID(for: device)
        let reportSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64
        let buffer = ReportBuffer(size: max(reportSize, 22))
        reportBuffers[deviceID] = buffer

        IOHIDDeviceRegisterInputReportCallback(device, buffer.pointer, buffer.size, { ctx, _, _, _, _, report, reportLength in
            let detector = Unmanaged<ImpactDetector>.fromOpaque(ctx!).takeUnretainedValue()
            detector.handleVendorReport(report: report, length: reportLength)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        guard settings.isEnabled else { return }

        let usage = IOHIDElementGetUsage(IOHIDValueGetElement(value))
        let intVal = Double(IOHIDValueGetIntegerValue(value))

        switch usage {
        case 0x0030: lastX = intVal  // X
        case 0x0031: lastY = intVal  // Y
        case 0x0032: lastZ = intVal  // Z
        default: return
        }

        processSample(x: lastX, y: lastY, z: lastZ, mode: .standardHID)
    }

    private func handleVendorReport(report: UnsafeMutablePointer<UInt8>?, length: CFIndex) {
        guard settings.isEnabled else { return }
        guard let report, length >= 18 else { return }

        let data = UnsafeBufferPointer(start: report, count: length)

        let x = Double(readInt32LE(data, at: 6))
        let y = Double(readInt32LE(data, at: 10))
        let z = Double(readInt32LE(data, at: 14))

        processSample(x: x, y: y, z: z, mode: .appleVendorReport)
    }

    private func processSample(x: Double, y: Double, z: Double, mode: SensorMode) {
        if !hasBaseline {
            lastX = x
            lastY = y
            lastZ = z
            baselineX = x
            baselineY = y
            baselineZ = z
            hasBaseline = true
            return
        }

        // High-pass the signal so gravity and slow desk movement do not
        // continuously trigger impacts.
        baselineX = baselineX * 0.92 + x * 0.08
        baselineY = baselineY * 0.92 + y * 0.08
        baselineZ = baselineZ * 0.92 + z * 0.08

        let jerkX = x - lastX
        let jerkY = y - lastY
        let jerkZ = z - lastZ

        let highPassX = x - baselineX
        let highPassY = y - baselineY
        let highPassZ = z - baselineZ

        lastX = x
        lastY = y
        lastZ = z

        let impactMagnitude = max(
            sqrt(highPassX * highPassX + highPassY * highPassY + highPassZ * highPassZ),
            sqrt(jerkX * jerkX + jerkY * jerkY + jerkZ * jerkZ)
        )

        // Adaptive threshold from sensitivity slider
        // sensitivity 0.0 = very insensitive (needs hard slap)
        // sensitivity 1.0 = very sensitive (light tap triggers)
        let baseThreshold = (mode == .appleVendorReport) ? vendorBaseThreshold : standardBaseThreshold
        let threshold = baseThreshold * (1.85 - settings.sensitivity * 1.45)

        guard impactMagnitude > threshold else { return }

        // Cooldown guard
        let now = Date()
        guard now.timeIntervalSince(lastImpactTime) >= settings.cooldown else { return }
        lastImpactTime = now

        // Normalise intensity 0–1
        let maxExpected = baseThreshold * 3.5
        let intensity = min(impactMagnitude / maxExpected, 1.0)

        DispatchQueue.main.async {
            self.fireImpact(intensity: intensity)
        }
    }

    // MARK: - Impact Event

    private func fireImpact(intensity: Double) {
        lastImpactIntensity = intensity
        totalSlapCount += 1
        UserDefaults.standard.set(totalSlapCount, forKey: "totalSlapCount")

        if settings.comboEnabled {
            comboCount += 1
            comboTier = ComboTier(from: comboCount)

            // Reset combo after 2 seconds of no hits
            comboResetTimer?.invalidate()
            comboResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.comboCount = 0
                    self?.comboTier = .none
                    NotificationCenter.default.post(name: .comboUpdated, object: nil)
                }
            }
        }

        NotificationCenter.default.post(
            name: .impactDetected,
            object: nil,
            userInfo: ["intensity": intensity, "combo": comboCount]
        )
        NotificationCenter.default.post(name: .comboUpdated, object: nil)

        // Trigger audio + effects
        let vol = settings.dynamicVolume
            ? settings.volume * (0.4 + intensity * 0.6)
            : settings.volume
        AudioEngine.shared.playRandom(pack: settings.selectedPack, volume: vol)

        if settings.screenFlashEnabled {
            ScreenFlash.flash(intensity: intensity, combo: comboCount)
        }
    }

    // MARK: - Reset
    func resetSlapCount() {
        totalSlapCount = 0
        UserDefaults.standard.set(0, forKey: "totalSlapCount")
    }

    private func sensorMode(for device: IOHIDDevice) -> SensorMode? {
        let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let maxInputSize = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0

        if usagePage == 0x000B, usage == 0x0053 {
            return .standardHID
        }

        if usagePage == 0xFF00, usage == 0x0003 {
            if let product, product.localizedCaseInsensitiveContains("trackpad") || product.localizedCaseInsensitiveContains("keyboard") {
                return nil
            }
            return maxInputSize <= 32 ? .appleVendorReport : nil
        }

        return nil
    }

    private func enableSensorStreamingIfNeeded(_ device: IOHIDDevice) {
        let trueValue = kCFBooleanTrue!
        IOHIDDeviceSetProperty(device, "SensorPropertyPowerState" as CFString, trueValue)
        IOHIDDeviceSetProperty(device, "SensorPropertyReportingState" as CFString, trueValue)
    }

    private func stableDeviceID(for device: IOHIDDevice) -> UInt {
        CFHash(device)
    }

    private func resetMotionState() {
        lastX = 0
        lastY = 0
        lastZ = 0
        baselineX = 0
        baselineY = 0
        baselineZ = 0
        hasBaseline = false
    }

    private func readInt32LE(_ data: UnsafeBufferPointer<UInt8>, at offset: Int) -> Int32 {
        guard data.count >= offset + 4 else { return 0 }

        let value = UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)

        return Int32(bitPattern: value)
    }
}

// MARK: - Combo Tier
enum ComboTier: String {
    case none    = ""
    case single  = "HIT!"
    case double  = "DOUBLE!"
    case triple  = "TRIPLE!"
    case quad    = "QUAD!!"
    case ultra   = "ULTRA!!!"
    case godlike = "GODLIKE!!!!"

    init(from count: Int) {
        switch count {
        case 0:     self = .none
        case 1:     self = .single
        case 2:     self = .double
        case 3:     self = .triple
        case 4:     self = .quad
        case 5...9: self = .ultra
        default:    self = .godlike
        }
    }

    var color: Color {
        switch self {
        case .none:    return .clear
        case .single:  return .white
        case .double:  return .yellow
        case .triple:  return .orange
        case .quad:    return .red
        case .ultra:   return .purple
        case .godlike: return .pink
        }
    }
}

import SwiftUI
