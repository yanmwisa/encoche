//
//  TrayScroll.swift
//  NotchDrop
//
//  Défilement de la tablette quand elle contient plus de fichiers qu'elle n'en montre : sans effet de bord.
//  Ce fichier n'importe que Foundation pour pouvoir être testé seul.
//

import Foundation

enum TrayScrollDirection {
    case earlier
    case later
}

enum TrayScroll {
    /// Fichiers visibles d'un coup, à peu près, dans la largeur de l'encoche ouverte.
    static let visibleCount = 4

    /// Les flèches ne servent que s'il y a des fichiers hors de vue.
    static func needsArrows(itemCount: Int) -> Bool {
        itemCount > visibleCount
    }

    /// Le fichier à amener en vue : une page plus loin ou plus tôt, sans jamais sortir de la liste.
    static func targetIndex(current: Int, direction: TrayScrollDirection, itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let step = direction == .later ? visibleCount : -visibleCount
        return min(max(current + step, 0), itemCount - 1)
    }
}
