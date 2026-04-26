import AppKit
import IOKit
import CoreGraphics

// MARK: - Ambient Light Sensor (IORegistry)

enum SensorResult {
    case success(lux: Double, raw: UInt64)
    case failure(String)
}

func readAmbientLux() -> SensorResult {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("IOMobileFramebufferShim")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return .failure("IOServiceGetMatchingServices failed — IOMobileFramebufferShim not found")
    }
    defer { IOObjectRelease(iterator) }

    var foundAny = false
    var service = IOIteratorNext(iterator)
    while service != 0 {
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        guard let ref = IORegistryEntryCreateCFProperty(
            service, "AmbientBrightness" as CFString,
            kCFAllocatorDefault, 0
        ) else { continue }

        let value = ref.takeRetainedValue()
        foundAny = true

        if let num = value as? NSNumber {
            let raw = num.uint64Value
            // External displays return fixed 65536 (= 1.0 after division); skip them
            if raw > 65536 {
                return .success(lux: Double(raw) / 65536.0, raw: raw)
            }
        }
    }

    if foundAny {
        return .failure("AmbientBrightness found but value <= 65536 (no internal display sensor?)")
    }
    return .failure("AmbientBrightness property not found on any IOMobileFramebufferShim")
}

// MARK: - Gamma Controller

final class GammaController {
    private var origRed = [CGGammaValue](repeating: 0, count: 256)
    private var origGreen = [CGGammaValue](repeating: 0, count: 256)
    private var origBlue = [CGGammaValue](repeating: 0, count: 256)
    private var sampleCount: UInt32 = 0
    private var captured = false

    func capture(displayID: CGDirectDisplayID) {
        CGGetDisplayTransferByTable(displayID, 256,
            &origRed, &origGreen, &origBlue, &sampleCount)
        captured = true
    }

    /// brightness: 0.0 (black) to 1.0 (normal). Clamped to 0.08 minimum.
    func apply(brightness: Float, displayID: CGDirectDisplayID) -> CGError {
        if !captured { capture(displayID: displayID) }
        let f = CGGammaValue(max(0.08, min(1.0, brightness)))
        let r = origRed.map { $0 * f }
        let g = origGreen.map { $0 * f }
        let b = origBlue.map { $0 * f }
        return CGSetDisplayTransferByTable(displayID, sampleCount, r, g, b)
    }

    func restore() {
        CGDisplayRestoreColorSyncSettings()
        captured = false
    }
}

// MARK: - Display helpers

struct DisplayInfo {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
}

func listDisplays() -> [DisplayInfo] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    return (0..<Int(count)).map { i in
        let id = ids[i]
        let builtIn = CGDisplayIsBuiltin(id) != 0
        let bounds = CGDisplayBounds(id)
        let name = builtIn
            ? "Built-in Display"
            : "External (\(Int(bounds.width))x\(Int(bounds.height)))"
        return DisplayInfo(id: id, name: name, isBuiltIn: builtIn)
    }
}

// MARK: - Sandbox check

func isSandboxed() -> Bool {
    ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}

func testCorebrightnessdiag() -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/libexec/corebrightnessdiag")
    proc.arguments = ["status-info"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus == 0 {
            let output = String(data: data, encoding: .utf8) ?? ""
            if let range = output.range(of: "AggregatedLux\\s*=\\s*([\\d.]+)",
                                        options: .regularExpression) {
                return "OK: \(output[range])"
            }
            return "OK but AggregatedLux not found"
        }
        return "exit code \(proc.terminationStatus)"
    } catch {
        return "BLOCKED: \(error.localizedDescription)"
    }
}

// MARK: - App UI

