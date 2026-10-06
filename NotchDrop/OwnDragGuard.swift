//
//  OwnDragGuard.swift
//  NotchDrop
//
//  Distingue un fichier de la tablette que l'on déplace (à ne pas recopier) d'un fichier venu de l'extérieur.
//

/// Un fichier sorti de la tablette puis relâché sur elle repartait en copie : chaque déplacement ajoutait un doublon.
/// Le glissement est marqué au départ ; tout nouveau clic, ou un dépôt, le remet à zéro.
struct OwnDragGuard {
    private(set) var isDraggingOwnItem = false

    mutating func beginOwnDrag() {
        isDraggingOwnItem = true
    }

    /// Vrai si le dépôt vient de la tablette elle-même et doit être ignoré. Le dépôt clôt le glissement.
    mutating func shouldIgnoreDrop() -> Bool {
        defer { isDraggingOwnItem = false }
        return isDraggingOwnItem
    }

    mutating func reset() {
        isDraggingOwnItem = false
    }
}
