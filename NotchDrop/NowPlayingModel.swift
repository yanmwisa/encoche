//
//  NowPlayingModel.swift
//  NotchDrop
//
//  Ce qui joue dans Musique ou Spotify, et ce que l'encoche en montre : état et règles, sans effet de bord.
//  Ce fichier n'importe que Foundation pour pouvoir être testé seul.
//

import Foundation

enum MusicSource: String, CaseIterable, Equatable {
    case music
    case spotify

    var displayName: String {
        switch self {
        case .music: "Musique"
        case .spotify: "Spotify"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Le nom d'application attendu par AppleScript.
    var scriptName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

struct NowPlaying: Equatable {
    let source: MusicSource
    let title: String
    let artist: String
    let isPlaying: Bool
}

enum PlayerCommand: String, Equatable {
    case playPause = "playpause"
    case next = "next track"
    case previous = "previous track"
}

extension NowPlaying {
    static let fieldSeparator: Character = "\u{1F}"
    static let maxTextLength = 120

    /// La réponse du script : « playing » ou « paused », le titre, l'artiste, séparés par le caractère 31.
    /// Arrêté, vide, ou toute autre forme : rien ne joue.
    static func parse(_ output: String, source: MusicSource) -> NowPlaying? {
        let fields = output.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3 else { return nil }
        let state = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == "playing" || state == "paused" else { return nil }
        let title = SessionEvent.cleaned(fields[1], max: maxTextLength)
        guard !title.isEmpty else { return nil }
        return NowPlaying(
            source: source,
            title: title,
            artist: SessionEvent.cleaned(fields[2], max: maxTextLength),
            isPlaying: state == "playing"
        )
    }
}

/// Une application de musique ouverte : son volume (0 à 100) et, s'il y en a un, son titre en cours ou en pause.
/// Une application ouverte sans titre garde tout de même son curseur de volume.
struct PlayerSource: Equatable {
    let source: MusicSource
    let volume: Int
    let track: NowPlaying?

    /// La réponse du script de lecture : le volume, puis « état, titre, artiste », séparés par le caractère 31.
    static func parse(_ output: String, source: MusicSource) -> PlayerSource? {
        guard let separatorIndex = output.firstIndex(of: NowPlaying.fieldSeparator),
              let volume = Int(output[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)),
              (0 ... 100).contains(volume)
        else { return nil }
        let rest = String(output[output.index(after: separatorIndex)...])
        return PlayerSource(source: source, volume: volume, track: NowPlaying.parse(rest, source: source))
    }
}

func clampedVolume(_ value: Int) -> Int {
    min(max(value, 0), 100)
}

/// La source que l'écran Lecteur pilote : celle que l'utilisateur a choisie si elle est ouverte,
/// sinon celle qui joue, sinon la première ouverte.
func controlledSource(selected: MusicSource?, among sources: [PlayerSource]) -> PlayerSource? {
    sources.first { $0.source == selected }
        ?? sources.first { $0.track?.isPlaying == true }
        ?? sources.first
}

/// Juste après un réglage, le relevé de l'application peut encore donner l'ancienne valeur : tant que le maintien
/// court, on garde celle que l'utilisateur vient de choisir, sinon le curseur sauterait en arrière.
func reconciledVolume(read: Int, local: Int?, holdUntil: Date?, now: Date) -> Int {
    guard let local, let holdUntil, now < holdUntil else { return read }
    return local
}

/// Couper met le volume à 0 en gardant l'ancien niveau ; rétablir le remet (50 si on ne le connaît pas).
func togglingMute(currentVolume: Int, restoreTo: Int?) -> (volume: Int, restoreTo: Int?) {
    currentVolume > 0 ? (0, currentVolume) : (restoreTo ?? 50, nil)
}

/// Ce que l'écran Lecteur pilote : ce qui joue, sinon ce qui est en pause. À égalité, Musique avant Spotify.
func currentTrack(among candidates: [NowPlaying]) -> NowPlaying? {
    candidates.first(where: \.isPlaying) ?? candidates.first
}

/// Les oreilles montrent d'abord ce qui attend l'utilisateur dans une session, sinon la musique qui joue.
/// Une musique en pause n'occupe pas l'encoche.
enum EarsContent: Equatable {
    case session(SessionEars)
    case nowPlaying(NowPlaying)
}

func earsContent(sessionEars: SessionEars?, nowPlaying: NowPlaying?) -> EarsContent? {
    if let sessionEars { return .session(sessionEars) }
    if let nowPlaying, nowPlaying.isPlaying { return .nowPlaying(nowPlaying) }
    return nil
}

/// Le script AppleScript qui lit l'état de l'application. Il n'est jamais lancé si l'application ne tourne pas :
/// « tell application » la démarrerait.
func nowPlayingReadScript(for source: MusicSource) -> String {
    """
    tell application "\(source.scriptName)"
        set level to (sound volume as text)
        if player state is stopped then return level & (ASCII character 31) & "stopped" & (ASCII character 31) & (ASCII character 31)
        return level & (ASCII character 31) & (player state as text) & (ASCII character 31) & (name of current track) & (ASCII character 31) & (artist of current track)
    end tell
    """
}

func playerCommandScript(_ command: PlayerCommand, for source: MusicSource) -> String {
    "tell application \"\(source.scriptName)\" to \(command.rawValue)"
}

func volumeScript(_ percent: Int, for source: MusicSource) -> String {
    "tell application \"\(source.scriptName)\" to set sound volume to \(clampedVolume(percent))"
}

// MARK: - Pochette du morceau

/// Un morceau, une pochette : la clé ne change que quand le morceau change.
func artworkKey(for track: NowPlaying) -> String {
    [track.source.rawValue, track.title, track.artist].joined(separator: "\u{1F}")
}

/// Musique donne l'image elle-même ; Spotify donne l'adresse de l'image.
func artworkReadScript(for source: MusicSource) -> String {
    switch source {
    case .music: "tell application \"Music\" to return raw data of artwork 1 of current track"
    case .spotify: "tell application \"Spotify\" to return artwork url of current track"
    }
}

/// L'adresse donnée par Spotify n'est suivie que si elle mène à son propre réseau d'images, en https :
/// une adresse venue d'ailleurs est refusée.
func isTrustedArtworkURL(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return host == "scdn.co" || host.hasSuffix(".scdn.co")
}

let maxArtworkBytes = 5 * 1024 * 1024

func isAcceptableArtworkSize(_ byteCount: Int) -> Bool {
    (1 ... maxArtworkBytes).contains(byteCount)
}

// MARK: - Volume du Mac

let systemVolumeReadScript = "output volume of (get volume settings)"

func systemVolumeScript(_ percent: Int) -> String {
    "set volume output volume \(clampedVolume(percent))"
}

/// Le volume de la sortie son du Mac, de 0 à 100. Une sortie sans réglage de volume (HDMI, certains casques)
/// répond « missing value » : la ligne « Mac » n'est alors pas montrée.
func parseSystemVolume(_ output: String?) -> Int? {
    guard let output, let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)), (0 ... 100).contains(value) else { return nil }
    return value
}

