//
//  RequestModel.swift
//  NotchDrop
//
//  Les demandes auxquelles l'encoche répond pour une session (autorisation d'outil, choix d'étapes) :
//  état et règles, sans effet de bord. Ce fichier n'importe que Foundation pour pouvoir être testé seul.
//

import Foundation

enum ApprovalDecision: String, Equatable {
    case allow
    case deny
}

/// Ce que l'encoche renvoie au script qui attend, sur une ligne.
enum RequestReply: Equatable {
    case decision(ApprovalDecision)
    /// Les étapes choisies, par numéro (à partir de 0), dans l'ordre des appuis.
    case sequence([Int])

    var line: String {
        switch self {
        case let .decision(decision): decision.rawValue
        case let .sequence(indices): indices.map(String.init).joined(separator: ",")
        }
    }
}

enum RequestKind: Equatable {
    case permission(tool: String, summary: String)
    case nextSteps(labels: [String])
}

struct PendingRequest: Identifiable, Equatable {
    let replyID: String
    let sessionID: String
    let sessionName: String
    let kind: RequestKind
    let requestedAt: Date

    var id: String { replyID }

    /// Au-delà, le script de hook a cessé d'attendre : l'autorisation est revenue au terminal.
    /// Les étapes proposées attendent plus longtemps : on peut y revenir sans que la session bloque.
    var timeout: TimeInterval {
        switch kind {
        case .permission: 60
        case .nextSteps: 600
        }
    }
}

/// L'identifiant d'un canal de réponse devient un nom de fichier : lettres, chiffres et tirets seulement.
func isValidReplyID(_ text: String) -> Bool {
    (8 ... 64).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
}

/// Les demandes en attente après un événement. Une demande nouvelle remplace l'ancienne de même nature dans
/// la même session ; tout signe que la session a avancé retire les siennes. La notification « permission_prompt »
/// accompagne la demande elle-même, et la fin d'un tour (« Stop ») précède souvent les étapes proposées :
/// ni l'une ni l'autre ne retire ce qui vient d'arriver.
func pendingRequests(afterReceiving event: SessionEvent, in pending: [PendingRequest], now: Date) -> [PendingRequest] {
    switch event.kind {
    case let .permissionRequested(tool, summary):
        guard let replyID = event.replyID else { return pending }
        return replacing(.permission(tool: tool, summary: summary), replyID: replyID, event: event, in: pending, now: now)
    case let .nextStepsOffered(labels):
        guard let replyID = event.replyID else { return pending }
        return replacing(.nextSteps(labels: labels), replyID: replyID, event: event, in: pending, now: now)
    case .notified, .questionAsked:
        return pending
    case .stopped:
        return pending.filter { $0.sessionID != event.sessionID || !$0.kind.isPermission }
    case .started, .promptSubmitted, .toolFinished, .ended:
        return pending.filter { $0.sessionID != event.sessionID }
    }
}

private func replacing(_ kind: RequestKind, replyID: String, event: SessionEvent, in pending: [PendingRequest], now: Date) -> [PendingRequest] {
    let request = PendingRequest(
        replyID: replyID,
        sessionID: event.sessionID,
        sessionName: sessionName(fromWorkingDirectory: event.cwd),
        kind: kind,
        requestedAt: now
    )
    let kept = pending.filter { $0.sessionID != event.sessionID || $0.kind.isPermission != kind.isPermission }
    // Une autorisation bloque une session : elle passe avant des étapes proposées, quel que soit l'ordre d'arrivée.
    let all = kept + [request]
    return all.filter { $0.kind.isPermission } + all.filter { !$0.kind.isPermission }
}

extension RequestKind {
    fileprivate var isPermission: Bool {
        if case .permission = self { return true }
        return false
    }
}

func removingRequest(_ replyID: String, from pending: [PendingRequest]) -> [PendingRequest] {
    pending.filter { $0.replyID != replyID }
}

func removingExpiredRequests(_ pending: [PendingRequest], now: Date) -> [PendingRequest] {
    pending.filter { now.timeIntervalSince($0.requestedAt) < $0.timeout }
}

/// Les numéros d'étapes que l'encoche peut renvoyer : dans la liste proposée, sans doublon, au moins un.
func isValidSequence(_ indices: [Int], stepCount: Int) -> Bool {
    !indices.isEmpty && Set(indices).count == indices.count && indices.allSatisfy { (0 ..< stepCount).contains($0) }
}

/// Toucher une étape la coche en dernier, la toucher de nouveau la décoche : l'ordre des appuis fait la séquence.
func togglingStep(_ picked: [Int], _ index: Int) -> [Int] {
    picked.contains(index) ? picked.filter { $0 != index } : picked + [index]
}

// MARK: - Ouverture automatique de l'encoche

enum RequestPanelAction: Equatable {
    case open
    case close
    case none
}

/// Quand une autorisation attend, l'encoche s'ouvre d'elle-même sur la carte ; quand il n'y en a plus
/// et que c'est elle qui l'avait ouverte, elle se referme. Une encoche que l'utilisateur utilise
/// (fichiers, réglages, notification) n'est jamais déplacée : les oreilles et l'onglet Sessions le préviennent.
/// `statusRaw` est le statut de l'encoche (« closed », « sessionAlert », « popping », « opened »…).
func requestPanelAction(statusRaw: String, openedByRequest: Bool, permissionCount: Int, previousPermissionCount: Int) -> RequestPanelAction {
    if permissionCount > previousPermissionCount, ["closed", "sessionAlert", "popping"].contains(statusRaw) {
        return .open
    }
    if permissionCount == 0, statusRaw == "opened", openedByRequest {
        return .close
    }
    return .none
}

func permissionCount(in requests: [PendingRequest]) -> Int {
    requests.filter { if case .permission = $0.kind { return true } else { return false } }.count
}

