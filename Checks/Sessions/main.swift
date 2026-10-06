//
//  Vérifications du modèle des sessions (SessionModel.swift), sans XCTest ni Xcode.
//  Lancer : ./scripts/check-sessions.sh
//

import Foundation

var passed = 0
var failed = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        passed += 1
        print("OK   \(name)")
    } else {
        failed += 1
        print("ECHEC \(name)")
    }
}

func payload(_ event: String, session: String = "s1", cwd: String = "/Users/example/my-project",
             extra: [String: Any] = [:], pid: Int? = 4242) -> Data {
    var inner: [String: Any] = ["hook_event_name": event, "session_id": session, "cwd": cwd]
    extra.forEach { inner[$0.key] = $0.value }
    var root: [String: Any] = ["event": inner]
    if let pid { root["claude_pid"] = pid }
    return try! JSONSerialization.data(withJSONObject: root)
}

let t0 = Date(timeIntervalSince1970: 1_000_000)

func feed(_ sessions: [AgentSession], _ data: Data, at now: Date = t0) -> [AgentSession] {
    guard let event = SessionEvent.decode(data) else { return sessions }
    return applying(event, to: sessions, now: now)
}

// --- Lecture des événements

check("UserPromptSubmit : décodé avec le pid et le nom du dossier",
      SessionEvent.decode(payload("UserPromptSubmit")) == SessionEvent(
        sessionID: "s1", cwd: "/Users/example/my-project", kind: .promptSubmitted, hostPID: 4242))
check("PermissionRequest : l'outil et la commande",
      SessionEvent.decode(payload("PermissionRequest", extra: ["tool_name": "Bash", "tool_input": ["command": "git push"]]))?.kind
        == .permissionRequested(tool: "Bash", summary: "git push"))
check("Notification : type et message",
      SessionEvent.decode(payload("Notification", extra: ["notification_type": "idle_prompt", "message": "Claude attend"]))?.kind
        == .notified(type: "idle_prompt", message: "Claude attend"))
