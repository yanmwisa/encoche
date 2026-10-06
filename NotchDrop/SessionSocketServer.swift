//
//  SessionSocketServer.swift
//  NotchDrop
//
//  Reçoit les événements du script de hook par un socket Unix privé (voir UnixSocketListener) :
//  une connexion par événement, lecture bornée.
//

import Foundation

final class SessionSocketServer {
    typealias StartError = UnixSocketListener.StartError

    static var defaultSocketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Encoche/sessions.sock")
    }

    private let listener: UnixSocketListener

    /// `onEvent` est appelé sur un fil quelconque : à l'appelant de repasser sur le fil principal.
    init(socketURL: URL = SessionSocketServer.defaultSocketURL, onEvent: @escaping (SessionEvent) -> Void) {
        listener = UnixSocketListener(socketURL: socketURL, label: "encoche.sessions.accept") { client in
            DispatchQueue.global(qos: .utility).async {
                Self.readEvent(from: client, deliverTo: onEvent)
            }
        }
    }

    func start() throws {
        try listener.start()
    }

    func stop() {
        listener.stop()
    }

    private static func readEvent(from client: Int32, deliverTo onEvent: (SessionEvent) -> Void) {
        defer { close(client) }

        // Un client lent ne bloque personne plus d'une seconde.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while received.count <= SessionEvent.maxPayloadBytes {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            received.append(buffer, count: count)
        }

        guard let event = SessionEvent.decode(received) else { return }
        onEvent(event)
    }
}
