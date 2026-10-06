//
//  UnixSocketListener.swift
//  NotchDrop
//
//  Une écoute sur un socket Unix privé : dossier en 0700, socket en 0600, et le fichier n'est effacé à l'arrêt
//  que s'il est toujours celui que cette instance a créé. Chaque connexion est remise à l'appelant, qui la ferme.
//

import Foundation

final class UnixSocketListener {
    enum StartError: Error {
        case pathTooLong(Int)
        case systemCall(name: String, errorCode: Int32)
    }

    private let socketURL: URL
    private let onClient: (Int32) -> Void
    private var listeningDescriptor: Int32 = -1
    /// Identité du fichier socket créé par cette instance : une instance plus récente peut l'avoir remplacé.
    private var boundFileIdentity: (device: dev_t, inode: ino_t)?
    private var acceptSource: DispatchSourceRead?
    private let acceptQueue: DispatchQueue

    /// `onClient` est appelé sur la file d'acceptation avec le descripteur de la connexion, à fermer par l'appelant.
    init(socketURL: URL, label: String, onClient: @escaping (Int32) -> Void) {
        self.socketURL = socketURL
        self.onClient = onClient
        acceptQueue = DispatchQueue(label: label)
    }

    deinit {
        stop()
    }

    func start() throws {
        guard acceptSource == nil else { return }

        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketURL.path.utf8CString.map { UInt8(bitPattern: $0) }
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else { throw StartError.pathTooLong(capacity - 1) }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        // Reste d'une exécution précédente interrompue.
        unlink(socketURL.path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw StartError.systemCall(name: "socket", errorCode: errno) }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(descriptor)
            throw StartError.systemCall(name: "bind", errorCode: code)
        }
        chmod(socketURL.path, 0o600)
        boundFileIdentity = currentFileIdentity()

        guard listen(descriptor, 16) == 0 else {
            let code = errno
            close(descriptor)
            removeSocketFileIfStillOurs()
            throw StartError.systemCall(name: "listen", errorCode: code)
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)

        listeningDescriptor = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        guard listeningDescriptor >= 0 else { return }
        close(listeningDescriptor)
        listeningDescriptor = -1
        removeSocketFileIfStillOurs()
    }

    private func currentFileIdentity() -> (device: dev_t, inode: ino_t)? {
        var info = stat()
        guard stat(socketURL.path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    /// Une nouvelle instance de l'app remplace le socket puis arrête l'ancienne : l'ancienne ne doit pas effacer celui de la nouvelle.
    private func removeSocketFileIfStillOurs() {
        defer { boundFileIdentity = nil }
        guard let bound = boundFileIdentity, let current = currentFileIdentity(),
              bound.device == current.device, bound.inode == current.inode
        else { return }
        unlink(socketURL.path)
    }

    private func acceptPendingConnections() {
        while true {
            let client = accept(listeningDescriptor, nil, nil)
            guard client >= 0 else { return }
            onClient(client)
        }
    }
}
