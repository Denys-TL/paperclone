import AppKit

/// Owns the whole app: the menu-bar item + menu, the per-display overlay
/// windows, and the current `PaperSettings`, which it persists in
/// `UserDefaults` and fans out to every overlay. The texture is fixed to
/// `PaperTexture.vellumMist`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var washValueLabel: NSTextField!
    private var grainValueLabel: NSTextField!
    private var textureSizeSlider: NSSlider!
    private var textureSizeValueLabel: NSTextField!
    private var grainSizeSlider: NSSlider!
    private var grainSizeValueLabel: NSTextField!

    private var overlays: [OverlayWindow] = []
    private var pattern: NSImage?

    // Tiles larger than this re-render on slider release instead of every drag tick.
    private let liveRenderMaxPixelEdge = 2560

    private let texture = PaperTexture.vellumMist

    private var settings = PaperSettings.load(texture: .vellumMist)

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        rebuildOverlays()
        renderPattern()
        applyToAll()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.menu = buildMenu()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = Icons.statusBar(enabled: settings.enabled)
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
        toggleItem.state = settings.enabled ? .on : .off
        toggleItem.image = Icons.symbol("power")
        menu.addItem(toggleItem)

        let washRow = buildSliderRow(title: "Wash", valueText: percentString(settings.wash),
                                     value: settings.wash, range: PaperSettings.washRange,
                                     action: #selector(washChanged(_:)))
        washValueLabel = washRow.valueLabel

        let grainRow = buildSliderRow(title: "Grain strength", valueText: percentString(settings.grain),
                                      value: settings.grain, range: PaperSettings.grainRange,
                                      action: #selector(grainChanged(_:)))
        grainValueLabel = grainRow.valueLabel

        let textureSizeRow = buildSliderRow(title: "Texture size", valueText: textureSizeString(),
                                            value: settings.textureSize, range: PaperSettings.textureSizeRange,
                                            action: #selector(textureSizeChanged(_:)))
        textureSizeSlider = textureSizeRow.slider
        textureSizeValueLabel = textureSizeRow.valueLabel

        let grainSizeRow = buildSliderRow(title: "Grain size", valueText: grainSizeString(),
                                          value: settings.grainSize, range: PaperSettings.grainSizeRange,
                                          action: #selector(grainSizeChanged(_:)))
        grainSizeSlider = grainSizeRow.slider
        grainSizeValueLabel = grainSizeRow.valueLabel

        for row in [washRow, grainRow, textureSizeRow, grainSizeRow] {
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

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func textureSizeString() -> String {
        String(format: "%.1f×", settings.textureSize)
    }

    private func grainSizeString() -> String {
        String(format: "%.1f px", settings.grainSize)
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
        settings.enabled.toggle()
        toggleItem.state = settings.enabled ? .on : .off
        updateStatusIcon()
        settings.save()
        overlays.forEach { $0.setVisible(settings.enabled) }
    }

    @objc private func washChanged(_ sender: NSSlider) {
        settings.wash = sender.doubleValue
        washValueLabel?.stringValue = percentString(settings.wash)
        settings.save()
        applyToAll()
    }

    @objc private func grainChanged(_ sender: NSSlider) {
        settings.grain = sender.doubleValue
        grainValueLabel?.stringValue = percentString(settings.grain)
        settings.save()
        applyToAll()
    }

    @objc private func textureSizeChanged(_ sender: NSSlider) {
        settings.textureSize = sender.doubleValue
        textureSizeValueLabel?.stringValue = textureSizeString()
        textureShapeChanged()
    }

    @objc private func grainSizeChanged(_ sender: NSSlider) {
        settings.grainSize = sender.doubleValue
        grainSizeValueLabel?.stringValue = grainSizeString()
        textureShapeChanged()
    }

    private func textureShapeChanged() {
        let dragging = NSApp.currentEvent?.type == .leftMouseDragged
        if dragging && PaperTextureRenderer.pixelEdge(for: settings) > liveRenderMaxPixelEdge { return }
        settings.save()
        renderPattern()
        applyToAll()
    }

    @objc private func resetTexture() {
        settings.resetTexture(to: texture)
        textureSizeSlider.doubleValue = settings.textureSize
        grainSizeSlider.doubleValue = settings.grainSize
        textureSizeValueLabel.stringValue = textureSizeString()
        grainSizeValueLabel.stringValue = grainSizeString()
        settings.save()
        renderPattern()
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

    private func renderPattern() {
        pattern = PaperTextureRenderer.tile(for: texture, settings: settings)   // render once, share across displays
    }

    private func applyToAll() {
        guard let pattern else { return }
        for overlay in overlays {
            overlay.apply(patternImage: pattern, texture: texture, settings: settings)
            overlay.setVisible(settings.enabled)
        }
    }
}
