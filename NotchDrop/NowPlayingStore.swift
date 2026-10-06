//
//  NowPlayingStore.swift
//  NotchDrop
//
//  Lit ce qui joue dans Musique et Spotify (AppleScript) et leur envoie précédent / pause / suivant.
//  Une application qui ne tourne pas n'est jamais interrogée : AppleScript la lancerait.
//

import AppKit
import Combine

final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()

    /// Une entrée par application de musique ouverte, avec son volume et son titre s'il y en a un.
    @Published private(set) var sources: [PlayerSource] = []
    /// La source que l'utilisateur a choisie dans l'écran Lecteur (nil : celle qui joue).
    @Published var selectedSource: MusicSource?
    /// Le volume de la sortie son du Mac ; nil si la sortie n'a pas de réglage de volume.
    @Published private(set) var systemVolume: Int?
    /// Applications dont macOS a refusé le contrôle (Réglages Système > Confidentialité > Automatisation).
    @Published private(set) var blockedSources: Set<MusicSource> = []

    var controlled: PlayerSource? { controlledSource(selected: selectedSource, among: sources) }

    private static let volumeHoldSeconds: TimeInterval = 1.5
    private let queue = DispatchQueue(label: "encoche.nowplaying")
    private var timer: DispatchSourceTimer?
    /// Réglages en attente d'envoi et valeur gardée un instant après un réglage : écrits par le fil principal,
    /// lus par la file, donc sous verrou.
    private let lock = NSLock()
    private var pendingVolumes: [MusicSource: Int] = [:]
    private var volumeHolds: [MusicSource: (value: Int, until: Date)] = [:]
    private var systemVolumeHold: (value: Int, until: Date)?
    private var pendingSystemVolume: Int?
    /// Sur le fil principal : le niveau d'avant la coupure, pour le rétablir.
    private var levelBeforeMute: [MusicSource: Int] = [:]
    private var levelBeforeSystemMute: Int?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 2)
        source.setEventHandler { [weak self] in self?.refresh() }
        source.resume()
        timer = source
    }

    func send(_ command: PlayerCommand, to source: MusicSource) {
        queue.async { [weak self] in
            _ = AppleScriptRunner.run(playerCommandScript(command, for: source))
            // Le titre ou l'état change tout de suite : on ne laisse pas l'écran attendre le prochain relevé.
            self?.queue.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }
        }
    }

    /// Le curseur suit le doigt tout de suite ; seule la dernière valeur part vers l'application.
    func setVolume(_ percent: Int, for source: MusicSource) {
        let volume = clampedVolume(percent)
        sources = sources.map { $0.source == source ? PlayerSource(source: source, volume: volume, track: $0.track) : $0 }
        lock.lock()
        volumeHolds[source] = (volume, Date().addingTimeInterval(Self.volumeHoldSeconds))
        pendingVolumes[source] = volume
        lock.unlock()
        queue.async { [weak self] in self?.sendPendingVolume(for: source) }
    }

    /// Plusieurs réglages en file : le premier envoie la dernière valeur, les suivants ne trouvent plus rien à envoyer.
    private func sendPendingVolume(for source: MusicSource) {
        lock.lock()
        let latest = pendingVolumes.removeValue(forKey: source)
        lock.unlock()
        guard let latest else { return }
        _ = AppleScriptRunner.run(volumeScript(latest, for: source))
    }

    /// Même principe que pour une source : le curseur suit le doigt, seule la dernière valeur part.
    func setSystemVolume(_ percent: Int) {
        let volume = clampedVolume(percent)
        systemVolume = volume
        lock.lock()
        systemVolumeHold = (volume, Date().addingTimeInterval(Self.volumeHoldSeconds))
        pendingSystemVolume = volume
        lock.unlock()
        queue.async { [weak self] in self?.sendPendingSystemVolume() }
    }

    func toggleSystemMute() {
        guard let current = systemVolume else { return }
        let result = togglingMute(currentVolume: current, restoreTo: levelBeforeSystemMute)
        levelBeforeSystemMute = result.restoreTo
        setSystemVolume(result.volume)
    }

    private func sendPendingSystemVolume() {
        lock.lock()
        let latest = pendingSystemVolume
        pendingSystemVolume = nil
        lock.unlock()
        guard let latest else { return }
        _ = AppleScriptRunner.run(systemVolumeScript(latest))
    }

    func toggleMute(for source: MusicSource) {
        guard let current = sources.first(where: { $0.source == source })?.volume else { return }
        let result = togglingMute(currentVolume: current, restoreTo: levelBeforeMute[source])
        levelBeforeMute[source] = result.restoreTo
        setVolume(result.volume, for: source)
    }

    private func refresh() {
        var found: [PlayerSource] = []
        var blocked: Set<MusicSource> = []
        let now = Date()
        for source in MusicSource.allCases where Self.isRunning(source) {
            let result = AppleScriptRunner.run(nowPlayingReadScript(for: source))
            if result.errorNumber == AppleScriptRunner.notAuthorizedErrorNumber { blocked.insert(source) }
            guard let output = result.descriptor?.stringValue, let read = PlayerSource.parse(output, source: source) else { continue }
            if let track = read.track { ArtworkStore.shared.request(for: track) }
            lock.lock()
            let hold = volumeHolds[source]
            lock.unlock()
            let volume = reconciledVolume(read: read.volume, local: hold?.value, holdUntil: hold?.until, now: now)
            found.append(PlayerSource(source: source, volume: volume, track: read.track))
        }
        let system = readSystemVolume(now: now)
        DispatchQueue.main.async { [self] in
            if systemVolume != system { systemVolume = system }
            if sources != found { sources = found }
            if blockedSources != blocked { blockedSources = blocked }
        }
    }

    private func readSystemVolume(now: Date) -> Int? {
        guard let read = parseSystemVolume(AppleScriptRunner.run(systemVolumeReadScript).descriptor?.stringValue) else { return nil }
        lock.lock()
        let hold = systemVolumeHold
        lock.unlock()
        return reconciledVolume(read: read, local: hold?.value, holdUntil: hold?.until, now: now)
    }

    private static func isRunning(_ source: MusicSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }
}

/// L'icône réelle d'une application installée, lue sur le Mac (rien n'est embarqué), comme le logo d'AirDrop.
enum AppIcon {
    static func image(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
