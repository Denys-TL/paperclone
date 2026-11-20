import AppKit

/// Owns the whole app: the menu-bar item + menu, the per-display overlay
/// windows, and the current state (enabled / intensity / texture size / grain
/// size), which it persists in
/// `UserDefaults` and fans out to every overlay. The texture is fixed to
/// `PaperTexture.vellumMist`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var slider: NSSlider!
    private var intensityValueLabel: NSTextField!
    private var textureSizeSlider: NSSlider!
    private var textureSizeValueLabel: NSTextField!
    private var grainSizeSlider: NSSlider!
    private var grainSizeValueLabel: NSTextField!

    private var overlays: [OverlayWindow] = []

    private let texture = PaperTexture.vellumMist

    private let defaults = UserDefaults.standard
    private var enabled = true
    private var intensity = PaperTexture.vellumMist.defaultOpacity   // 0...1

    private let minIntensity = 0.03
    private let maxIntensity = 0.40

    private var textureSize = PaperTexture.vellumMist.defaultTextureSize   // tile zoom
    private var grainSize = PaperTexture.vellumMist.defaultGrainSize       // pixels

    private let minTextureSize = 0.5
    private let maxTextureSize = 4.0
    private let minGrainSize = 0.9
    private let maxGrainSize = 12.0

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPrefs()
        buildStatusItem()
        rebuildOverlays()
        applyToAll()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    private func loadPrefs() {
        if defaults.object(forKey: "enabled") != nil { enabled = defaults.bool(forKey: "enabled") }
        if defaults.object(forKey: "intensity") != nil { intensity = defaults.double(forKey: "intensity") }
        intensity = min(max(intensity, minIntensity), maxIntensity)
        if defaults.object(forKey: "textureSize") != nil { textureSize = defaults.double(forKey: "textureSize") }
        textureSize = min(max(textureSize, minTextureSize), maxTextureSize)
        if defaults.object(forKey: "grainSize") != nil { grainSize = defaults.double(forKey: "grainSize") }
        grainSize = min(max(grainSize, minGrainSize), maxGrainSize)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = buildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = Icons.statusBar(enabled: enabled)
        button.toolTip = "PaperClone — paper texture overlay"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Header — app name + paper glyph, not selectable.
        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(string: "PaperClone", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        header.image = Icons.statusBar(enabled: true)
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = enabled ? .on : .off
        toggleItem.image = Icons.symbol("power")
        menu.addItem(toggleItem)

        let intensityRow = buildSliderRow(title: "Intensity", valueText: percentString(),
                                          value: intensity, range: minIntensity...maxIntensity,
                                          action: #selector(intensityChanged(_:)))
        slider = intensityRow.slider
        intensityValueLabel = intensityRow.valueLabel

        let textureSizeRow = buildSliderRow(title: "Texture size", valueText: textureSizeString(),
                                            value: textureSize, range: minTextureSize...maxTextureSize,
                                            action: #selector(textureSizeChanged(_:)))
        textureSizeSlider = textureSizeRow.slider
        textureSizeValueLabel = textureSizeRow.valueLabel

        let grainSizeRow = buildSliderRow(title: "Grain size", valueText: grainSizeString(),
                                          value: grainSize, range: minGrainSize...maxGrainSize,
                                          action: #selector(grainSizeChanged(_:)))
        grainSizeSlider = grainSizeRow.slider
        grainSizeValueLabel = grainSizeRow.valueLabel

        for row in [intensityRow, textureSizeRow, grainSizeRow] {
            let item = NSMenuItem()
            item.view = row.view
            menu.addItem(item)
        }

        let reset = NSMenuItem(title: "Reset Texture", action: #selector(resetTexture), keyEquivalent: "")
        reset.target = self
        reset.image = Icons.symbol("arrow.counterclockwise")
        menu.addItem(reset)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit PaperClone", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = Icons.symbol("xmark.circle")
        menu.addItem(quit)

        return menu
    }

    private func percentString() -> String {
        "\(Int((intensity * 100).rounded()))%"
    }

    private func textureSizeString() -> String {
        String(format: "%.1f×", textureSize)
    }

    private func grainSizeString() -> String {
        String(format: "%.1f px", grainSize)
    }

    private func buildSliderRow(title: String,
                                valueText: String,
                                value: Double,
                                range: ClosedRange<Double>,
                                action: Selector) -> (view: NSView, slider: NSSlider, valueLabel: NSTextField) {
        let width: CGFloat = 244
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 56))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 14, y: 33, width: 120, height: 16)
        container.addSubview(titleLabel)

        let valueLabel = NSTextField(labelWithString: valueText)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - 74, y: 33, width: 60, height: 16)
        container.addSubview(valueLabel)

        let rowSlider = NSSlider(value: value,
                                 minValue: range.lowerBound,
                                 maxValue: range.upperBound,
                                 target: self,
                                 action: action)
        rowSlider.isContinuous = true
        rowSlider.controlSize = .small
        rowSlider.frame = NSRect(x: 14, y: 9, width: width - 28, height: 20)
        container.addSubview(rowSlider)

        return (container, rowSlider, valueLabel)
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        enabled.toggle()
        toggleItem.state = enabled ? .on : .off
        updateStatusIcon()
        defaults.set(enabled, forKey: "enabled")
        overlays.forEach { $0.setVisible(enabled) }
    }

    @objc private func intensityChanged(_ sender: NSSlider) {
        intensity = sender.doubleValue
        intensityValueLabel?.stringValue = percentString()
        defaults.set(intensity, forKey: "intensity")
        applyToAll()
    }

    @objc private func textureSizeChanged(_ sender: NSSlider) {
        textureSize = sender.doubleValue
        textureSizeValueLabel?.stringValue = textureSizeString()
        defaults.set(textureSize, forKey: "textureSize")
        applyToAll()
    }

    @objc private func grainSizeChanged(_ sender: NSSlider) {
        grainSize = sender.doubleValue
        grainSizeValueLabel?.stringValue = grainSizeString()
        defaults.set(grainSize, forKey: "grainSize")
        applyToAll()
    }

    @objc private func resetTexture() {
        textureSize = texture.defaultTextureSize
        grainSize = texture.defaultGrainSize
        textureSizeSlider.doubleValue = textureSize
        grainSizeSlider.doubleValue = grainSize
        textureSizeValueLabel.stringValue = textureSizeString()
        grainSizeValueLabel.stringValue = grainSizeString()
        defaults.removeObject(forKey: "textureSize")
        defaults.removeObject(forKey: "grainSize")
        applyToAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        applyToAll()
    }

    // MARK: Overlays

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
    }

    private func applyToAll() {
        let pattern = PaperTextureRenderer.tile(for: texture, grainSize: grainSize, textureSize: textureSize)   // render once, share across displays
        for overlay in overlays {
            overlay.apply(patternImage: pattern, intensity: intensity)
            overlay.setVisible(enabled)
        }
    }
}
