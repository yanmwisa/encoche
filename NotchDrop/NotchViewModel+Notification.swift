//
//  NotchViewModel+Notification.swift
//  NotchDrop
//
//  Comportement de la carte de notification (prototype, fausses données).
//

import Cocoa
import SwiftUI

extension NotchViewModel {
    static let notificationWidth: CGFloat = 460

    /// Plus doux que le ressort d'ouverture : la carte change de forme sans rebondir.
    var notificationAnimation: Animation {
        .spring(response: 0.45, dampingFraction: 0.82)
    }

    var notificationSize: CGSize {
        .init(
            width: Self.notificationWidth,
            height: deviceNotchRect.height + notificationPhase.contentHeight
        )
    }

    var notificationRect: CGRect {
        .init(
            x: screenRect.origin.x + (screenRect.width - notificationSize.width) / 2,
            y: screenRect.origin.y + screenRect.height - notificationSize.height,
            width: notificationSize.width,
            height: notificationSize.height
        )
    }

    func notificationShowNextSample() {
        let message = IncomingMessage.sample(at: nextSampleIndex)
        nextSampleIndex += 1
        notificationShow(message)
    }

    func notificationShow(_ message: IncomingMessage) {
        // Panneau déjà ouvert : on attend sa fermeture plutôt que de le recouvrir.
        guard status != .opened else {
            pendingMessage = message
            return
        }
        incoming = message
        notificationPhase = .banner
        notchNotify()
        hapticSender.send()
        scheduleAutoDismiss()
    }

    func notificationBeginReply() {
        guard status == .notification else { return }
        notificationPhase = .composing
        autoDismiss.cancel()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0 is NotchWindow }?.makeKeyAndOrderFront(nil)
    }

    func notificationSendReply(_ text: String) {
        guard status == .notification else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Prototype : rien n'est envoyé, on montre seulement la confirmation.
        notificationPhase = .sent
        hapticSender.send()
        scheduleAutoDismiss()
    }

    func notificationDismiss() {
        guard status == .notification else { return }
        notchClose()
    }

    func notificationHoverChanged(_ isHovering: Bool) {
        guard status == .notification else { return }
        if isHovering {
            autoDismiss.cancel()
        } else {
            scheduleAutoDismiss()
        }
    }

    func showPendingNotificationAfterClose() {
        guard let message = pendingMessage else { return }
        pendingMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.notificationShow(message)
        }
    }

    private func scheduleAutoDismiss() {
        autoDismiss.cancel()
        guard let delay = notificationPhase.autoDismissDelay else { return }
        autoDismiss.schedule(after: delay) { [weak self] in
            self?.notificationDismiss()
        }
    }
}

/// Une seule minuterie à la fois : en programmer une nouvelle annule l'ancienne.
final class AutoDismissTimer {
    private var pendingAction: DispatchWorkItem?

    func schedule(after seconds: TimeInterval, _ action: @escaping () -> Void) {
        cancel()
        let item = DispatchWorkItem(block: action)
        pendingAction = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func cancel() {
        pendingAction?.cancel()
        pendingAction = nil
    }
}
