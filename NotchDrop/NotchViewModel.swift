import Cocoa
import Combine
import Foundation
import LaunchAtLogin
import SwiftUI

class NotchViewModel: NSObject, ObservableObject {
    var cancellables: Set<AnyCancellable> = []
    let inset: CGFloat

    init(inset: CGFloat = -4, sessionStore: SessionStore = SessionStore()) {
        self.inset = inset
        self.sessionStore = sessionStore
        super.init()
        setupCancellables()
    }

    deinit {
        destroy()
    }

    let animation: Animation = .interactiveSpring(
        duration: 0.5,
        extraBounce: 0.25,
        blendDuration: 0.125
    )
    /// La hauteur laisse la bande de l'encoche matérielle vide, puis la barre d'onglets, puis l'écran choisi.
    let notchOpenedSize: CGSize = .init(width: 600, height: 184)
    let dropDetectorRange: CGFloat = 32

    enum Status: String, Codable, Hashable, Equatable {
        case closed
        case opened
        case popping
        case notification
        case sessionAlert
    }

    enum OpenReason: String, Codable, Hashable, Equatable {
        case click
        case drag
        case boot
        case request
        case unknown
    }

    enum ContentType: Int, Codable, Hashable, Equatable {
        case normal
        case sessions
        case player
        case menu
        case settings
    }

    var notchOpenedRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notchOpenedSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - notchOpenedSize.height,
            width: notchOpenedSize.width,
            height: notchOpenedSize.height
        )
    }

    @Published private(set) var status: Status = .closed
    @Published var openReason: OpenReason = .unknown
    @Published var contentType: ContentType = .normal

    @Published var spacing: CGFloat = 16
    @Published var cornerRadius: CGFloat = 16
    @Published var deviceNotchRect: CGRect = .zero
    @Published var screenRect: CGRect = .zero
    @Published var optionKeyPressed: Bool = false
    @Published var notchVisible: Bool = true

    // Sessions Claude Code : l'état vit dans le magasin partagé, l'encoche n'en garde que ce qu'elle montre.
    let sessionStore: SessionStore
    @Published private(set) var sessionSummary: NotchSummary = describeNotch([])
    @Published private(set) var pendingRequests: [PendingRequest] = []
    @Published private(set) var nowPlaying: NowPlaying?

    // Carte de notification (prototype)
    @Published var incoming: IncomingMessage?
    @Published var notificationPhase: NotificationPhase = .banner
    var pendingMessage: IncomingMessage?
    var nextSampleIndex = 0
    let autoDismiss = AutoDismissTimer()

    @PublishedPersist(key: "selectedLanguage", defaultValue: .system)
    var selectedLanguage: Language

    @PublishedPersist(key: "hapticFeedback", defaultValue: true)
    var hapticFeedback: Bool

    let hapticSender = PassthroughSubject<Void, Never>()

    func notchOpen(_ reason: OpenReason) {
        openReason = reason
        status = .opened
        contentType = .normal
        NSApp.activate(ignoringOtherApps: true)
    }

    func notchClose() {
        openReason = .unknown
        status = .closed
        contentType = .normal
        autoDismiss.cancel()
        incoming = nil
        notificationPhase = .banner
        showPendingNotificationAfterClose()
        refreshSessionAlert()
    }

    func notchSessionAlert() {
        openReason = .unknown
        status = .sessionAlert
    }

    func updateSessionSummary(_ summary: NotchSummary) {
        // Comptes seulement, jamais de noms ni de commandes : ce journal reste lisible par d'autres outils.
        NSLog("Encoche : %d session(s), %d en attente", summary.rows.count, summary.waitingCount)
        sessionSummary = summary
        refreshSessionAlert()
    }

    /// Ce que montrent les oreilles : une alerte de session d'abord, sinon la musique qui joue.
    var currentEars: EarsContent? {
        earsContent(sessionEars: sessionSummary.ears, nowPlaying: nowPlaying)
    }

    func updateNowPlaying(_ track: NowPlaying?) {
        guard track != nowPlaying else { return }
        nowPlaying = track
        refreshSessionAlert()
    }

    func updatePendingRequests(_ requests: [PendingRequest]) {
        let previousCount = permissionCount(in: pendingRequests)
        pendingRequests = requests
        switch requestPanelAction(
            statusRaw: status.rawValue,
            openedByRequest: openReason == .request,
            permissionCount: permissionCount(in: requests),
            previousPermissionCount: previousCount
        ) {
        case .open: notchOpenForRequest()
        case .close: notchClose()
        case .none: break
        }
    }

    /// S'ouvre sur la demande sans activer l'application : la frappe en cours au clavier n'est pas volée.
    func notchOpenForRequest() {
        openReason = .request
        status = .opened
        contentType = .sessions
    }

    func notchNotify() {
        openReason = .unknown
        status = .notification
        contentType = .normal
    }

    func showSettings() {
        contentType = .settings
    }

    func notchPop() {
        openReason = .unknown
        status = .popping
    }
}
