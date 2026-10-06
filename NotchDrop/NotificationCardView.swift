//
//  NotificationCardView.swift
//  NotchDrop
//
//  Carte de notification qui sort de l'encoche (prototype, fausses données).
//

import SwiftUI

struct NotificationCardView: View {
    @ObservedObject var vm: NotchViewModel
    let message: IncomingMessage

    @State private var replyText = ""
    @State private var isHovering = false
    @FocusState private var replyFieldFocused: Bool

    private var trimmedReply: String {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            messageBody
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(
            width: vm.notificationSize.width,
            height: vm.notificationSize.height,
            alignment: .top
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            vm.notificationHoverChanged(hovering)
        }
        .onExitCommand { vm.notificationDismiss() }
        .animation(vm.notificationAnimation, value: vm.notificationPhase)
    }

    // Même hauteur que l'encoche matérielle : le texte reste de part et d'autre de la caméra.
    private var header: some View {
        HStack(spacing: 8) {
            AppBadge(app: message.app)
            Text(message.app.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("maintenant")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button { vm.notificationDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .accessibilityLabel("Fermer")
        }
        .frame(height: vm.deviceNotchRect.height)
    }

    private var messageBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.sender)
                .font(.headline)
                .lineLimit(1)
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch vm.notificationPhase {
        case .banner:
            HStack {
                Spacer()
                Button("Répondre") { vm.notificationBeginReply() }
                    .buttonStyle(PillButtonStyle())
            }
            .transition(footerTransition)
        case .composing:
            HStack(spacing: 8) {
                TextField("Répondre à \(message.sender)", text: $replyText)
                    .textFieldStyle(.plain)
                    .focused($replyFieldFocused)
                    .onSubmit { vm.notificationSendReply(replyText) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.14)))
                Button { vm.notificationSendReply(replyText) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(message.app.badgeColor)
                }
                .buttonStyle(.plain)
                .disabled(trimmedReply.isEmpty)
                .opacity(trimmedReply.isEmpty ? 0.35 : 1)
                .accessibilityLabel("Envoyer")
            }
            .transition(footerTransition)
            .onAppear {
                DispatchQueue.main.async { replyFieldFocused = true }
            }
        case .sent:
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: vm.notificationPhase)
                Text("Envoyé")
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            .transition(footerTransition)
        }
    }

    private var footerTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
    }
}

private struct AppBadge: View {
    let app: MessageApp

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(app.badgeColor)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: app.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

/// Bouton en pilule qui s'enfonce légèrement quand on appuie, comme les boutons du système.
private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.24 : 0.14)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
