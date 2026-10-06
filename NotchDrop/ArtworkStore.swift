//
//  ArtworkStore.swift
//  NotchDrop
//
//  Les pochettes des morceaux en cours : lues une seule fois par morceau, gardées en mémoire (20 au plus).
//  Musique donne l'image ; pour Spotify on télécharge l'image à l'adresse donnée, si elle est de confiance.
//

import AppKit

final class ArtworkStore: ObservableObject {
    static let shared = ArtworkStore()

    @Published private(set) var images: [String: NSImage] = [:]

    private static let capacity = 20
    private static let downloadTimeout: TimeInterval = 8
    private let queue = DispatchQueue(label: "encoche.artwork")
    /// Sur la file : clés déjà demandées, dans l'ordre, pour ne lire chaque pochette qu'une fois.
    private var requestedKeys: [String] = []

    private init() {}

    func image(for track: NowPlaying) -> NSImage? {
        images[artworkKey(for: track)]
    }

    /// Sans effet si la pochette de ce morceau a déjà été demandée (trouvée ou non).
    func request(for track: NowPlaying) {
        let key = artworkKey(for: track)
        queue.async { [weak self] in
            guard let self, !requestedKeys.contains(key) else { return }
            requestedKeys.append(key)
            let evicted = requestedKeys.count > Self.capacity ? requestedKeys.removeFirst() : nil
            guard let image = Self.loadImage(for: track.source) else {
                publish(nil, for: key, evicting: evicted)
                return
            }
            publish(image, for: key, evicting: evicted)
        }
    }

    private func publish(_ image: NSImage?, for key: String, evicting evicted: String?) {
        DispatchQueue.main.async { [self] in
            if let evicted { images.removeValue(forKey: evicted) }
            if let image { images[key] = image }
        }
    }

    private static func loadImage(for source: MusicSource) -> NSImage? {
        let result = AppleScriptRunner.run(artworkReadScript(for: source))
        guard let descriptor = result.descriptor else { return nil }
        switch source {
        case .music:
            let data = descriptor.data
            return isAcceptableArtworkSize(data.count) ? NSImage(data: data) : nil
        case .spotify:
            guard let text = descriptor.stringValue, let url = URL(string: text), isTrustedArtworkURL(url) else { return nil }
            return download(url)
        }
    }

    private static func download(_ url: URL) -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: downloadTimeout)
        request.httpMethod = "GET"
        let semaphore = DispatchSemaphore(value: 0)
        var data: Data?
        URLSession.shared.dataTask(with: request) { received, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { data = received }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + downloadTimeout + 2)
        guard let data, isAcceptableArtworkSize(data.count) else { return nil }
        return NSImage(data: data)
    }
}
