//
//  BrowserBridgeServer.swift
//  NotchDrop
//
//  Le pont avec l'extension Chrome : l'hôte de messagerie native se connecte à un socket Unix privé
//  (voir UnixSocketListener) et échange des lignes JSON. Un seul client à la fois : le plus récent remplace l'ancien.
//

import Foundation

final class BrowserBridgeServer {
    static var defaultSocketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Encoche/browser.sock")
    }

    private let listener: UnixSocketListener
    private let onTabs: ([BrowserTab]) -> Void
    private let onDisconnect: () -> Void
    private let lock = NSLock()
    private var currentClient: Int32 = -1

    /// `onTabs` et `onDisconnect` sont appelés sur un fil quelconque : à l'appelant de repasser sur le fil principal.
    init(
        socketURL: URL = BrowserBridgeServer.defaultSocketURL,
        onTabs: @escaping ([BrowserTab]) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self.onTabs = onTabs
        self.onDisconnect = onDisconnect
        var accept: ((Int32) -> Void)?
        listener = UnixSocketListener(socketURL: socketURL, label: "encoche.browser.accept") { accept?($0) }
        accept = { [weak self] client in self?.adopt(client) }
    }

    func start() throws {
        try listener.start()
    }

    func stop() {
        listener.stop()
        lock.lock()
        if currentClient >= 0 { shutdown(currentClient, SHUT_RDWR) }
        lock.unlock()
    }

    /// Demande à l'extension de régler le volume d'un onglet. Sans extension connectée, ne fait rien.
    func setVolume(tabID: Int, volume: Int) {
        let line = BrowserMessage.setVolumeLine(tabID: tabID, volume: volume)
        lock.lock()
        defer { lock.unlock() }
        guard currentClient >= 0 else { return }
        line.withUnsafeBytes { buffer in
            _ = send(currentClient, buffer.baseAddress, buffer.count, 0)
        }
    }

    private func adopt(_ client: Int32) {
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)

        lock.lock()
        // Le plus récent remplace l'ancien : on réveille l'ancien lecteur, qui ferme son descripteur et s'en va.
        if currentClient >= 0 { shutdown(currentClient, SHUT_RDWR) }
        currentClient = client
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [self] in
            readLines(from: client)
        }
    }

    private func readLines(from client: Int32) {
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        reading: while true {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            pending.append(buffer, count: count)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex ..< newline]
                pending = Data(pending[pending.index(after: newline)...])
                if let tabs = BrowserMessage.parseTabs(Data(line)) { onTabs(tabs) }
            }
            // Une ligne qui n'en finit pas : l'autre bout n'est pas notre hôte.
            if pending.count > BrowserMessage.maxLineBytes { break reading }
        }

        lock.lock()
        let wasCurrent = currentClient == client
        if wasCurrent { currentClient = -1 }
        lock.unlock()
        close(client)
        if wasCurrent { onDisconnect() }
    }
}
