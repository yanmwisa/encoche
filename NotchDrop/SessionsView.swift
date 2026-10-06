//
//  SessionsView.swift
//  NotchDrop
//
//  Les sessions dans l'encoche : mascotte, oreilles de l'encoche fermée, liste de l'encoche ouverte.
//

import SwiftUI

enum SessionPalette {
    static let mascot = Color(red: 215 / 255, green: 119 / 255, blue: 87 / 255)
    static let attention = Color(red: 0.949, green: 0.757, blue: 0.306)
    static let working = Color(red: 0.941, green: 0.643, blue: 0.365)
    static let done = Color(red: 0.435, green: 0.816, blue: 0.549)

    static func color(for phase: SessionPhase) -> Color {
        switch phase {
        case .approval, .question: attention
        case .working: working
        case .done: done
        }
    }
}

/// Silhouette du terminal de Claude Code : tête, bras, corps, quatre pattes.
/// Dessinée ici d'après ce que le terminal affiche ; ce n'est pas un fichier officiel.
private enum MascotCells {
    static let columns: CGFloat = 13
    static let rows: CGFloat = 8
    static let body: [CGRect] = [
        CGRect(x: 2, y: 0, width: 9, height: 2),
        CGRect(x: 0, y: 2, width: 13, height: 2),
        CGRect(x: 2, y: 4, width: 9, height: 2),
        CGRect(x: 2, y: 6, width: 1, height: 2),
        CGRect(x: 4, y: 6, width: 1, height: 2),
        CGRect(x: 8, y: 6, width: 1, height: 2),
        CGRect(x: 10, y: 6, width: 1, height: 2),
    ]
    static let eyes: [CGRect] = [
        CGRect(x: 3, y: 1, width: 1, height: 1),
        CGRect(x: 9, y: 1, width: 1, height: 1),
    ]
}

private struct CellsShape: Shape {
    let cells: [CGRect]

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / MascotCells.columns
        var path = Path()
        for cell in cells {
            path.addRect(CGRect(
                x: rect.minX + cell.minX * unit,
                y: rect.minY + cell.minY * unit,
                width: cell.width * unit,
                height: cell.height * unit
            ))
        }
        return path
    }
}

struct MascotView: View {
    let phase: SessionPhase
    var width: CGFloat = 18

    @State private var isHopping = false

    private var bodyColor: Color {
        switch phase {
        case .approval, .question: SessionPalette.mascot
        case .working: SessionPalette.mascot.opacity(0.55)
        case .done: SessionPalette.done
        }
    }

    var body: some View {
        ZStack {
            CellsShape(cells: MascotCells.body).fill(bodyColor)
            CellsShape(cells: MascotCells.eyes).fill(.black)
        }
        .frame(width: width, height: width * MascotCells.rows / MascotCells.columns)
        .offset(y: phase.needsUser && isHopping ? -2 : 0)
        .animation(
            phase.needsUser ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
            value: isHopping
        )
        .onAppear { isHopping = true }
        .accessibilityHidden(true)
    }
}

/// L'encoche fermée, élargie : la mascotte et le nom à gauche, le type de demande à droite,
/// la caméra au milieu.
struct SessionEarsView: View {
    let ears: SessionEars
    let notchWidth: CGFloat
    let earWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0 ..< ears.mascotCount, id: \.self) { _ in
                    MascotView(phase: ears.tone == .finished ? .done : .question, width: 18)
                }
                if !ears.left.isEmpty {
                    Text(ears.left)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: earWidth - 12, alignment: .leading)
            Spacer(minLength: notchWidth)
            Text(ears.right)
                .foregroundStyle(ears.tone == .finished ? SessionPalette.done : SessionPalette.attention)
                .lineLimit(1)
                .frame(width: earWidth - 12, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(width: notchWidth + earWidth * 2, height: height)
    }
}

/// La liste de l'encoche ouverte : ce qui attend en premier, puis ce qui travaille, puis ce qui a fini.
struct SessionsListView: View {
    let summary: NotchSummary
    let onGoTo: (AgentSession) -> Void
    /// Faux pour le rendu hors écran : un défilement n'est pas dessiné par ImageRenderer.
    var isScrollable = true

    var body: some View {
        // Pas de ligne de comptes : l'onglet Sessions porte déjà le nombre de sessions qui attendent,
        // et la place sert à montrer les sessions.
        VStack(alignment: .leading, spacing: 8) {
            if summary.rows.isEmpty {
                Text("No Claude Code session found. Sessions appear as soon as one starts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else if isScrollable {
                ScrollView { rows }
                    .scrollIndicators(.never)
            } else {
                rows
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(summary.rows) { session in
                SessionRowView(session: session, onGoTo: { onGoTo(session) })
            }
        }
    }
}

private struct SessionRowView: View {
    let session: AgentSession
    let onGoTo: () -> Void

    private var rowTint: Color {
        if session.phase.needsUser { return SessionPalette.attention.opacity(0.12) }
        return session.hasUnseenFinish ? SessionPalette.done.opacity(0.14) : Color.white.opacity(0.06)
    }

    var body: some View {
        HStack(spacing: 10) {
            MascotView(phase: session.phase, width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    PhaseChip(phase: session.phase)
                }
                Text(session.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if session.hostPID != nil {
                Button("Go to", action: onGoTo)
                    .buttonStyle(GoButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowTint)
        )
    }
}

private struct PhaseChip: View {
    let phase: SessionPhase

    var body: some View {
        Text(phase.label)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .foregroundStyle(phase.needsUser ? Color.black.opacity(0.85) : SessionPalette.color(for: phase))
            .background(Capsule().fill(phase.needsUser ? SessionPalette.attention : Color.clear))
            .overlay(Capsule().stroke(phase.needsUser ? Color.clear : SessionPalette.color(for: phase).opacity(0.5), lineWidth: 1))
    }
}

private struct GoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.24 : 0.14)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
