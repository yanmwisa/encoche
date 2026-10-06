//
//  SessionModel.swift
//  NotchDrop
//
//  Sessions Claude Code : état et décisions d'affichage, sans effet de bord.
//  Ce fichier n'importe que Foundation pour pouvoir être testé seul.
//

import Foundation

/// Du plus urgent au moins urgent : l'ordre de déclaration est l'ordre de tri.
enum SessionPhase: Int, Equatable, Comparable {
    case approval
    case question
    case working
    case done

    static func < (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var needsUser: Bool {
        self == .approval || self == .question
    }

    var label: String {
        switch self {
        case .approval: "Autorisation"
        case .question: "Vous attend"
        case .working: "Travaille"
        case .done: "Terminé"
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    /// Identifiant de session de Claude Code.
    let id: String
    var name: String
    var phase: SessionPhase
    var detail: String
    var updatedAt: Date
    /// Processus de Claude Code, pour retrouver l'application qui l'héberge.
    var hostPID: Int32?
    /// Le tour vient de finir et personne ne l'a encore vu : la pastille « Terminé » reste jusqu'à ce que ce soit vu.
    var hasUnseenFinish = false
}

enum SessionEventKind: Equatable {
    case started
    case promptSubmitted
    case permissionRequested(tool: String, summary: String)
    case nextStepsOffered(labels: [String])
    /// Claude pose une question (outil AskUserQuestion) : elle arrive comme une demande d'autorisation, mais il n'y a rien à autoriser.
    case questionAsked(text: String)
    case notified(type: String, message: String)
    case toolFinished
    case stopped
    case ended
}

struct SessionEvent: Equatable {
    let sessionID: String
    let cwd: String
    let kind: SessionEventKind
    let hostPID: Int32?
    /// Présent quand le hook attend une réponse (autorisation) : nomme le canal où la renvoyer.
    let replyID: String?

    init(sessionID: String, cwd: String, kind: SessionEventKind, hostPID: Int32?, replyID: String? = nil) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.kind = kind
        self.hostPID = hostPID
        self.replyID = replyID
    }
}

// MARK: - Lecture d'un événement reçu

extension SessionEvent {
    static let maxPayloadBytes = 64 * 1024
    static let maxIdentifierLength = 80
    static let maxTextLength = 160
    static let maxNextSteps = 3
    static let maxLabelLength = 80

    /// Le script de hook envoie `{"claude_pid": 123, "event": { ...JSON du hook... }}`.
    /// Tout ce qui n'est pas exactement ce format est refusé : le socket est ouvert aux autres processus.
    static func decode(_ data: Data) -> SessionEvent? {
        guard data.count <= maxPayloadBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["event"] as? [String: Any],
              let rawSessionID = payload["session_id"] as? String,
              let eventName = payload["hook_event_name"] as? String,
              let kind = kind(named: eventName, payload: payload)
        else { return nil }

        let sessionID = cleaned(rawSessionID, max: maxIdentifierLength)
        guard !sessionID.isEmpty else { return nil }

        let rawPID = root["claude_pid"] as? Int
        return SessionEvent(
            sessionID: sessionID,
            cwd: cleaned(payload["cwd"] as? String ?? "", max: 400),
            kind: kind,
            hostPID: rawPID.flatMap { Int32(exactly: $0) }.flatMap { $0 > 0 ? $0 : nil },
            replyID: (root["reply_id"] as? String).flatMap { isValidReplyID($0) ? $0 : nil }
        )
    }

    private static func kind(named eventName: String, payload: [String: Any]) -> SessionEventKind? {
        switch eventName {
        case "SessionStart":
            return .started
        case "UserPromptSubmit":
            return .promptSubmitted
        case "PermissionRequest":
            let tool = cleaned(payload["tool_name"] as? String ?? "", max: maxIdentifierLength)
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            if tool == questionToolName {
                return .questionAsked(text: questionText(of: input))
            }
            return .permissionRequested(tool: tool, summary: summary(of: input))
        case "NextSteps":
            // Envoyé par le mod next-steps-sequence, pas par Claude Code : seuls les libellés sont lus,
            // le texte des étapes ne quitte jamais le mod.
            let items = payload["items"] as? [[String: Any]] ?? []
            let labels = items.prefix(maxNextSteps)
                .compactMap { $0["label"] as? String }
                .map { cleaned($0, max: maxLabelLength) }
                .filter { !$0.isEmpty }
            return labels.isEmpty ? nil : .nextStepsOffered(labels: labels)
        case "Notification":
            return .notified(
                type: cleaned(payload["notification_type"] as? String ?? "", max: maxIdentifierLength),
                message: cleaned(payload["message"] as? String ?? "", max: maxTextLength)
            )
        case "PostToolUse":
            return .toolFinished
        case "Stop":
            return .stopped
        case "SessionEnd":
            return .ended
        default:
            return nil
        }
    }

    static let questionToolName = "AskUserQuestion"

    /// La première question posée, sinon une phrase d'attente.
    private static func questionText(of toolInput: [String: Any]) -> String {
        let questions = toolInput["questions"] as? [[String: Any]] ?? []
        let asked = cleaned(questions.first?["question"] as? String ?? "", max: maxTextLength)
        return asked.isEmpty ? "Claude vous pose une question" : asked
    }

    /// Ce que l'outil demande de faire, en une ligne : la commande, sinon le fichier.
    private static func summary(of toolInput: [String: Any]) -> String {
        for key in ["command", "file_path", "url", "pattern"] {
            if let value = toolInput[key] as? String, !value.isEmpty {
                return cleaned(value, max: maxTextLength)
            }
        }
        return ""
    }

    /// Texte affichable : sans caractère de contrôle ni de format (sens d'écriture, largeur nulle),
    /// retours à la ligne et tabulations changés en espaces, espaces repliés, longueur bornée.
    static func cleaned(_ text: String, max: Int) -> String {
        let visible = text.unicodeScalars
            .map { $0.properties.isWhitespace ? " " : $0 }
            .filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar) && scalar.properties.generalCategory != .format
            }
        let folded = String(String.UnicodeScalarView(visible))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard folded.count > max else { return folded }
        return String(folded.prefix(max - 1)) + "…"
    }
}

