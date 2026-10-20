import AppKit
import SwiftUI
import Combine

@main struct FileConverterApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of:"--engine-acceptance"), CommandLine.arguments.indices.contains(index+1) {
            let root = URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
            Task { await EngineAcceptance.run(in:root) }
            application.run()
            return
        }
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let monitor = DragMonitor()
    private let wheel = WheelPanelController()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        FolderGrants.shared.restore()
        configureMenus()
        NSApplication.shared.servicesProvider = self
        model.onShowWindow = { [weak self] in self?.showWindow() }
        wheel.sounds = model.sounds
        model.onWheelSettingChanged = { [weak self] enabled in
            if enabled { self?.monitor.start() } else { self?.monitor.stop() }
        }
        model.onShowWheel = { [weak self] sources in
            guard let self else { return }
            self.wheel.show(sources: sources, at: NSEvent.mouseLocation, clickable: true)
        }
        wheel.inspect = { [weak self] urls in guard let self else { return [] }; return try await self.model.inspect(urls) }
        wheel.installedPacks = Set(model.packs.map(\.id))
        model.$packs.sink { [weak self] packs in self?.wheel.installedPacks = Set(packs.map(\.id)) }.store(in:&subscriptions)
        wheel.onConversion = { [weak self] sources, choice in self?.model.performWheel(sources,choice:choice) }
        monitor.modifier = model.modifier
        model.onModifierChanged = { [weak self] in self?.monitor.modifier = $0 }
        monitor.onActivation = { [weak self] sources, point in
            guard let self, !self.model.isCancelling else { return }
            self.wheel.show(sources: sources, at: point)
        }
        monitor.onDismissal = { [weak self] in self?.wheel.dismiss() }
        monitor.onRelease = { [weak self] point in self?.wheel.releaseDrag(at: point) }
        if model.wheelEnabled { monitor.start() }
        if !CommandLine.arguments.contains("--background") { showWindow() }
    }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop(); FolderGrants.shared.releaseAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    @objc func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = GlacierBrand.name; window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 930, height: 680)
            window.contentView = NSHostingView(rootView: WorkspaceView(model: model))
            window.center(); window.delegate = self
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func chooseImages() { showWindow(); model.pickFiles() }
    @objc func prepareFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = DragMonitor.files(from:pasteboard)
        guard !urls.isEmpty else { error.pointee = "Choose files in Finder first."; return }
        model.setSources(urls); showWindow()
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { model.setSources(filenames.map { URL(fileURLWithPath:$0) }); showWindow(); sender.reply(toOpenOrPrint:.success) }
    @objc private func showWheel() { showWindow(); model.pickFiles(showWheel: true) }
    @objc private func showSettings() { model.page = .settings; showWindow() }
    @objc private func showActivity() { model.page = .activity; showWindow() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    private func configureMenus() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = GlacierBrand.menuBarImage
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(menuItem("Open \(GlacierBrand.name)", action: #selector(showWindow)))
        menu.addItem(menuItem("Choose files…", action: #selector(chooseImages)))
        menu.addItem(menuItem("Open conversion wheel…", action: #selector(showWheel)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Activity", action: #selector(showActivity)))
        menu.addItem(menuItem("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(.separator()); menu.addItem(menuItem("Quit \(GlacierBrand.name)", action: #selector(quit), key: "q"))
        item.menu = menu; statusItem = item
        model.$isProcessing.sink { [weak item] working in
            item?.button?.toolTip = working ? "\(GlacierBrand.name) · Processing files…" : "\(GlacierBrand.name) · Drag files with your wheel modifier"
        }.store(in: &subscriptions)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: GlacierBrand.name, action: nil, keyEquivalent: ""); let appMenu = NSMenu(title: GlacierBrand.name)
        appMenu.addItem(menuItem("Settings…", action: #selector(showSettings), key: ","))
        appMenu.addItem(.separator()); appMenu.addItem(menuItem("Quit \(GlacierBrand.name)", action: #selector(quit), key: "q"))
        appMenuItem.submenu = appMenu; mainMenu.addItem(appMenuItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("Choose files…", action: #selector(chooseImages), key: "o"))
        fileMenu.addItem(menuItem("Open conversion wheel…", action: #selector(showWheel)))
        fileItem.submenu = fileMenu; mainMenu.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }
}
