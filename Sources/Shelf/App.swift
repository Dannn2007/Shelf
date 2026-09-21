import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

// MARK: - 全局通知

extension Notification.Name {
    static let shelfNewModule    = Notification.Name("ShelfNewModule")
    static let shelfSelectModule = Notification.Name("ShelfSelectModule")
}

// MARK: - 应用级状态

final class AppState {
    static let shared = AppState()
    private init() {}

    weak var mainWindow: NSWindow?
    var openMainWindow: (() -> Void)?
}

// MARK: - 全局热键

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onPress: (() -> Void)?

    private init() {}

    /// 依次尝试若干组合，返回最终成功的一组（nil 表示全被占用）
    @discardableResult
    func register(primary: (UInt32, UInt32), fallbacks: [(UInt32, UInt32)] = []) -> (UInt32, UInt32)? {
        installHandlerIfNeeded()
        for (code, mods) in [primary] + fallbacks {
            unregisterCurrent()
            let status = RegisterEventHotKey(code, mods,
                                             EventHotKeyID(signature: 0x5348464C, id: 1),
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
            if status == noErr { return (code, mods) }
        }
        return nil
    }

    func unregisterCurrent() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onPress?() }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }
}

// MARK: - App

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = ShelfStore.shared

    var body: some Scene {
        Window("Shelf", id: "main") {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建模块") {
                    NotificationCenter.default.post(name: .shelfNewModule, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .help) {}
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        setupHotKey()
        NSApp.servicesProvider = self

        NotificationCenter.default.publisher(for: .shelfHotKeyChanged)
            .sink { [weak self] _ in self?.setupHotKey() }
            .store(in: &cancellables)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.openMainWindow?() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "square.stack.3d.up.fill",
                              accessibilityDescription: "Shelf") ?? NSImage()
            img.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(withTitle: "打开 Shelf",
                     action: #selector(showMainWindow),
                     keyEquivalent: "")
        menu.addItem(.separator())

        let store = ShelfStore.shared
        menu.addItem(NSMenuItem.sectionHeader(title: "模块"))
        for module in store.modules {
            let count = store.items.filter { $0.moduleID == module.id }.count
            let item = NSMenuItem(title: "\(module.name)  (\(count))",
                                  action: #selector(selectModule(_:)),
                                  keyEquivalent: "")
            item.representedObject = module.id.uuidString
            item.image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "偏好设置…",
                     action: #selector(openSettings),
                     keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Shelf",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    @objc private func showMainWindow() { AppState.shared.toggleWindow() }

    @objc private func selectModule(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let id = UUID(uuidString: s) else { return }
        AppState.shared.toggleWindow(open: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .shelfSelectModule, object: id)
        }
    }

    @objc private func openSettings() {
        AppState.shared.toggleWindow(open: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .shelfOpenSettings, object: nil)
        }
    }

    // MARK: 热键

    private func setupHotKey() {
        let s = ShelfSettings.shared
        let primary = (s.hotKeyCode, s.hotKeyModifiers)
        let fallbacks: [(UInt32, UInt32)] = [
            (49, UInt32(controlKey | optionKey)),   // ⌃⌥Space
            (49, UInt32(shiftKey | optionKey)),     // ⇧⌥Space
            (1,  UInt32(cmdKey | shiftKey))         // ⌘⇧S
        ]
        HotKeyManager.shared.onPress = { AppState.shared.toggleWindow() }
        if let chosen = HotKeyManager.shared.register(primary: primary, fallbacks: fallbacks),
           chosen != primary {
            // 首选组合被占用，自动落到可用组合
            s.hotKeyCode = chosen.0
            s.hotKeyModifiers = chosen.1
        }
    }
}

// MARK: - 窗口开关

extension AppState {
    func toggleWindow(open forceOpen: Bool = false) {
        DispatchQueue.main.async {
            if let w = self.mainWindow, w.isVisible {
                if forceOpen || !(NSApp.isActive && w.isKeyWindow) {
                    NSApp.activate(ignoringOtherApps: true)
                    w.makeKeyAndOrderFront(nil)
                } else {
                    w.orderOut(nil)
                }
                return
            }
            self.openMainWindow?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                NSApp.activate(ignoringOtherApps: true)
                self.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }
}

extension Notification.Name {
    static let shelfHotKeyChanged = Notification.Name("ShelfHotKeyChanged")
}
