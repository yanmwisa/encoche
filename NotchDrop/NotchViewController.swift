//
//  NotchViewController.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//

import AppKit
import Cocoa
import SwiftUI

class NotchViewController: NSHostingController<NotchView> {
    init(_ vm: NotchViewModel) {
        super.init(rootView: .init(vm: vm))
    }

    /// L'encoche s'ouvre sans activer l'application : le premier clic sur un bouton doit compter.
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}

private final class FirstMouseHostingView: NSHostingView<NotchView> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}