// MARK: - Évolution de l'état

func sessionName(fromWorkingDirectory cwd: String) -> String {
    let name = (cwd as NSString).lastPathComponent
    return name.isEmpty || name == "/" ? "Session" : name
}

func applying(_ event: SessionEvent, to sessions: [AgentSession], now: Date) -> [AgentSession] {
    let existingIndex = sessions.firstIndex { $0.id == event.sessionID }

    if event.kind == .ended {
        guard let existingIndex else { return sessions }
        var remaining = sessions
        remaining.remove(at: existingIndex)
        return remaining
    }

    var session = existingIndex.map { sessions[$0] } ?? AgentSession(
        id: event.sessionID,
        name: sessionName(fromWorkingDirectory: event.cwd),
        phase: .done,
        detail: "",
        updatedAt: now,
        hostPID: nil
    )
    session.updatedAt = now
    if let hostPID = event.hostPID { session.hostPID = hostPID }
    if !event.cwd.isEmpty { session.name = sessionName(fromWorkingDirectory: event.cwd) }
    apply(event.kind, to: &session)

    var updated = sessions
    if let existingIndex {
        updated[existingIndex] = session
    } else {
        updated.append(session)
    }
    return updated
}

private func apply(_ kind: SessionEventKind, to session: inout AgentSession) {
    switch kind {
    case .started:
        session.phase = .done
        session.detail = "Session démarrée"
        session.hasUnseenFinish = false
    case .promptSubmitted, .toolFinished:
        session.phase = .working
        session.detail = "Travaille"
        session.hasUnseenFinish = false
    case let .permissionRequested(tool, summary):
        session.phase = .approval
        session.detail = summary.isEmpty ? tool : summary
        session.hasUnseenFinish = false
    case let .questionAsked(text):
        session.phase = .question
        session.detail = text
        session.hasUnseenFinish = false
    case .nextStepsOffered:
        // Une offre discrète : elle n'allume pas les oreilles, elle attend dans l'écran Sessions.
        break
    case let .notified(type, message):
        applyNotification(type: type, message: message, to: &session)
    case .stopped:
        session.phase = .done
        session.detail = "A fini"
        session.hasUnseenFinish = true
    case .ended:
        break
    }
}

private func applyNotification(type: String, message: String, to session: inout AgentSession) {
    switch type {
    case "permission_prompt":
        // La demande d'autorisation ou la question arrive déjà avec son texte : on ne le remplace pas par le texte générique.
        guard !session.phase.needsUser else { return }
        session.phase = .approval
        session.detail = message
    case "idle_prompt":
        session.phase = .question
        session.detail = message.isEmpty ? "Attend votre réponse" : message
        session.hasUnseenFinish = false
    default:
        break
    }
}

/// Une session sans nouvelle depuis trop longtemps (processus tué, hook de fin jamais reçu) disparaît.
func removingStale(_ sessions: [AgentSession], now: Date, maxAge: TimeInterval) -> [AgentSession] {
    sessions.filter { now.timeIntervalSince($0.updatedAt) <= maxAge }
}