final class PoCDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    let gamma = GammaController()
    var displays: [DisplayInfo] = []

    // Sensor UI
    var luxValueLabel: NSTextField!
    var rawValueLabel: NSTextField!
    var statusLabel: NSTextField!
    var sandboxLabel: NSTextField!
    var cbdiagLabel: NSTextField!

    // Gamma UI
    var displayPopup: NSPopUpButton!
    var slider: NSSlider!
    var pctLabel: NSTextField!

    // Log
    var logScroll: NSScrollView!
    var logView: NSTextView!

    // Stats
    var readCount = 0
    var successCount = 0

    var selectedDisplay: CGDirectDisplayID {
        guard !displays.isEmpty, let popup = displayPopup else { return CGMainDisplayID() }
        return displays[popup.indexOfSelectedItem].id
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        displays = listDisplays()
        buildWindow()

        let sandboxed = isSandboxed()
        sandboxLabel.stringValue = sandboxed ? "YES — App Sandbox active" : "NO — not sandboxed"
        sandboxLabel.textColor = sandboxed ? .systemGreen : .systemOrange
        log("Sandbox: \(sandboxed)")
        log("Displays: \(displays.map { "\($0.name) [ID \($0.id)]" }.joined(separator: ", "))")

        // Test corebrightnessdiag (should fail in sandbox)
        let cbResult = testCorebrightnessdiag()
        cbdiagLabel.stringValue = "corebrightnessdiag: \(cbResult)"
        cbdiagLabel.textColor = cbResult.hasPrefix("BLOCKED") ? .systemGreen : .systemOrange
        log("corebrightnessdiag: \(cbResult)")

        // Start 1-second polling
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gamma.restore()
    }

    // MARK: Poll sensor

    func poll() {
        readCount += 1
        switch readAmbientLux() {
        case .success(let lux, let raw):
            successCount += 1
            luxValueLabel.stringValue = String(format: "%.1f lux", lux)
            luxValueLabel.textColor = .labelColor
            rawValueLabel.stringValue = "raw: \(raw)  (/ 65536 = \(String(format: "%.3f", Double(raw) / 65536.0)))"
            statusLabel.stringValue = "\(successCount)/\(readCount) reads OK"
            statusLabel.textColor = .systemGreen
        case .failure(let msg):
            luxValueLabel.stringValue = "— lux"
            luxValueLabel.textColor = .systemRed
            rawValueLabel.stringValue = msg
            statusLabel.stringValue = "\(successCount)/\(readCount) reads OK"
            statusLabel.textColor = successCount > 0 ? .systemOrange : .systemRed
            if readCount <= 3 { log("Sensor error: \(msg)") }
        }
    }

    // MARK: Gamma actions

    @objc func sliderMoved(_ sender: NSSlider) {
        let val = sender.floatValue
        pctLabel.stringValue = String(format: "%.0f%%", val * 100)
        let err = gamma.apply(brightness: val, displayID: selectedDisplay)
        if err != .success {
            log("CGSetDisplayTransferByTable error: \(err.rawValue)")
        }
    }

    @objc func restoreClicked(_ sender: Any) {
        gamma.restore()
        slider.floatValue = 1.0
        pctLabel.stringValue = "100%"
        log("Gamma restored")
    }

    @objc func displayChanged(_ sender: NSPopUpButton) {
        gamma.restore()
        gamma.capture(displayID: selectedDisplay)
        slider.floatValue = 1.0
        pctLabel.stringValue = "100%"
        log("Switched to: \(displays[sender.indexOfSelectedItem].name)")
    }

    func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)\n"
        logView?.textStorage?.append(NSAttributedString(
            string: line,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         .foregroundColor: NSColor.secondaryLabelColor]
        ))
        logView?.scrollToEndOfDocument(nil)
    }

    // MARK: Build window

    func buildWindow() {
        let w: CGFloat = 520, h: CGFloat = 540
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Gnomon PoC — Sensor + Gamma"
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window.contentView = content

        var y = h - 30

        // --- Section: Sensor ---
        y -= 4
        content.addSubview(sectionHeader("AMBIENT LIGHT SENSOR (IORegistry)", x: 16, y: y))
        y -= 40
        luxValueLabel = bigLabel("— lux", x: 20, y: y)
        content.addSubview(luxValueLabel)
        y -= 20
        rawValueLabel = smallLabel("waiting...", x: 20, y: y)
        content.addSubview(rawValueLabel)
        y -= 20
        statusLabel = smallLabel("0/0 reads", x: 20, y: y)
        content.addSubview(statusLabel)
        y -= 20
        sandboxLabel = smallLabel("checking...", x: 20, y: y)
        content.addSubview(sandboxLabel)
        y -= 20
        cbdiagLabel = smallLabel("corebrightnessdiag: testing...", x: 20, y: y)
        content.addSubview(cbdiagLabel)

        // --- Section: Gamma ---
        y -= 30
        content.addSubview(sectionHeader("GAMMA TABLE DIMMING (CGSetDisplayTransferByTable)", x: 16, y: y))
        y -= 28

        let dispLabel = smallLabel("Display:", x: 20, y: y + 2)
        content.addSubview(dispLabel)
        displayPopup = NSPopUpButton(frame: NSRect(x: 80, y: y, width: 300, height: 24), pullsDown: false)
        for d in displays { displayPopup.addItem(withTitle: "\(d.name) [ID \(d.id)]") }
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged(_:))
        content.addSubview(displayPopup)

        y -= 32
        let brLabel = smallLabel("Brightness:", x: 20, y: y + 2)
        content.addSubview(brLabel)
        slider = NSSlider(frame: NSRect(x: 100, y: y, width: 280, height: 24))
        slider.minValue = 0.08
        slider.maxValue = 1.0
        slider.floatValue = 1.0
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        content.addSubview(slider)

        pctLabel = NSTextField(labelWithString: "100%")
        pctLabel.frame = NSRect(x: 390, y: y + 2, width: 50, height: 18)
        pctLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        content.addSubview(pctLabel)

        let restoreBtn = NSButton(title: "Restore", target: self, action: #selector(restoreClicked(_:)))
        restoreBtn.frame = NSRect(x: 440, y: y - 2, width: 65, height: 28)
        restoreBtn.bezelStyle = .rounded
        content.addSubview(restoreBtn)

        // --- Section: Log ---
        y -= 36
        content.addSubview(sectionHeader("LOG", x: 16, y: y))
        y -= 4

        logScroll = NSScrollView(frame: NSRect(x: 16, y: 12, width: w - 32, height: y - 12))
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logView = NSTextView(frame: logScroll.bounds)
        logView.isEditable = false
        logView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5)
        logView.autoresizingMask = [.width, .height]
        logScroll.documentView = logView
        content.addSubview(logScroll)

        window.makeKeyAndOrderFront(nil)
    }

    func sectionHeader(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 490, height: 16)
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        return label
    }

    func bigLabel(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 300, height: 32)
        label.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        return label
    }

    func smallLabel(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 490, height: 16)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        return label
    }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = PoCDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
