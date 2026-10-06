//
//  NotchPlayerView.swift
//  NotchDrop
//
//  L'écran Lecteur et la barre des oreilles : ce qui joue dans Musique ou Spotify, avec le vrai logo de l'application.
//

import AppKit
import SwiftUI

/// Le vrai logo d'une application installée, sinon une note de musique.
struct AppIconView: View {
    let bundleIdentifier: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let icon = AppIcon.image(forBundleIdentifier: bundleIdentifier) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "music.note").resizable().padding(size * 0.2)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SourceIconView: View {
    let source: MusicSource
    var size: CGFloat = 24

    var body: some View {
        AppIconView(bundleIdentifier: source.bundleIdentifier, size: size)
    }
}

/// L'encoche fermée, élargie : le logo et le titre à gauche, l'artiste à droite, la caméra au milieu.
struct NowPlayingEarsView: View {
    let track: NowPlaying
    let notchWidth: CGFloat
    let earWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                SourceIconView(source: track.source, size: 18)
                Text(track.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: earWidth - 12, alignment: .leading)
            Spacer(minLength: notchWidth)
            Text(track.artist)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: earWidth - 12, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(width: notchWidth + earWidth * 2, height: height)
    }
}

/// L'écran Lecteur, lu depuis le magasin partagé.
struct NotchPlayerView: View {
    @ObservedObject private var store = NowPlayingStore.shared
    @ObservedObject private var artwork = ArtworkStore.shared
    @ObservedObject private var browser = BrowserBridgeStore.shared

    var body: some View {
        NotchPlayerContent(
            sources: store.sources,
            controlled: store.controlled,
            artwork: { artwork.image(for: $0) },
            tabs: browser.tabs,
            systemVolume: store.systemVolume,
            isBlocked: !store.blockedSources.isEmpty,
            onCommand: { command, source in store.send(command, to: source) },
            onVolume: { source, percent in store.setVolume(percent, for: source) },
            onMute: { store.toggleMute(for: $0) },
            onSelect: { store.selectedSource = $0 },
            onTabVolume: { tabID, percent in browser.setVolume(percent, forTab: tabID) },
            onSystemVolume: { store.setSystemVolume($0) },
            onSystemMute: { store.toggleSystemMute() }
        )
    }
}

/// À gauche ce que la source pilotée joue, à droite un curseur de volume par source ouverte.
struct NotchPlayerContent: View {
    let sources: [PlayerSource]
    let controlled: PlayerSource?
    /// La vraie pochette du morceau si on l'a ; sinon le logo de l'application.
    let artwork: (NowPlaying) -> NSImage?
    /// Les onglets de Chrome qui jouent du son (vide sans l'extension).
    let tabs: [BrowserTab]
    /// Le volume du Mac (nil si la sortie n'a pas de réglage).
    let systemVolume: Int?
    let isBlocked: Bool
    let onCommand: (PlayerCommand, MusicSource) -> Void
    let onVolume: (MusicSource, Int) -> Void
    let onMute: (MusicSource) -> Void
    let onSelect: (MusicSource) -> Void
    let onTabVolume: (Int, Int) -> Void
    let onSystemVolume: (Int) -> Void
    let onSystemMute: () -> Void

