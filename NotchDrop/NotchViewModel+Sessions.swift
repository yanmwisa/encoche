//
//  NotchViewModel+Sessions.swift
//  NotchDrop
//
//  Comportement des sessions dans l'encoche : oreilles quand une session attend, liste, « Y aller ».
//

import Cocoa
import Combine
import SwiftUI

extension NotchViewModel {
    /// Largeur de chaque oreille, de part et d'autre de l'encoche matérielle.
    static let sessionEarWidth: CGFloat = 120

    var sessionAlertSize: CGSize {
        .init(
            width: deviceNotchRect.width + 2 * Self.sessionEarWidth,
            height: deviceNotchRect.height
        )
    }

    var sessionAlertRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - sessionAlertSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - sessionAlertSize.height,
            width: sessionAlertSize.width,
            height: sessionAlertSize.height
        )
    }

    /// Reçoit l'état du magasin partagé et le garde à jour dans la vue.
    func observeSessionStore() {
        sessionStore.$sessions
            .map(describeNotch)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                self?.updateSessionSummary(summary)
            }
            .store(in: &cancellables)
    }

    /// Ouvrir l'écran Sessions, c'est voir les fins de tour : la pastille « Terminé » s'efface.
    func observeFinishAcknowledgement() {
        Publishers.CombineLatest($status, $contentType)
            .filter { $0 == .opened && $1 == .sessions }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sessionStore.acknowledgeFinishes()
            }
            .store(in: &cancellables)
    }

    func observeNowPlaying() {
        NowPlayingStore.shared.$sources
            .map { currentTrack(among: $0.compactMap(\.track)) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.updateNowPlaying(track)
            }
            .store(in: &cancellables)
    }

    /// Un clic sur les oreilles ouvre ce qu'elles montraient : les sessions, ou le Lecteur quand c'était la musique.
    func openAlertTarget() {
        if sessionSummary.ears != nil {
            openSessions()
        } else {
            notchOpen(.click)
            contentType = .player
        }
    }

    func observeRequests() {
        sessionStore.$requests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in
                self?.updatePendingRequests(requests)
            }
            .store(in: &cancellables)
    }

    /// Renvoie la réponse à la session qui attend, puis referme l'encoche s'il ne reste plus rien à décider.
    func answerRequest(_ request: PendingRequest, _ reply: RequestReply) {
        // Faux si la session a déjà été servie ailleurs ou si le délai est passé : la demande disparaît dans les deux cas.
        if !RequestReplyChannel.send(reply, replyID: request.replyID) {
            NSLog("Encoche : réponse non remise (délai passé ou session déjà servie)")
        }
        sessionStore.removeRequest(request.replyID)
        if sessionStore.requests.isEmpty { notchClose() }
    }

    /// Les oreilles apparaissent tant qu'une session attend, sans jamais recouvrir un panneau ouvert ou une notification.
    func refreshSessionAlert() {
        let needsAlert = currentEars != nil
        switch status {
        case .closed:
            if needsAlert { notchSessionAlert() }
        case .sessionAlert:
            if !needsAlert { notchClose() }
        case .opened, .popping, .notification:
            break
        }
    }

    func openSessions() {
        notchOpen(.click)
        contentType = .sessions
    }

    /// Ouvre la session cliquée dans l'application Claude ; sans correspondance (terminal, session inconnue
    /// de l'application), active seulement l'application qui l'héberge.
    func goToSession(_ session: AgentSession) {
        if let url = desktopSessionURL(forCLISession: session.id, metadata: Self.desktopSessionMetadata(mentioning: session.id)) {
            notchClose()
            NSWorkspace.shared.open(url)
            return
        }
        guard let pid = session.hostPID,
              let application = SessionHost.owningApplication(ofProcess: pid)
        else { return }
        notchClose()
        application.activate(options: [.activateAllWindows])
    }

    /// Les fichiers de sessions de l'application Claude qui citent cet identifiant (lecture seule).
    private static func desktopSessionMetadata(mentioning cliSessionID: String) -> [Data] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        let needle = Data(cliSessionID.utf8)
        return files.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .filter { $0.range(of: needle) != nil }
    }
}
