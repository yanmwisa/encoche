//
//  NotificationModel.swift
//  NotchDrop
//
//  Prototype : messages fictifs pour juger la carte de notification.
//  Aucune donnée réelle, aucun accès aux vraies notifications.
//

import Foundation
import SwiftUI

enum MessageApp: Equatable {
    case iMessage
    case whatsApp

    var displayName: String {
        switch self {
        case .iMessage: "Messages"
        case .whatsApp: "WhatsApp"
        }
    }

    var symbolName: String {
        switch self {
        case .iMessage: "message.fill"
        case .whatsApp: "phone.bubble.fill"
        }
    }

    var badgeColor: Color {
        switch self {
        case .iMessage: Color(red: 0.204, green: 0.78, blue: 0.349)
        case .whatsApp: Color(red: 0.145, green: 0.827, blue: 0.4)
        }
    }
}

struct IncomingMessage: Identifiable, Equatable {
    let id = UUID()
    let app: MessageApp
    let sender: String
    let text: String
}

extension IncomingMessage {
    private static let samples: [(app: MessageApp, sender: String, text: String)] = [
        (.iMessage, "Marie D.", "Tu passes ce soir ? On t'a gardé une place."),
        (.whatsApp, "Groupe Équipe", "Rappel : la réunion commence dans 10 minutes."),
        (.iMessage, "Julien", "J'ai envoyé le fichier, dis-moi si tu le reçois bien."),
        (.whatsApp, "Awa", "Merci pour hier ! On s'appelle demain matin ?"),
    ]

    static func sample(at index: Int) -> IncomingMessage {
        let sample = samples[index % samples.count]
        return IncomingMessage(app: sample.app, sender: sample.sender, text: sample.text)
    }
}

/// Étapes de la carte. Chaque étape décide seule de sa taille et de son temps de vie.
enum NotificationPhase: Equatable {
    case banner
    case composing
    case sent

    /// Secondes avant disparition automatique ; nil tant que l'utilisateur écrit.
    var autoDismissDelay: TimeInterval? {
        switch self {
        case .banner: 7
        case .composing: nil
        case .sent: 1.4
        }
    }

    /// Hauteur sous la ligne de l'encoche matérielle.
    var contentHeight: CGFloat {
        switch self {
        case .banner, .sent: 114
        case .composing: 120
        }
    }
}