    var body: some View {
        if controlled != nil || !tabs.isEmpty || systemVolume != nil {
            HStack(spacing: 16) {
                if let controlled {
                    nowPlaying(controlled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    nothingPlaying
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                mixer
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            empty
        }
    }

    private func nowPlaying(_ current: PlayerSource) -> some View {
        HStack(spacing: 10) {
            cover(for: current)
            VStack(alignment: .leading, spacing: 2) {
                Text(current.track?.title ?? "Rien en lecture")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(current.track.map { $0.artist.isEmpty ? current.source.displayName : $0.artist } ?? current.source.displayName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    controlButton("backward.fill") { onCommand(.previous, current.source) }
                    controlButton(current.track?.isPlaying == true ? "pause.fill" : "play.fill", isMain: true) { onCommand(.playPause, current.source) }
                    controlButton("forward.fill") { onCommand(.next, current.source) }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func cover(for current: PlayerSource) -> some View {
        if let track = current.track, let image = artwork(track) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        } else {
            SourceIconView(source: current.source, size: 46)
        }
    }

    /// Une ligne par application de musique ouverte, puis une par onglet de Chrome qui joue du son ;
    /// au-delà de trois lignes, la liste défile.
    private var mixer: some View {
        let rows = VStack(spacing: 3) {
            if let systemVolume {
                systemRow(systemVolume)
            }
            ForEach(sources, id: \.source) { entry in
                volumeRow(entry)
            }
            ForEach(tabs) { tab in
                tabRow(tab)
            }
        }
        return Group {
            if sources.count + tabs.count + (systemVolume == nil ? 0 : 1) > 3 {
                ScrollView { rows }.scrollIndicators(.never)
            } else {
                rows
            }
        }
    }

    /// Le son du Mac : toujours là, en tête, pour baisser l'ensemble sans toucher aux réglages de chaque source.
    private func systemRow(_ volume: Int) -> some View {
        HStack(spacing: 8) {
            Button(action: onSystemMute) {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "laptopcomputer")
                    .font(.system(size: 13))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white.opacity(volume == 0 ? 0.4 : 0.9))
            }
            .buttonStyle(.plain)
            .help(volume == 0 ? "Rétablir le son du Mac" : "Couper le son du Mac")
            Text("Mac")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 66, alignment: .leading)
            Slider(
                value: Binding(get: { Double(volume) }, set: { onSystemVolume(Int($0.rounded())) }),
                in: 0 ... 100
            )
            .controlSize(.small)
            Text("\(volume)%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
    }

    /// À gauche, quand aucune application de musique n'est ouverte : un mot, pour ne pas laisser un trou.
    private var nothingPlaying: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isBlocked ? "Contrôle refusé" : "Aucune musique")
                .font(.system(size: 13, weight: .bold))
            Text(isBlocked ? "Réglages Système > Automatisation" : "Ouvrez Musique ou Spotify")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func tabRow(_ tab: BrowserTab) -> some View {
        HStack(spacing: 8) {
            AppIconView(bundleIdentifier: "com.google.Chrome", size: 22)
            Text(browserHostLabel(tab.host))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(width: 66, alignment: .leading)
                .help(tab.title)
            Slider(
                value: Binding(get: { Double(tab.volume) }, set: { onTabVolume(tab.id, Int($0.rounded())) }),
                in: 0 ... 100
            )
            .controlSize(.small)
            Text("\(tab.volume)%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
    }

    private func volumeRow(_ entry: PlayerSource) -> some View {
        let isControlled = entry.source == controlled?.source
        return HStack(spacing: 8) {
            Button { onMute(entry.source) } label: {
                SourceIconView(source: entry.source, size: 22)
                    .opacity(entry.volume == 0 ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .help(entry.volume == 0 ? "Rétablir le son" : "Couper le son")
            Button { onSelect(entry.source) } label: {
                Text(entry.source.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 66, alignment: .leading)
            }
            .buttonStyle(.plain)
            Slider(
                value: Binding(get: { Double(entry.volume) }, set: { onVolume(entry.source, Int($0.rounded())) }),
                in: 0 ... 100
            )
            .controlSize(.small)
            Text("\(entry.volume)%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isControlled ? .white.opacity(0.09) : .clear))
    }

    private func controlButton(_ symbol: String, isMain: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: isMain ? 38 : 28, height: 24)
                .foregroundStyle(isMain ? Color.black : Color.white)
                .background(Capsule().fill(isMain ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text(isBlocked ? "macOS a refusé le contrôle de Musique ou Spotify." : "Aucune source ouverte.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(isBlocked
                ? "Autorisez-le dans Réglages Système > Confidentialité > Automatisation."
                : "Ouvrez Musique ou Spotify : le titre et le volume apparaissent ici.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
