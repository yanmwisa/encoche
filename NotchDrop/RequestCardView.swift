//
//  RequestCardView.swift
//  NotchDrop
//
//  La demande d'une session dans l'encoche : une autorisation à donner, ou des étapes à choisir.
//

import SwiftUI

struct RequestCardView: View {
    let request: PendingRequest
    let position: String
    let showsPosition: Bool
    let onReply: (RequestReply) -> Void

    var body: some View {
        switch request.kind {
        case let .permission(tool, summary):
            ApprovalCardView(
                sessionName: request.sessionName, tool: tool, summary: summary,
                position: position, showsPosition: showsPosition,
                onAnswer: { onReply(.decision($0)) }
            )
        case let .nextSteps(labels):
            NextStepsCardView(
                sessionName: request.sessionName, labels: labels,
                position: position, showsPosition: showsPosition,
                onLaunch: { onReply(.sequence($0)) }
            )
        }
    }
}
