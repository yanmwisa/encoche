//
//  SessionStore.swift
//  NotchDrop
//
//  Les sessions connues, partagées par toutes les fenêtres d'encoche :
//  l'encoche est reconstruite à chaque changement d'écran, les sessions ne doivent pas l'être.
//

import Combine
import Foundation

final class SessionStore: ObservableObject {
    static let defaultMaxAge: TimeInterval = 12 * 60 * 60

    @Published private(set) var sessions: [AgentSession] = []
    /// Les demandes (autorisation, choix d'étapes) auxquelles l'encoche peut répondre, la plus ancienne d'abord.
    @Published private(set) var requests: [PendingRequest] = []
    private let maxAge: TimeInterval

    init(maxAge: TimeInterval = SessionStore.defaultMaxAge) {
        self.maxAge = maxAge
    }

    func receive(_ event: SessionEvent, now: Date = Date()) {
        sessions = removingStale(applying(event, to: sessions, now: now), now: now, maxAge: maxAge)
        requests = removingExpiredRequests(pendingRequests(afterReceiving: event, in: requests, now: now), now: now)
    }

    /// Signal 0 : ne touche pas au processus, dit seulement s'il existe (EPERM : il existe, mais il n'est pas à nous).
    static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    func acknowledgeFinishes() {
        let seen = acknowledgingFinishes(sessions)
        if seen != sessions { sessions = seen }
    }

    func removeRequest(_ replyID: String) {
        requests = removingRequest(replyID, from: requests)
    }

    /// Balayage périodique : sessions trop anciennes, sessions dont le processus est mort, demandes expirées.
    func sweep(now: Date = Date(), isProcessAlive: (Int32) -> Bool = SessionStore.isProcessAlive) {
        let kept = removingDeadSessions(removingStale(sessions, now: now, maxAge: maxAge), isAlive: isProcessAlive)
        if kept != sessions { sessions = kept }
        let pending = removingExpiredRequests(requests, now: now)
        if pending != requests { requests = pending }
    }
}
