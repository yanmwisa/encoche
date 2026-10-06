//
//  AppDelegate.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import AppKit
import Cocoa
import LaunchAtLogin

class AppDelegate: NSObject, NSApplicationDelegate {
    var isFirstOpen = true
    var isLaunchedAtLogin = false
    var mainWindowController: NotchWindowController?

    var timer: Timer?
    var demoNotificationsTimer: Timer?

    // Sessions Claude Code : un seul magasin pour toutes les fenêtres d'encoche.
    let sessionStore = SessionStore()
    var sessionServer: SessionSocketServer?
    var sessionSweepTimer: Timer?
    // Lancement avec --demo-notifications : une fausse notification toutes les 12 secondes.
    let isDemoNotifications = CommandLine.arguments.contains("--demo-notifications")

    func applicationDidFinishLaunching(_: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildApplicationWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSApp.setActivationPolicy(.accessory)

        isLaunchedAtLogin = LaunchAtLogin.wasLaunchedAtLogin

        _ = EventMonitors.shared
        let timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.determineIfProcessIdentifierMatches()
            self?.makeKeyAndVisibleIfNeeded()
        }
        self.timer = timer

        rebuildApplicationWindows()
        startDemoNotificationsIfRequested()
        startSessionServer()
        NowPlayingStore.shared.start()
        BrowserBridgeStore.shared.start()
    }

    func startSessionServer() {
        let store = sessionStore
        let server = SessionSocketServer { event in
            DispatchQueue.main.async { store.receive(event) }
        }
        do {
            try server.start()
            sessionServer = server
        } catch {
            NSLog("Encoche : réception des sessions impossible : \(error)")
        }
        sessionSweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [store] _ in
            store.sweep()
        }
    }

    func startDemoNotificationsIfRequested() {
        guard isDemoNotifications else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showNextDemoNotification()
        }
        demoNotificationsTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            self?.showNextDemoNotification()
        }
    }

    func showNextDemoNotification() {
        mainWindowController?.vm?.notificationShowNextSample()
    }

    func applicationWillTerminate(_: Notification) {
        sessionServer?.stop()
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try? FileManager.default.removeItem(at: pidFile)
    }

    func findScreenFitsOurNeeds() -> NSScreen? {
        if let screen = NSScreen.buildin, screen.notchSize != .zero { return screen }
        return .main
    }

    @objc func rebuildApplicationWindows() {
        defer { isFirstOpen = false }
        if let mainWindowController {
            mainWindowController.destroy()
        }
        mainWindowController = nil
        guard let mainScreen = findScreenFitsOurNeeds() else { return }
        mainWindowController = .init(screen: mainScreen, sessionStore: sessionStore)
        if isFirstOpen, !isLaunchedAtLogin, !isDemoNotifications {
            mainWindowController?.openAfterCreate = true
        }
    }

    func determineIfProcessIdentifierMatches() {
        let pid = String(NSRunningApplication.current.processIdentifier)
        let content = (try? String(contentsOf: pidFile)) ?? ""
        guard pid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else {
            NSApp.terminate(nil)
            return
        }
    }

    func makeKeyAndVisibleIfNeeded() {
        guard let controller = mainWindowController,
              let window = controller.window,
              let vm = controller.vm,
              vm.status == .opened
        else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard let controller = mainWindowController,
              let vm = controller.vm
        else { return true }
        vm.notchOpen(.click)
        return true
    }
}
