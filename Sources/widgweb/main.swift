import AppKit
import WebKit

struct WidgetConfig: Decodable {
    var width: Double?
    var height: Double?
    /// Offset from the top-left of the main screen.
    var left: Double?
    var top: Double?
    var interactive: Bool?
}

/// Covers the web view in edit mode so the whole widget can be dragged.
final class DragView: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class WidgetWindow: NSWindow {
    let name: String
    let config: WidgetConfig
    let webView: WKWebView
    let dragView = DragView()

    init(dir: URL, config: WidgetConfig) {
        name = dir.lastPathComponent
        self.config = config
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear

        let saved = UserDefaults.standard.string(forKey: "origin.\(name)").map(NSPointFromString)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let size = NSSize(width: config.width ?? 300, height: config.height ?? 200)
        let origin = saved ?? NSPoint(x: screen.minX + (config.left ?? 40),
                                      y: screen.maxY - (config.top ?? 40) - size.height)
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        // Above Finder's desktop icons (so clicks reach us) but below normal windows.
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]

        let container = NSView()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        dragView.frame = container.bounds
        dragView.autoresizingMask = [.width, .height]
        dragView.wantsLayer = true
        dragView.layer?.borderColor = NSColor.systemBlue.cgColor
        dragView.layer?.borderWidth = 2
        container.addSubview(webView)
        container.addSubview(dragView)
        contentView = container

        setEditing(false)
        webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)

        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            guard let self else { return }
            UserDefaults.standard.set(NSStringFromPoint(self.frame.origin), forKey: "origin.\(self.name)")
        }
    }

    func setEditing(_ editing: Bool) {
        dragView.isHidden = !editing
        ignoresMouseEvents = !(editing || config.interactive == true)
    }

    override var canBecomeKey: Bool { config.interactive == true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let widgetsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/widgweb/widgets")
    var windows: [WidgetWindow] = []
    var statusItem: NSStatusItem!
    let editItem = NSMenuItem(title: "Edit Positions", action: #selector(toggleEdit), keyEquivalent: "e")

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: widgetsDir, withIntermediateDirectories: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "widgweb")
        let menu = NSMenu()
        menu.addItem(editItem)
        menu.addItem(NSMenuItem(title: "Reload Widgets", action: #selector(reload), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Widgets Folder", action: #selector(openFolder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu

        reload()
    }

    @objc func reload() {
        windows.forEach { $0.close() }
        editItem.state = .off
        let dirs = (try? FileManager.default.contentsOfDirectory(at: widgetsDir, includingPropertiesForKeys: nil)) ?? []
        windows = dirs
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { dir in
                var config = WidgetConfig()
                if let data = try? Data(contentsOf: dir.appendingPathComponent("widget.json")) {
                    do { config = try JSONDecoder().decode(WidgetConfig.self, from: data) }
                    catch { NSLog("widgweb: bad widget.json in \(dir.lastPathComponent): \(error)") }
                }
                return WidgetWindow(dir: dir, config: config)
            }
        windows.forEach { $0.orderFront(nil) }
    }

    @objc func toggleEdit() {
        editItem.state = editItem.state == .on ? .off : .on
        windows.forEach { $0.setEditing(editItem.state == .on) }
    }

    @objc func openFolder() { NSWorkspace.shared.open(widgetsDir) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
