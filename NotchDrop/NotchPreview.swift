//
//  NotchPreview.swift
//  NotchDrop
//
//  Rend les vues de l'encoche (onglets, sessions, AirDrop) dans un fichier PNG, sans rien afficher à l'écran :
//  NotchDrop --render-preview /chemin/apercu.png
//

import AppKit
import SwiftUI

enum NotchPreview {
    private static let now = Date()

    private static func sample(_ id: String, _ phase: SessionPhase, _ detail: String, age: TimeInterval) -> AgentSession {
        AgentSession(id: id, name: id, phase: phase, detail: detail, updatedAt: now.addingTimeInterval(-age), hostPID: 1)
    }

    private static let sessions: [AgentSession] = [
        sample("my-project", .approval, "git push origin feature/search", age: 5),
        sample("notes", .question, "Waiting for your answer", age: 30),
        sample("weather-app", .working, "Working", age: 8),
        sample("website", .done, "Finished", age: 200),
    ]


    private static var previewSources: [PlayerSource] {
        [
            PlayerSource(source: .music, volume: 55, track: nil),
            PlayerSource(source: .spotify, volume: 40, track: NowPlaying(source: .spotify, title: "Lofi for coding", artist: "Playlist", isPlaying: true)),
        ]
    }

    private static let playingTrack = NowPlaying(source: .music, title: "Night Shift", artist: "Southern Stars", isPlaying: true)

    private static var finishedSession: AgentSession {
        var session = sample("website", .done, "Finished", age: 3)
        session.hasUnseenFinish = true
        return session
    }

    private static var sheet: some View {
        let notchWidth: CGFloat = 190
        let earWidth = NotchViewModel.sessionEarWidth
        let alone = describeNotch([sessions[0]])
        let several = describeNotch(Array(sessions.prefix(2)))
        let full = describeNotch(sessions)

        return VStack(alignment: .leading, spacing: 24) {
            sheetBlock("Tab bar: one tab per screen, the selected one highlighted", height: 150) {
                VStack(spacing: 10) {
                    ForEach([NotchViewModel.ContentType.normal, .sessions, .player, .menu], id: \.self) { selection in
                        NotchTabBar(selection: selection, waitingCount: 2, onSelect: { _ in })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(width: 568)
            }
            sheetBlock("Open notch: Sessions", height: 184) {
                openedNotch(selection: .sessions) {
                    SessionsListView(summary: full, onGoTo: { _ in }, isScrollable: false)
                }
            }
            sheetBlock("Open notch: a permission to give", height: 184) {
                openedNotch(selection: .sessions) {
                    ApprovalCardView(
                        sessionName: "my-project", tool: "Bash", summary: "git push origin feature/search",
                        position: "1 of 2", showsPosition: true, onAnswer: { _ in }
                    )
                }
            }
            sheetBlock("Open notch: next steps to pick", height: 184) {
                openedNotch(selection: .sessions) {
                    NextStepsCardView(
                        sessionName: "weather-app",
                        labels: ["Run the tests", "Update the changelog", "Rerun the test suite"],
                        position: "", showsPosition: false, onLaunch: { _ in }, initiallyPicked: [2, 0]
                    )
                }
            }
            sheetBlock("Open notch: Player", height: 184) {
                openedNotch(selection: .player) {
                    NotchPlayerContent(
                        sources: [previewSources[1]], controlled: previewSources[1], artwork: { _ in nil }, tabs: [BrowserTab(id: 12, title: "Focus mix, 2 hours", host: "www.youtube.com", volume: 70)], systemVolume: 69, isBlocked: false,
                        onCommand: { _, _ in }, onVolume: { _, _ in }, onMute: { _ in }, onSelect: { _ in }, onTabVolume: { _, _ in },
                        onSystemVolume: { _ in }, onSystemMute: {}
                    )
                }
            }
            sheetBlock("Ears: music is playing", height: 32) {
                NowPlayingEarsView(track: playingTrack, notchWidth: notchWidth, earWidth: earWidth, height: 32)
            }
            sheetBlock("The real AirDrop logo, as the system provides it", height: 70) {
                HStack(spacing: 14) {
                    ShareView.ShareType.airdrop.icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                    Text("AirDrop").font(.system(.headline, design: .rounded))
                }
                .padding(20)
            }
            sheetBlock("One session waiting", height: 32) {
                if let ears = alone.ears {
                    SessionEarsView(ears: ears, notchWidth: notchWidth, earWidth: earWidth, height: 32)
                }
            }
            sheetBlock("One session finished its turn", height: 32) {
                if let ears = describeNotch([finishedSession]).ears {
                    SessionEarsView(ears: ears, notchWidth: notchWidth, earWidth: earWidth, height: 32)
                }
            }
            sheetBlock("Two sessions waiting", height: 32) {
                if let ears = several.ears {
                    SessionEarsView(ears: ears, notchWidth: notchWidth, earWidth: earWidth, height: 32)
                }
            }
            sheetBlock("List (open notch)", height: 230) {
                SessionsListView(summary: full, onGoTo: { _ in }, isScrollable: false)
                    .padding(16)
                    .frame(width: 568, height: 230)
            }
            sheetBlock("Empty list", height: 90) {
                SessionsListView(summary: describeNotch([]), onGoTo: { _ in })
                    .padding(16)
                    .frame(width: 568, height: 90)
            }
        }
        .padding(24)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    /// La mise en page de l'encoche ouverte : bande de la caméra vide, barre d'onglets, puis l'écran choisi.
    private static func openedNotch(
        selection: NotchViewModel.ContentType,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            NotchTabBar(selection: selection, waitingCount: 2, onSelect: { _ in })
            // 184 - 36 (bande de la caméra) - 16 (bas) - 28 (onglets) - 16 (écart) : ce qui reste à l'écran choisi.
            content()
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: 88, alignment: .top)
                .clipped()
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 36)
        .frame(width: 600, height: 184)
        .clipped()
    }

    private static func sheetBlock(_ title: String, height: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black))
                .frame(height: height, alignment: .top)
        }
    }

    @MainActor
    static func render(to path: String) -> Bool {
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }
}
