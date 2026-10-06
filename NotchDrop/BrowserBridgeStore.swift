//
//  BrowserBridgeStore.swift
//  NotchDrop
//
//  Les onglets de Chrome qui jouent du son, annoncés par l'extension, et leur volume.
//  Sans l'extension, la liste reste vide et rien d'autre ne change.
//

import Foundation

final class BrowserBridgeStore: ObservableObject {
    static let shared = BrowserBridgeStore()

    @Published private(set) var tabs: [BrowserTab] = []

    private static let volumeHoldSeconds: TimeInterval = 1.5
    private var server: BrowserBridgeServer?
    /// Comme pour Musique : juste après un réglage, l'annonce suivante de Chrome peut redonner l'ancien volume.
    private var volumeHolds: [Int: (value: Int, until: Date)] = [:]

    private init() {}

    func start() {
        guard server == nil else { return }
        let bridge = BrowserBridgeServer(
            onTabs: { [weak self] tabs in DispatchQueue.main.async { self?.receive(tabs) } },
            onDisconnect: { [weak self] in DispatchQueue.main.async { self?.tabs = [] } }
        )
        do {
            try bridge.start()
            server = bridge
        } catch {
            NSLog("Encoche : pont avec Chrome impossible : \(error)")
        }
    }

    func setVolume(_ percent: Int, forTab tabID: Int) {
        let volume = clampedVolume(percent)
        volumeHolds[tabID] = (volume, Date().addingTimeInterval(Self.volumeHoldSeconds))
        tabs = tabs.map { $0.id == tabID ? BrowserTab(id: $0.id, title: $0.title, host: $0.host, volume: volume) : $0 }
        server?.setVolume(tabID: tabID, volume: volume)
    }

    private func receive(_ announced: [BrowserTab]) {
        let now = Date()
        volumeHolds = volumeHolds.filter { $0.value.until > now }
        let reconciled = announced.map { tab in
            let volume = reconciledVolume(read: tab.volume, local: volumeHolds[tab.id]?.value, holdUntil: volumeHolds[tab.id]?.until, now: now)
            return BrowserTab(id: tab.id, title: tab.title, host: tab.host, volume: volume)
        }
        let sorted = sortedForDisplay(reconciled)
        if sorted != tabs { tabs = sorted }
    }
}
