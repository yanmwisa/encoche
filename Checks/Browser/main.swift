//
//  Vérifications du pont avec Chrome : le vrai hôte de messagerie native (Python), le vrai socket, le vrai décodage.
//  Chrome est simulé par le cadrage de messagerie native (4 octets de longueur, puis du JSON).
//  Lancer : ./scripts/check-browser-bridge.sh
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

func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return condition()
}

final class Received {
    private let lock = NSLock()
    private var tabsLists: [[BrowserTab]] = []
    private var disconnects = 0
    func add(_ tabs: [BrowserTab]) { lock.lock(); tabsLists.append(tabs); lock.unlock() }
    func addDisconnect() { lock.lock(); disconnects += 1; lock.unlock() }
    var all: [[BrowserTab]] { lock.lock(); defer { lock.unlock() }; return tabsLists }
    var disconnectCount: Int { lock.lock(); defer { lock.unlock() }; return disconnects }
}

// Un chemin court : un socket Unix est limité à 103 octets.
let home = URL(fileURLWithPath: "/tmp/encb-\(UInt32.random(in: 0 ... 999_999))")
defer { try? FileManager.default.removeItem(at: home) }
let socketURL = home.appendingPathComponent("Library/Application Support/Encoche/browser.sock")
let hostPath = CommandLine.arguments[1]

/// Un « Chrome » : lance l'hôte, lui écrit des messages cadrés, lit ce qu'il renvoie.
final class FakeChrome {
    let process = Process()
    let input = Pipe()
    let output = Pipe()

    init() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [hostPath]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        process.standardInput = input
        process.standardOutput = output
        try! process.run()
    }

    func send(_ json: String) {
        let body = Data(json.utf8)
        var size = UInt32(body.count).littleEndian
        input.fileHandleForWriting.write(Data(bytes: &size, count: 4) + body)
    }

    /// Le prochain message de l'hôte : 4 octets de longueur, puis le JSON.
    func readMessage() -> String? {
        let header = output.fileHandleForReading.readData(ofLength: 4)
        guard header.count == 4 else { return nil }
        let size = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        let body = output.fileHandleForReading.readData(ofLength: size)
        return String(decoding: body, as: UTF8.self)
    }

    func close() { try? input.fileHandleForWriting.close() }
}

let received = Received()
let server = BrowserBridgeServer(socketURL: socketURL, onTabs: { received.add($0) }, onDisconnect: { received.addDisconnect() })
do { try server.start() } catch { print("ECHEC le pont ne démarre pas : \(error)"); exit(1) }

var info = stat()
stat(socketURL.path, &info)
check("le socket du pont est en 0600", info.st_mode & 0o777 == 0o600)
stat(socketURL.deletingLastPathComponent().path, &info)
check("le dossier est en 0700", info.st_mode & 0o777 == 0o700)

let chrome = FakeChrome()
Thread.sleep(forTimeInterval: 3.5)  // l'hôte réessaie de se connecter toutes les 3 s : il a trouvé le socket

chrome.send(#"{"type":"tabs","tabs":[{"id":12,"title":"Mix concentration","host":"www.youtube.com","volume":70}]}"#)
check("les onglets annoncés par Chrome arrivent à l'app", waitUntil { received.all.last == [BrowserTab(id: 12, title: "Mix concentration", host: "www.youtube.com", volume: 70)] })

chrome.send("pas du json")
chrome.send(#"{"type":"autre"}"#)
chrome.send(#"{"type":"tabs","tabs":[{"id":13,"volume":40}]}"#)
check("un message invalide est ignoré, le suivant passe", waitUntil { received.all.last?.first?.id == 13 } && received.all.count == 2)

server.setVolume(tabID: 12, volume: 40)
let reply = chrome.readMessage()
check("l'ordre de volume de l'app arrive à Chrome, cadré", reply == #"{"tabId":12,"type":"setVolume","volume":40}"#)

chrome.send(#"{"type":"tabs","tabs":[]}"#)
check("une liste vide d'onglets est transmise", waitUntil { received.all.last?.isEmpty == true })

chrome.close()
check("Chrome ferme l'entrée : l'hôte s'arrête", waitUntil { !chrome.process.isRunning })
check("l'app apprend que l'extension est partie", waitUntil { received.disconnectCount == 1 })

// App fermée : l'hôte garde la main, jette les messages, et s'arrête quand Chrome ferme.
server.stop()
let lonely = FakeChrome()
lonely.send(#"{"type":"tabs","tabs":[{"id":1}]}"#)
Thread.sleep(forTimeInterval: 0.5)
check("sans app, l'hôte reste en vie", lonely.process.isRunning)
lonely.close()
check("sans app, l'hôte s'arrête quand Chrome ferme", waitUntil(timeout: 4) { !lonely.process.isRunning })

print("\n\(passed) réussis, \(failed) échec(s)")
exit(failed == 0 ? 0 : 1)
