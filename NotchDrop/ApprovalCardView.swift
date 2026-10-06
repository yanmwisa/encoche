//
//  ApprovalCardView.swift
//  NotchDrop
//
//  La demande d'autorisation d'une session, avec ses deux réponses : Autoriser ou Refuser.
//

import SwiftUI

struct ApprovalCardView: View {
    let sessionName: String
    let tool: String
    let summary: String
    let position: String
    let showsPosition: Bool
    let onAnswer: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MascotView(phase: .approval, width: 20)
                Text(sessionName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(tool.isEmpty ? "Autorisation" : tool)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1.5)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .background(Capsule().fill(SessionPalette.attention))
                Spacer(minLength: 8)
                if showsPosition {
                    Text(position)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Text(summary.isEmpty ? "Demande une autorisation" : summary)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
                .help(summary)
            HStack(spacing: 8) {
                Button("Autoriser") { onAnswer(.allow) }
                    .buttonStyle(ApprovalButtonStyle(fill: SessionPalette.done, text: Color(red: 0.03, green: 0.13, blue: 0.06)))
                Button("Refuser") { onAnswer(.deny) }
                    .buttonStyle(ApprovalButtonStyle(fill: Color(red: 0.94, green: 0.48, blue: 0.42).opacity(0.22), text: Color(red: 0.94, green: 0.48, blue: 0.42)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ApprovalButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(text)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
