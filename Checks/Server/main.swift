//
//  Vérifications de la réception des sessions : le vrai script de hook, le vrai socket, le vrai décodage.
//  Lancer : ./scripts/check-sessions-server.sh
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

// Un chemin court : un socket Unix est limité à 103 octets.
let shortHome = URL(fileURLWithPath: "/tmp/enc-\(UInt32.random(in: 0 ... 999_999))")
let shortSocketURL = shortHome.appendingPathComponent("Library/Application Support/Encoche/sessions.sock")
defer { try? FileManager.default.removeItem(at: shortHome) }

let hookPath = CommandLine.arguments[1]

final class Collector {
    private let lock = NSLock()
    private(set) var events: [SessionEvent] = []
    func add(_ event: SessionEvent) {
        lock.lock(); events.append(event); lock.unlock()
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
}

func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return condition()
}

/// Lance le vrai script et rend ce qu'il écrit sur sa sortie. Le délai d'attente d'une autorisation est court : un test ne doit jamais attendre 60 s.
@discardableResult
func runHook(sending json: String, home: URL) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [hookPath]
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "ENCOCHE_APPROVAL_TIMEOUT": "2"]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try! process.run()
    input.fileHandleForWriting.write(Data(json.utf8))
    try? input.fileHandleForWriting.close()
    let printed = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: printed, as: UTF8.self)
}

let collector = Collector()
let server = SessionSocketServer(socketURL: shortSocketURL) { collector.add($0) }
do {
    try server.start()
} catch {
    print("ECHEC le serveur ne démarre pas : \(error)")
    exit(1)
}

// --- Permissions

var info = stat()
stat(shortSocketURL.path, &info)
check("le socket est en 0600", info.st_mode & 0o777 == 0o600)
stat(shortSocketURL.deletingLastPathComponent().path, &info)
check("le dossier est en 0700", info.st_mode & 0o777 == 0o700)

// --- Un événement du vrai script de hook

runHook(
    sending: #"{"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"/Users/example/my-project","tool_name":"Bash","tool_input":{"command":"git push"}}"#,
    home: shortHome
)
check("l'événement du script arrive", waitUntil { collector.count == 1 })
if let event = collector.events.first {
    check("session et dossier", event.sessionID == "abc" && event.cwd == "/Users/example/my-project")
    check("autorisation avec la commande", event.kind == .permissionRequested(tool: "Bash", summary: "git push"))
    check("le pid du parent est transmis", (event.hostPID ?? 0) > 0)
}

// --- Une autorisation avec réponse : le vrai script attend, l'app répond par le canal, le script sort la décision

let repliesDirectory = shortHome.appendingPathComponent("Library/Application Support/Encoche/replies")
let permissionJSON = #"{"hook_event_name":"PermissionRequest","session_id":"rep","cwd":"/tmp/projet","tool_name":"Bash","tool_input":{"command":"ls"}}"#
let answered = DispatchSemaphore(value: 0)
var printedDecision = ""
DispatchQueue.global().async {
    printedDecision = runHook(sending: permissionJSON, home: shortHome)
    answered.signal()
}
check("l'autorisation arrive avec son canal de réponse", waitUntil { collector.events.contains { $0.sessionID == "rep" && $0.replyID != nil } })
if let replyID = collector.events.first(where: { $0.sessionID == "rep" })?.replyID {
    check("le canal est un tube privé de l'utilisateur", {
        var pipeInfo = stat()
        return stat(repliesDirectory.appendingPathComponent(replyID).path, &pipeInfo) == 0
            && (pipeInfo.st_mode & S_IFMT) == S_IFIFO && pipeInfo.st_mode & 0o777 == 0o600
    }())
    check("répondre « autoriser » est remis au script", RequestReplyChannel.send(.decision(.allow), replyID: replyID, in: repliesDirectory))
    check("le script sort la décision d'autorisation", answered.wait(timeout: .now() + 3) == .success && printedDecision.contains(#""behavior":"allow""#))
    check("répondre une seconde fois échoue : le script n'attend plus", !RequestReplyChannel.send(.decision(.deny), replyID: replyID, in: repliesDirectory))
}
check("un identifiant dangereux n'écrit nulle part", !RequestReplyChannel.send(.decision(.allow), replyID: "../../x", in: repliesDirectory))
check("un fichier ordinaire n'est pas un canal", {
    let regular = repliesDirectory.appendingPathComponent("ordinaire-12345678")
    FileManager.default.createFile(atPath: regular.path, contents: Data())
    return !RequestReplyChannel.send(.decision(.allow), replyID: "ordinaire-12345678", in: repliesDirectory)
}())

// --- Rafale : tous les événements arrivent

let countBeforeBurst = collector.count
for index in 0 ..< 20 {
    runHook(sending: #"{"hook_event_name":"UserPromptSubmit","session_id":"s\#(index)","cwd":"/tmp"}"#, home: shortHome)
}
check("vingt événements en rafale, tous reçus", waitUntil { collector.count == countBeforeBurst + 20 })

// --- Ce qui ne doit pas passer

let before = collector.count
runHook(sending: "pas du json", home: shortHome)
runHook(sending: #"{"hook_event_name":"PreCompact","session_id":"x","cwd":"/tmp"}"#, home: shortHome)
runHook(sending: String(repeating: "x", count: SessionEvent.maxPayloadBytes + 100), home: shortHome)
Thread.sleep(forTimeInterval: 0.5)
check("JSON invalide, événement inconnu et message trop gros : refusés", collector.count == before)

// --- Instance plus récente : l'ancienne ne doit pas effacer le socket de la nouvelle

let newerCollector = Collector()
let newerServer = SessionSocketServer(socketURL: shortSocketURL) { newerCollector.add($0) }
do { try newerServer.start() } catch { print("ECHEC la nouvelle instance ne démarre pas : \(error)"); exit(1) }
server.stop()
check("l'ancienne instance laisse le socket de la nouvelle", FileManager.default.fileExists(atPath: shortSocketURL.path))
runHook(sending: #"{"hook_event_name":"Stop","session_id":"nouvelle","cwd":"/tmp"}"#, home: shortHome)
check("la nouvelle instance reçoit toujours", waitUntil { newerCollector.count == 1 })

newerServer.stop()
check("la dernière instance retire son socket", !FileManager.default.fileExists(atPath: shortSocketURL.path))

print("\n\(passed) réussis, \(failed) échec(s)")
exit(failed == 0 ? 0 : 1)