/// Une session dont le processus hôte n'existe plus (terminal fermé, processus tué) n'enverra jamais « SessionEnd » :
/// elle disparaît au balayage au lieu de rester des heures. Sans pid connu, seul l'âge décide.
func removingDeadSessions(_ sessions: [AgentSession], isAlive: (Int32) -> Bool) -> [AgentSession] {
    sessions.filter { session in
        guard let hostPID = session.hostPID else { return true }
        return isAlive(hostPID)
    }
}

// MARK: - Ce que l'encoche montre

struct SessionEars: Equatable {
    enum Tone: Equatable {
        /// Une session attend une réponse.
        case attention
        /// Une session a fini son tour.
        case finished
    }

    let left: String
    let right: String
    let mascotCount: Int
    var tone: Tone = .attention
}

struct NotchSummary: Equatable {
    let ears: SessionEars?
    let rows: [AgentSession]
    let waitingCount: Int
    let workingCount: Int
    let finishedCount: Int
}

func describeNotch(_ sessions: [AgentSession]) -> NotchSummary {
    let waiting = sessions.filter(\.phase.needsUser)
    let rows = sessions.sorted { first, second in
        first.phase != second.phase ? first.phase < second.phase : first.updatedAt > second.updatedAt
    }
    let finished = sessions.filter { $0.hasUnseenFinish && !$0.phase.needsUser }
    return NotchSummary(
        ears: waiting.isEmpty ? ears(forFinished: finished) : ears(forWaiting: waiting),
        rows: rows,
        waitingCount: waiting.count,
        workingCount: sessions.filter { $0.phase == .working }.count,
        finishedCount: finished.count
    )
}

/// Une demande passe toujours avant une fin de tour : les oreilles ne montrent « Terminé » que si rien n'attend.
private func ears(forFinished finished: [AgentSession]) -> SessionEars? {
    switch finished.count {
    case 0:
        return nil
    case 1:
        return SessionEars(left: finished[0].name, right: "Terminé", mascotCount: 1, tone: .finished)
    default:
        return SessionEars(left: "", right: "\(finished.count) ont fini", mascotCount: 2, tone: .finished)
    }
}

/// L'utilisateur a ouvert l'écran Sessions : les fins de tour sont vues.
func acknowledgingFinishes(_ sessions: [AgentSession]) -> [AgentSession] {
    sessions.map { session in
        var seen = session
        seen.hasUnseenFinish = false
        return seen
    }
}

private func ears(forWaiting waiting: [AgentSession]) -> SessionEars? {
    switch waiting.count {
    case 0:
        return nil
    case 1:
        let session = waiting[0]
        return SessionEars(left: session.name, right: session.phase.label, mascotCount: 1)
    default:
        return SessionEars(left: "", right: "\(waiting.count) vous attendent", mascotCount: 2)
    }
}

// MARK: - Glisser un fichier vers l'encoche

/// Un fichier glissé ouvre l'encoche fermée, mais aussi celle qui montre une alerte de session ou l'apparition
/// d'une pastille : sinon une session en attente empêche de déposer un fichier.
func dragOpensNotch(statusRaw: String) -> Bool {
    ["closed", "popping", "sessionAlert"].contains(statusRaw)
}

// MARK: - « Y aller » : la session précise dans l'application Claude

/// Le lien qui ouvre dans l'application Claude la session dont `cliSessionId` est celui du hook.
/// `metadata` : le contenu des fichiers `claude-code-sessions/<compte>/<org>/local_*.json`.
/// Une session archivée ne gagne que si aucune autre ne correspond.
func desktopSessionURL(forCLISession cliSessionID: String, metadata: [Data]) -> URL? {
    var archivedMatch: String?
    for file in metadata {
        guard let record = try? JSONSerialization.jsonObject(with: file) as? [String: Any],
              let localID = record["sessionId"] as? String, !localID.isEmpty
        else { continue }
        let knownIDs = [record["cliSessionId"] as? String].compactMap { $0 }
            + (record["priorCliSessionIds"] as? [String] ?? [])
        guard knownIDs.contains(cliSessionID) else { continue }
        if record["isArchived"] as? Bool != true { return epitaxyURL(localID) }
        archivedMatch = archivedMatch ?? localID
    }
    return archivedMatch.flatMap(epitaxyURL)
}

private func epitaxyURL(_ localID: String) -> URL? {
    URL(string: "claude://claude.ai/epitaxy/\(localID)")
}
