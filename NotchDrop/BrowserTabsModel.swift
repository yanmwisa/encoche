//
//  BrowserTabsModel.swift
//  NotchDrop
//
//  Les onglets de Chrome qui jouent du son, tels que l'extension les annonce, et l'ordre de régler leur volume :
//  analyse stricte des messages, sans effet de bord. Ce fichier n'importe que Foundation pour pouvoir être testé seul.
//

import Foundation

struct BrowserTab: Equatable, Identifiable {
    /// Numéro de l'onglet dans Chrome.
    let id: Int
    let title: String
    let host: String
    /// Volume réglé par l'utilisateur, de 0 à 100 (100 : la page n'est pas touchée).
    let volume: Int
}

enum BrowserMessage {
    static let maxLineBytes = 64 * 1024
    static let maxTabs = 8

    /// Une ligne JSON de l'extension : `{"type":"tabs","tabs":[{"id":12,"title":"…","host":"youtube.com","volume":70}]}`.
    /// Tout ce qui n'a pas cette forme est refusé : un autre programme de l'utilisateur peut écrire sur le socket.
    static func parseTabs(_ line: Data) -> [BrowserTab]? {
        guard line.count <= maxLineBytes,
              let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              root["type"] as? String == "tabs",
              let entries = root["tabs"] as? [[String: Any]]
        else { return nil }
        return entries.prefix(maxTabs).compactMap { entry in
            guard let id = entry["id"] as? Int, id >= 0 else { return nil }
            return BrowserTab(
                id: id,
                title: SessionEvent.cleaned(entry["title"] as? String ?? "", max: 80),
                host: SessionEvent.cleaned(entry["host"] as? String ?? "", max: 100),
                volume: clampedVolume(entry["volume"] as? Int ?? 100)
            )
        }
    }

    /// L'ordre envoyé à l'extension, en une ligne.
    static func setVolumeLine(tabID: Int, volume: Int) -> Data {
        let object: [String: Any] = ["type": "setVolume", "tabId": tabID, "volume": clampedVolume(volume)]
        let json = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return json + Data("\n".utf8)
    }
}

/// Le nom d'un site pour l'écran Lecteur : « www.youtube.com » devient « YouTube ».
func browserHostLabel(_ host: String) -> String {
    let known = ["youtube": "YouTube", "spotify": "Spotify", "soundcloud": "SoundCloud", "deezer": "Deezer", "twitch": "Twitch", "netflix": "Netflix"]
    let parts = host.lowercased().split(separator: ".").map(String.init).filter { $0 != "www" }
    // « open.spotify.com » : le nom est l'avant-dernier morceau ; « youtube.com » aussi.
    guard parts.count >= 2 else { return parts.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Onglet" }
    let name = parts[parts.count - 2]
    return known[name] ?? (name.prefix(1).uppercased() + name.dropFirst())
}

/// Les onglets triés pour l'affichage : le même ordre d'un relevé à l'autre, sans qu'une ligne saute.
func sortedForDisplay(_ tabs: [BrowserTab]) -> [BrowserTab] {
    tabs.sorted { $0.id < $1.id }
}
