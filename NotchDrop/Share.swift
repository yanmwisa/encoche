//
//  Share.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//  Last Modified by 冷月 on 2025/5/5.
//

import Cocoa

class Share: NSObject, NSSharingServiceDelegate {
    /// Le service de partage et son délégué doivent survivre à `begin()` : relâchés trop tôt, la fenêtre d'AirDrop ne s'affiche jamais.
    private static var inProgress = Set<Share>()
    private var service: NSSharingService?

    let files: [URL]
    let serviceName: NSSharingService.Name?

    init(files: [URL], serviceName: NSSharingService.Name? = nil) {
        self.files = files
        self.serviceName = serviceName
        super.init()
    }

    func begin() {
        do {
            try sendEx(files)
        } catch {
            NSAlert.popError(error)
        }
    }

    private func sendEx(_ files: [URL]) throws {
        if let serviceName {
            guard let service = NSSharingService(named: serviceName) else {
                throw NSError(domain: "ShareService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Selected sharing service not available", comment: ""),
                ])
            }

            guard service.canPerform(withItems: files) else {
                throw NSError(domain: "ShareService", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Sharing service cannot perform with given files", comment: ""),
                ])
            }

            service.delegate = self
            self.service = service
            Self.inProgress.insert(self)
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: files)
        } else {
            // 弹出分享面板
            let picker = NSSharingServicePicker(items: files)
            if let view = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        }
    }

    func sharingService(_: NSSharingService, didShareItems _: [Any]) { finish() }

    func sharingService(_: NSSharingService, didFailToShareItems _: [Any], error: Error) {
        finish()
        guard (error as NSError).code != NSUserCancelledError else { return }
        NSAlert.popError(error)
    }

    private func finish() {
        Self.inProgress.remove(self)
        service = nil
    }
}