check("événement inconnu : refusé", SessionEvent.decode(payload("PreCompact")) == nil)
check("JSON invalide : refusé", SessionEvent.decode(Data("pas du json".utf8)) == nil)
check("sans session_id : refusé", SessionEvent.decode(Data(#"{"event":{"hook_event_name":"Stop"}}"#.utf8)) == nil)
check("identifiant vide : refusé", SessionEvent.decode(payload("Stop", session: "")) == nil)
check("trop gros : refusé", SessionEvent.decode(Data(repeating: 0x20, count: SessionEvent.maxPayloadBytes + 1)) == nil)
check("pid négatif ou absent : ignoré",
      SessionEvent.decode(payload("Stop", pid: -5))?.hostPID == nil && SessionEvent.decode(payload("Stop", pid: nil))?.hostPID == nil)

check("texte nettoyé : contrôles, sens d'écriture et espaces",
      SessionEvent.cleaned("a\u{1B}[31m\n\tb\u{202E}c   d", max: 80) == "a[31m bc d")
check("texte tronqué avec …", SessionEvent.cleaned(String(repeating: "x", count: 50), max: 10) == "xxxxxxxxx…")

// --- Évolution de l'état

check("nouvelle session au démarrage : terminée, nommée d'après le dossier",
      feed([], payload("SessionStart")).first.map { $0.name == "my-project" && $0.phase == .done } == true)
check("prompt : travaille", feed([], payload("UserPromptSubmit")).first?.phase == .working)

let asking = feed([], payload("PermissionRequest", extra: ["tool_name": "Bash", "tool_input": ["command": "rm -rf build"]]))
check("autorisation : phase et commande", asking.first.map { $0.phase == .approval && $0.detail == "rm -rf build" } == true)
check("la notification générique ne remplace pas la commande",
      feed(asking, payload("Notification", extra: ["notification_type": "permission_prompt", "message": "Claude a besoin de votre accord"])).first?.detail == "rm -rf build")
check("après l'outil, la session retravaille", feed(asking, payload("PostToolUse")).first?.phase == .working)
check("idle_prompt : la session vous attend",
      feed([], payload("Notification", extra: ["notification_type": "idle_prompt"])).first?.phase == .question)
check("notification d'un autre type : sans effet sur la phase",
      feed(asking, payload("Notification", extra: ["notification_type": "auth_success"])).first?.phase == .approval)
check("Stop : terminée", feed(asking, payload("Stop")).first?.phase == .done)
check("SessionEnd : la session disparaît", feed(asking, payload("SessionEnd")).isEmpty)
check("SessionEnd d'une session inconnue : rien", feed([], payload("SessionEnd")).isEmpty)
check("deux sessions restent séparées",
      feed(feed([], payload("UserPromptSubmit", session: "a")), payload("Stop", session: "b")).count == 2)
check("le pid est gardé", feed([], payload("UserPromptSubmit")).first?.hostPID == 4242)

// --- Péremption

let old = AgentSession(id: "old", name: "x", phase: .working, detail: "", updatedAt: t0, hostPID: nil)
check("session périmée retirée", removingStale([old], now: t0.addingTimeInterval(13 * 3600), maxAge: 12 * 3600).isEmpty)
check("session récente gardée", removingStale([old], now: t0.addingTimeInterval(3600), maxAge: 12 * 3600).count == 1)

// --- Ce que l'encoche montre

func session(_ id: String, _ phase: SessionPhase, age: TimeInterval = 0) -> AgentSession {
    AgentSession(id: id, name: id, phase: phase, detail: "", updatedAt: t0.addingTimeInterval(-age), hostPID: nil)
}

check("rien n'attend : pas d'oreilles", describeNotch([session("a", .working), session("b", .done)]).ears == nil)
check("une autorisation : nom et type",
      describeNotch([session("a", .approval)]).ears == SessionEars(left: "a", right: "Permission", mascotCount: 1))
check("une question : nom et type",
      describeNotch([session("a", .question)]).ears == SessionEars(left: "a", right: "Waiting for you", mascotCount: 1))
check("deux en attente : le compte, deux mascottes",
      describeNotch([session("a", .approval), session("b", .question)]).ears == SessionEars(left: "", right: "2 waiting for you", mascotCount: 2))
check("tri : autorisation, question, travail, terminé",
      describeNotch([session("d", .done), session("w", .working), session("q", .question), session("a", .approval)]).rows.map(\.id) == ["a", "q", "w", "d"])
check("à phase égale, la plus récente d'abord",
      describeNotch([session("vieille", .working, age: 100), session("neuve", .working, age: 1)]).rows.map(\.id) == ["neuve", "vieille"])
check("les comptes", {
    let summary = describeNotch([session("a", .approval), session("b", .working), session("c", .working)])
    return summary.waitingCount == 1 && summary.workingCount == 2
}())


// Glisser un fichier : ce qui ouvre l'encoche
check("glisser ouvre l'encoche fermée", dragOpensNotch(statusRaw: "closed"))
check("glisser ouvre malgré une alerte de session", dragOpensNotch(statusRaw: "sessionAlert"))
check("glisser ouvre pendant la pastille", dragOpensNotch(statusRaw: "popping"))
check("glisser ne referme ni ne rouvre l'encoche déjà ouverte", !dragOpensNotch(statusRaw: "opened"))

// « Y aller » : la session précise
func meta(_ local: String, cli: String?, prior: [String] = [], archived: Bool = false) -> Data {
    var record: [String: Any] = ["sessionId": local, "priorCliSessionIds": prior, "isArchived": archived]
    if let cli { record["cliSessionId"] = cli }
    return try! JSONSerialization.data(withJSONObject: record)
}
let linkBase = "claude://claude.ai/epitaxy/"
check("lien : la session dont cliSessionId correspond",
      desktopSessionURL(forCLISession: "cli-2", metadata: [meta("local_1", cli: "cli-1"), meta("local_2", cli: "cli-2")])?.absoluteString == linkBase + "local_2")
check("lien : un ancien identifiant de la session correspond aussi",
      desktopSessionURL(forCLISession: "vieux", metadata: [meta("local_1", cli: "neuf", prior: ["vieux"])])?.absoluteString == linkBase + "local_1")
check("lien : la session active passe avant l'archivée",
      desktopSessionURL(forCLISession: "x", metadata: [meta("local_vieille", cli: "x", archived: true), meta("local_vivante", cli: "x")])?.absoluteString == linkBase + "local_vivante")
check("lien : à défaut, la session archivée",
      desktopSessionURL(forCLISession: "x", metadata: [meta("local_archivee", cli: "x", archived: true)])?.absoluteString == linkBase + "local_archivee")
check("lien : aucune correspondance, aucun lien (repli sur l'application)",
      desktopSessionURL(forCLISession: "inconnu", metadata: [meta("local_1", cli: "cli-1")]) == nil)
check("lien : un fichier illisible est ignoré",
      desktopSessionURL(forCLISession: "a", metadata: [Data("pas du json".utf8), meta("local_1", cli: "a")])?.absoluteString == linkBase + "local_1")


// Déplacer un fichier de la tablette : pas de doublon
var ownDrag = OwnDragGuard()
check("dépôt venu de l'extérieur : accepté", !ownDrag.shouldIgnoreDrop())
ownDrag.beginOwnDrag()
check("dépôt d'un fichier de la tablette sur elle-même : ignoré", ownDrag.shouldIgnoreDrop())
check("le dépôt suivant, venu de l'extérieur, est de nouveau accepté", !ownDrag.shouldIgnoreDrop())
ownDrag.beginOwnDrag()
ownDrag.reset()
check("après un nouveau clic, le marquage est levé", !ownDrag.shouldIgnoreDrop())


// Approbations depuis l'encoche
func permission(_ session: String, reply: String?, tool: String = "Bash", summary: String = "git push") -> SessionEvent {
    SessionEvent(sessionID: session, cwd: "/Users/example/my-project", kind: .permissionRequested(tool: tool, summary: summary), hostPID: 1, replyID: reply)
}
func plain(_ session: String, _ kind: SessionEventKind) -> SessionEvent {
    SessionEvent(sessionID: session, cwd: "/tmp", kind: kind, hostPID: 1)
}
func decodedWithReply(_ reply: String) -> SessionEvent? {
    let data = payload("PermissionRequest", extra: ["tool_name": "Bash", "tool_input": ["command": "ls"]])
    var root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    root["reply_id"] = reply
    return SessionEvent.decode(try! JSONSerialization.data(withJSONObject: root))
}
check("identifiant de réponse valide", isValidReplyID("3F2A9C10-7B6E-4D2A-9A51-0C1D2E3F4A5B"))
check("identifiant refusé : chemin, point, trop court", !isValidReplyID("../../etc/passwd") && !isValidReplyID("a.b.c.d.e.f.g.h") && !isValidReplyID("abc"))
check("décodage : reply_id valide conservé", decodedWithReply("abcd1234-ef56")?.replyID == "abcd1234-ef56")
check("décodage : reply_id dangereux ignoré", decodedWithReply("../../x")?.replyID == nil)
let first = pendingRequests(afterReceiving: permission("a", reply: "reply-aaaa-1111"), in: [], now: t0)
check("une demande avec canal est mise en attente", first.map(\.replyID) == ["reply-aaaa-1111"] && first[0].sessionName == "my-project" && first[0].kind == .permission(tool: "Bash", summary: "git push"))
check("une demande sans canal n'attend rien", pendingRequests(afterReceiving: permission("a", reply: nil), in: [], now: t0).isEmpty)
check("une nouvelle demande de la même session remplace l'ancienne",
      pendingRequests(afterReceiving: permission("a", reply: "reply-aaaa-2222"), in: first, now: t0).map(\.replyID) == ["reply-aaaa-2222"])
check("deux sessions : deux demandes, la plus ancienne d'abord",
      pendingRequests(afterReceiving: permission("b", reply: "reply-bbbb-1111"), in: first, now: t0).map(\.sessionID) == ["a", "b"])
check("la notification de permission ne retire pas la demande",
      pendingRequests(afterReceiving: plain("a", .notified(type: "permission_prompt", message: "m")), in: first, now: t0) == first)
check("répondre ailleurs (outil fini) retire la demande", pendingRequests(afterReceiving: plain("a", .toolFinished), in: first, now: t0).isEmpty)
check("fin de session retire la demande", pendingRequests(afterReceiving: plain("a", .ended), in: first, now: t0).isEmpty)
check("l'événement d'une autre session laisse la demande", pendingRequests(afterReceiving: plain("z", .toolFinished), in: first, now: t0) == first)
check("répondre retire la demande choisie", removingRequest("reply-aaaa-1111", from: first).isEmpty)
check("expiration : encore là à 59 s, partie à 60 s",
      removingExpiredRequests(first, now: t0.addingTimeInterval(59)).count == 1 && removingExpiredRequests(first, now: t0.addingTimeInterval(60)).isEmpty)


// Tablette : défilement
check("pas de flèches avec peu de fichiers", !TrayScroll.needsArrows(itemCount: 4) && TrayScroll.needsArrows(itemCount: 5))
check("flèche suivante : une page plus loin", TrayScroll.targetIndex(current: 0, direction: .later, itemCount: 12) == 4)
check("flèche suivante : s'arrête au dernier fichier", TrayScroll.targetIndex(current: 8, direction: .later, itemCount: 10) == 9)
check("flèche précédente : revient d'une page, jamais avant le premier", TrayScroll.targetIndex(current: 4, direction: .earlier, itemCount: 12) == 0 && TrayScroll.targetIndex(current: 1, direction: .earlier, itemCount: 12) == 0)
check("tablette vide : index 0", TrayScroll.targetIndex(current: 3, direction: .later, itemCount: 0) == 0)


// Choix d'étapes depuis l'encoche
func nextStepsPayload(_ items: [[String: Any]], reply: String? = "steps-aaaa-1111", session: String = "a") -> Data {
    var root: [String: Any] = ["event": ["hook_event_name": "NextSteps", "session_id": session, "cwd": "/Users/example/Encoche-Mac", "items": items]]
    if let reply { root["reply_id"] = reply }
    return try! JSONSerialization.data(withJSONObject: root)
}
let stepItems: [[String: Any]] = [["label": "Lancer les tests", "prompt": "lance les tests"], ["label": "Committer", "prompt": "commit"], ["label": "Pousser", "prompt": "push"]]
check("décodage : les libellés seulement, jamais le texte des étapes",
      SessionEvent.decode(nextStepsPayload(stepItems))?.kind == .nextStepsOffered(labels: ["Lancer les tests", "Committer", "Pousser"]))
check("décodage : trois étapes au plus", {
    let many = stepItems + [["label": "Quatrième"], ["label": "Cinquième"]]
    if case let .nextStepsOffered(labels)? = SessionEvent.decode(nextStepsPayload(many))?.kind { return labels.count == 3 }
    return false
}())
check("décodage : libellé nettoyé (retours à la ligne, contrôles)", {
    if case let .nextStepsOffered(labels)? = SessionEvent.decode(nextStepsPayload([["label": "a\nb\u{202E}c"]]))?.kind { return labels == ["a bc"] }
    return false
}())
check("décodage : sans aucune étape lisible, événement refusé", SessionEvent.decode(nextStepsPayload([["prompt": "x"], ["label": "  "]])) == nil)
check("décodage : identifiant de réponse conservé", SessionEvent.decode(nextStepsPayload(stepItems))?.replyID == "steps-aaaa-1111")
let offer = pendingRequests(afterReceiving: SessionEvent.decode(nextStepsPayload(stepItems))!, in: [], now: t0)
check("une offre d'étapes est mise en attente avec ses libellés", offer.count == 1 && offer[0].kind == .nextSteps(labels: ["Lancer les tests", "Committer", "Pousser"]) && offer[0].sessionName == "Encoche-Mac")
check("une nouvelle offre de la même session remplace l'ancienne",
      pendingRequests(afterReceiving: SessionEvent.decode(nextStepsPayload(stepItems, reply: "steps-aaaa-2222"))!, in: offer, now: t0).map(\.replyID) == ["steps-aaaa-2222"])
check("autorisation et offre d'une même session coexistent", pendingRequests(afterReceiving: permission("a", reply: "reply-aaaa-1111"), in: offer, now: t0).count == 2)
check("la fin du tour (Stop) ne retire pas l'offre d'étapes", pendingRequests(afterReceiving: plain("a", .stopped), in: offer, now: t0) == offer)
check("la fin du tour retire une autorisation restée en attente", pendingRequests(afterReceiving: plain("a", .stopped), in: first, now: t0).isEmpty)
check("un nouveau message de l'utilisateur retire l'offre", pendingRequests(afterReceiving: plain("a", .promptSubmitted), in: offer, now: t0).isEmpty)
check("un outil qui tourne retire l'offre", pendingRequests(afterReceiving: plain("a", .toolFinished), in: offer, now: t0).isEmpty)
check("l'offre d'une autre session reste", pendingRequests(afterReceiving: plain("z", .promptSubmitted), in: offer, now: t0) == offer)
check("une offre sans canal n'attend rien", pendingRequests(afterReceiving: SessionEvent.decode(nextStepsPayload(stepItems, reply: nil))!, in: [], now: t0).isEmpty)
check("expiration d'une offre : 10 minutes",
      removingExpiredRequests(offer, now: t0.addingTimeInterval(599)).count == 1 && removingExpiredRequests(offer, now: t0.addingTimeInterval(600)).isEmpty)
check("l'offre n'allume pas les oreilles", describeNotch(applying(SessionEvent.decode(nextStepsPayload(stepItems))!, to: [], now: t0)).ears == nil)
check("réponse : décision en une ligne", RequestReply.decision(.allow).line == "allow" && RequestReply.decision(.deny).line == "deny")
check("réponse : séquence en numéros dans l'ordre des appuis", RequestReply.sequence([2, 0]).line == "2,0")
check("séquence valide : dans la plage, sans doublon", isValidSequence([2, 0], stepCount: 3) && isValidSequence([1], stepCount: 3))
check("séquence refusée : vide, hors plage, négative, doublon", !isValidSequence([], stepCount: 3) && !isValidSequence([3], stepCount: 3) && !isValidSequence([-1], stepCount: 3) && !isValidSequence([1, 1], stepCount: 3))

check("toucher des étapes : l'ordre des appuis fait la séquence", togglingStep(togglingStep([], 2), 0) == [2, 0])
check("toucher une étape cochée la décoche", togglingStep([2, 0], 2) == [0])


// Ouverture automatique de l'encoche
check("nouvelle autorisation, encoche fermée : s'ouvre", requestPanelAction(statusRaw: "closed", openedByRequest: false, permissionCount: 1, previousPermissionCount: 0) == .open)
check("nouvelle autorisation, oreilles ou pastille : s'ouvre", requestPanelAction(statusRaw: "sessionAlert", openedByRequest: false, permissionCount: 1, previousPermissionCount: 0) == .open && requestPanelAction(statusRaw: "popping", openedByRequest: false, permissionCount: 1, previousPermissionCount: 0) == .open)
check("une seconde autorisation ouvre aussi si l'encoche s'est refermée", requestPanelAction(statusRaw: "closed", openedByRequest: false, permissionCount: 2, previousPermissionCount: 1) == .open)
check("encoche utilisée (fichiers, réglages) : jamais déplacée", requestPanelAction(statusRaw: "opened", openedByRequest: false, permissionCount: 1, previousPermissionCount: 0) == .none)
check("notification affichée : rien", requestPanelAction(statusRaw: "notification", openedByRequest: false, permissionCount: 1, previousPermissionCount: 0) == .none)
check("plus d'autorisation, ouverte par elle : se referme", requestPanelAction(statusRaw: "opened", openedByRequest: true, permissionCount: 0, previousPermissionCount: 1) == .close)
check("plus d'autorisation, ouverte par l'utilisateur : reste", requestPanelAction(statusRaw: "opened", openedByRequest: false, permissionCount: 0, previousPermissionCount: 1) == .none)
check("autorisation déjà connue : pas de réouverture", requestPanelAction(statusRaw: "closed", openedByRequest: false, permissionCount: 1, previousPermissionCount: 1) == .none)
check("une autorisation passe avant une offre d'étapes plus ancienne", pendingRequests(afterReceiving: permission("b", reply: "reply-bbbb-1111"), in: offer, now: t0).map(\.sessionID) == ["b", "a"])
check("le compte ignore les étapes proposées", permissionCount(in: offer + first) == 1)


// Pastille « Terminé »
func finished(_ id: String, unseen: Bool = true) -> AgentSession {
    var value = session(id, .done)
    value.hasUnseenFinish = unseen
    return value
}
let afterStop = applying(plain("a", .stopped), to: [session("a", .working)], now: t0)
check("fin de tour : la session est marquée « non vue »", afterStop[0].hasUnseenFinish && afterStop[0].phase == .done)
check("nouveau message : la fin n'est plus à voir", !applying(plain("a", .promptSubmitted), to: afterStop, now: t0)[0].hasUnseenFinish)
check("un outil qui tourne : la fin n'est plus à voir", !applying(plain("a", .toolFinished), to: afterStop, now: t0)[0].hasUnseenFinish)
check("une demande d'autorisation : la fin n'est plus à voir", !applying(permission("a", reply: nil), to: afterStop, now: t0)[0].hasUnseenFinish)
check("une session qui démarre n'a rien à faire voir", !applying(plain("n", .started), to: [], now: t0)[0].hasUnseenFinish)
check("oreilles : une session a fini", describeNotch([finished("a")]).ears == SessionEars(left: "a", right: "Done", mascotCount: 1, tone: .finished))
check("oreilles : deux ont fini", describeNotch([finished("a"), finished("b")]).ears == SessionEars(left: "", right: "2 finished", mascotCount: 2, tone: .finished))
check("oreilles : une demande passe avant une fin de tour", describeNotch([finished("a"), session("b", .approval)]).ears?.tone == .attention)
check("oreilles : fin déjà vue, rien", describeNotch([finished("a", unseen: false)]).ears == nil)
check("oreilles : une session qui travaille n'a pas de pastille", describeNotch([session("w", .working)]).ears == nil)
check("le compte des fins non vues", describeNotch([finished("a"), finished("b", unseen: false), session("c", .working)]).finishedCount == 1)
check("ouvrir Sessions : toutes les fins sont vues", acknowledgingFinishes([finished("a"), finished("b")]).allSatisfy { !$0.hasUnseenFinish })


// Question de Claude et sessions mortes
func questionPayload(question: String? = "Quelle est ta couleur préférée ?") -> Data {
    var input: [String: Any] = [:]
    if let question { input["questions"] = [["question": question, "options": [["label": "Rouge"]]]] }
    return payload("PermissionRequest", session: "a", extra: ["tool_name": "AskUserQuestion", "tool_input": input])
}
check("question de Claude : lue comme une question, pas une autorisation",
      SessionEvent.decode(questionPayload())?.kind == .questionAsked(text: "Quelle est ta couleur préférée ?"))
check("question sans texte : phrase d'attente", SessionEvent.decode(questionPayload(question: nil))?.kind == .questionAsked(text: "Claude has a question"))
let afterQuestion = applying(SessionEvent.decode(questionPayload())!, to: [session("a", .working)], now: t0)
check("question : la session « vous attend » avec le texte de la question", afterQuestion[0].phase == .question && afterQuestion[0].detail == "Quelle est ta couleur préférée ?")
check("la notification de permission n'écrase pas la question",
      applying(plain("a", .notified(type: "permission_prompt", message: "Claude needs your permission")), to: afterQuestion, now: t0)[0].detail == "Quelle est ta couleur préférée ?")
check("une question ne crée aucune demande à laquelle répondre", pendingRequests(afterReceiving: SessionEvent.decode(questionPayload())!, in: [], now: t0).isEmpty)
check("la réponse à la question (outil fini) remet la session au travail", applying(plain("a", .toolFinished), to: afterQuestion, now: t0)[0].phase == .working)
func hosted(_ id: String, pid: Int32?) -> AgentSession {
    AgentSession(id: id, name: id, phase: .working, detail: "", updatedAt: t0, hostPID: pid)
}
check("session dont le processus est mort : retirée", removingDeadSessions([hosted("vivante", pid: 10), hosted("morte", pid: 20)], isAlive: { $0 == 10 }).map(\.id) == ["vivante"])
check("session sans pid connu : conservée", removingDeadSessions([hosted("inconnue", pid: nil)], isAlive: { _ in false }).count == 1)


// Lecteur : ce qui joue
let sep = String(NowPlaying.fieldSeparator)
func readout(_ state: String, _ title: String, _ artist: String) -> String { [state, title, artist].joined(separator: sep) }
check("lecture : ce qui joue", NowPlaying.parse(readout("playing", "Nuit blanche", "Les Étoiles"), source: .music) == NowPlaying(source: .music, title: "Nuit blanche", artist: "Les Étoiles", isPlaying: true))
check("lecture : en pause", NowPlaying.parse(readout("paused", "Marche lente", "Orchestre"), source: .spotify)?.isPlaying == false)
check("lecture : arrêté ou vide, rien ne joue", NowPlaying.parse("", source: .music) == nil && NowPlaying.parse(readout("stopped", "x", "y"), source: .music) == nil)
check("lecture : forme inattendue ignorée", NowPlaying.parse("playing|titre|artiste", source: .music) == nil && NowPlaying.parse(readout("playing", "", "a"), source: .music) == nil)
check("lecture : texte nettoyé (retours à la ligne, contrôles, longueur)", {
    let parsed = NowPlaying.parse(readout("playing", "a\nb\u{202E}c" + String(repeating: "x", count: 300), "z"), source: .music)
    return parsed?.title.hasPrefix("a bcx") == true && (parsed?.title.count ?? 999) <= NowPlaying.maxTextLength
}())
let pausedMusic = NowPlaying(source: .music, title: "a", artist: "", isPlaying: false)
let playingSpotify = NowPlaying(source: .spotify, title: "b", artist: "", isPlaying: true)
check("le Lecteur pilote ce qui joue avant ce qui est en pause", currentTrack(among: [pausedMusic, playingSpotify]) == playingSpotify)
check("sans rien qui joue, le Lecteur garde la source en pause", currentTrack(among: [pausedMusic]) == pausedMusic && currentTrack(among: []) == nil)
let finishedEars = SessionEars(left: "a", right: "Done", mascotCount: 1, tone: .finished)
check("oreilles : une alerte de session passe avant la musique", earsContent(sessionEars: finishedEars, nowPlaying: playingSpotify) == .session(finishedEars))
check("oreilles : la musique qui joue s'affiche", earsContent(sessionEars: nil, nowPlaying: playingSpotify) == .nowPlaying(playingSpotify))
check("oreilles : une musique en pause n'occupe pas l'encoche", earsContent(sessionEars: nil, nowPlaying: pausedMusic) == nil && earsContent(sessionEars: nil, nowPlaying: nil) == nil)
check("script de lecture : demande l'état, le titre et l'artiste", nowPlayingReadScript(for: .spotify).contains("tell application \"Spotify\"") && nowPlayingReadScript(for: .music).contains("artist of current track"))
check("script de commande", playerCommandScript(.playPause, for: .music) == "tell application \"Music\" to playpause" && playerCommandScript(.next, for: .spotify) == "tell application \"Spotify\" to next track")


// Lecteur : volume par source
func sourceReadout(_ volume: String, _ state: String, _ title: String, _ artist: String) -> String { [volume, state, title, artist].joined(separator: sep) }
check("source : volume et titre en cours", PlayerSource.parse(sourceReadout("55", "playing", "Nuit blanche", "Les Étoiles"), source: .music) == PlayerSource(source: .music, volume: 55, track: NowPlaying(source: .music, title: "Nuit blanche", artist: "Les Étoiles", isPlaying: true)))
check("source ouverte sans titre : garde son volume", PlayerSource.parse(sourceReadout("30", "stopped", "", ""), source: .spotify) == PlayerSource(source: .spotify, volume: 30, track: nil))
check("source : volume hors 0-100 ou illisible refusé", PlayerSource.parse(sourceReadout("120", "playing", "a", "b"), source: .music) == nil && PlayerSource.parse(sourceReadout("fort", "playing", "a", "b"), source: .music) == nil && PlayerSource.parse("", source: .music) == nil)
check("volume borné entre 0 et 100", clampedVolume(-5) == 0 && clampedVolume(140) == 100 && clampedVolume(37) == 37)
let silentMusic = PlayerSource(source: .music, volume: 50, track: nil)
let playingSpot = PlayerSource(source: .spotify, volume: 40, track: playingSpotify)
check("source pilotée : le choix de l'utilisateur d'abord", controlledSource(selected: .music, among: [silentMusic, playingSpot]) == silentMusic)
check("source pilotée : sans choix, celle qui joue", controlledSource(selected: nil, among: [silentMusic, playingSpot]) == playingSpot)
check("source pilotée : choix fermé, on revient à ce qui joue, puis à la première", controlledSource(selected: .music, among: [playingSpot]) == playingSpot && controlledSource(selected: nil, among: [silentMusic]) == silentMusic && controlledSource(selected: nil, among: []) == nil)
check("le relevé n'écrase pas un réglage tout juste fait", reconciledVolume(read: 60, local: 25, holdUntil: t0.addingTimeInterval(1.5), now: t0) == 25)
check("le maintien passé, le relevé reprend la main", reconciledVolume(read: 60, local: 25, holdUntil: t0.addingTimeInterval(1.5), now: t0.addingTimeInterval(2)) == 60 && reconciledVolume(read: 60, local: nil, holdUntil: nil, now: t0) == 60)
check("couper garde l'ancien niveau", togglingMute(currentVolume: 70, restoreTo: nil) == (0, 70))
check("rétablir remet le niveau gardé, puis l'oublie", togglingMute(currentVolume: 0, restoreTo: 70) == (70, nil))
check("rétablir sans niveau connu : 50", togglingMute(currentVolume: 0, restoreTo: nil) == (50, nil))
check("script de volume borné", volumeScript(150, for: .spotify) == "tell application \"Spotify\" to set sound volume to 100" && volumeScript(42, for: .music) == "tell application \"Music\" to set sound volume to 42")
check("script de lecture : demande aussi le volume", nowPlayingReadScript(for: .music).contains("sound volume"))


// Lecteur : pochette
check("pochette : la clé change avec le morceau, pas avec l'état", artworkKey(for: playingSpotify) == artworkKey(for: NowPlaying(source: .spotify, title: "b", artist: "", isPlaying: false)) && artworkKey(for: playingSpotify) != artworkKey(for: pausedMusic))
check("pochette : adresse de Spotify en https acceptée", isTrustedArtworkURL(URL(string: "https://i.scdn.co/image/ab67616d0000b273abc")!))
check("pochette : adresse hors du réseau de Spotify refusée", !isTrustedArtworkURL(URL(string: "https://evil.example.com/a.jpg")!) && !isTrustedArtworkURL(URL(string: "https://scdn.co.evil.com/a.jpg")!) && !isTrustedArtworkURL(URL(string: "https://notscdn.co/a.jpg")!))
check("pochette : http et schémas locaux refusés", !isTrustedArtworkURL(URL(string: "http://i.scdn.co/image/a")!) && !isTrustedArtworkURL(URL(string: "file:///etc/passwd")!))
check("pochette : taille bornée", isAcceptableArtworkSize(1) && isAcceptableArtworkSize(maxArtworkBytes) && !isAcceptableArtworkSize(0) && !isAcceptableArtworkSize(maxArtworkBytes + 1))
check("pochette : script de Musique et de Spotify", artworkReadScript(for: .music).contains("raw data of artwork 1") && artworkReadScript(for: .spotify).contains("artwork url"))


// Chrome : volume par onglet
func tabsLine(_ tabs: [[String: Any]], type: String = "tabs") -> Data {
    try! JSONSerialization.data(withJSONObject: ["type": type, "tabs": tabs])
}
let youtubeTab: [String: Any] = ["id": 12, "title": "Focus mix, 2 hours", "host": "www.youtube.com", "volume": 70]
check("onglets : une liste valide est lue", BrowserMessage.parseTabs(tabsLine([youtubeTab])) == [BrowserTab(id: 12, title: "Focus mix, 2 hours", host: "www.youtube.com", volume: 70)])
check("onglets : mauvais type, texte ou JSON refusés", BrowserMessage.parseTabs(tabsLine([youtubeTab], type: "autre")) == nil && BrowserMessage.parseTabs(Data("pas du json".utf8)) == nil && BrowserMessage.parseTabs(Data("{\"type\":\"tabs\"}".utf8)) == nil)
check("onglets : volume hors bornes ramené entre 0 et 100, absent : 100", {
    let tabs = BrowserMessage.parseTabs(tabsLine([["id": 1, "volume": 500], ["id": 2, "volume": -3], ["id": 3]]))
    return tabs?.map(\.volume) == [100, 0, 100]
}())
check("onglets : identifiant négatif ou absent ignoré", BrowserMessage.parseTabs(tabsLine([["id": -1], ["title": "x"], ["id": 4]]))?.map(\.id) == [4])
check("onglets : huit au plus", BrowserMessage.parseTabs(tabsLine((0 ..< 20).map { ["id": $0] }))?.count == BrowserMessage.maxTabs)
check("onglets : texte nettoyé", BrowserMessage.parseTabs(tabsLine([["id": 1, "title": "a\nb\u{202E}c", "host": "x.com"]]))?.first?.title == "a bc")
check("onglets : ligne trop longue refusée", BrowserMessage.parseTabs(Data(repeating: 0x20, count: BrowserMessage.maxLineBytes + 1)) == nil)
check("ordre d'envoi du volume : une ligne JSON bornée", {
    let line = String(decoding: BrowserMessage.setVolumeLine(tabID: 12, volume: 250), as: UTF8.self)
    return line == "{\"tabId\":12,\"type\":\"setVolume\",\"volume\":100}\n"
}())
check("nom du site : youtube, sous-domaine, inconnu, vide", browserHostLabel("www.youtube.com") == "YouTube" && browserHostLabel("open.spotify.com") == "Spotify" && browserHostLabel("music.bandcamp.com") == "Bandcamp" && browserHostLabel("") == "Onglet" && browserHostLabel("localhost") == "Localhost")
check("onglets triés par numéro", sortedForDisplay([BrowserTab(id: 9, title: "", host: "", volume: 1), BrowserTab(id: 3, title: "", host: "", volume: 1)]).map(\.id) == [3, 9])


// Volume du Mac
check("volume du Mac : un entier de 0 à 100", parseSystemVolume("69") == 69 && parseSystemVolume(" 0\n") == 0 && parseSystemVolume("100") == 100)
check("volume du Mac : sortie sans réglage ou illisible", parseSystemVolume("missing value") == nil && parseSystemVolume(nil) == nil && parseSystemVolume("101") == nil && parseSystemVolume("-1") == nil && parseSystemVolume("") == nil)
check("script de volume du Mac borné", systemVolumeScript(42) == "set volume output volume 42" && systemVolumeScript(300) == "set volume output volume 100" && systemVolumeScript(-9) == "set volume output volume 0")
check("script de lecture du volume du Mac", systemVolumeReadScript == "output volume of (get volume settings)")

print("\n\(passed) réussis, \(failed) échec(s)")
exit(failed == 0 ? 0 : 1)
