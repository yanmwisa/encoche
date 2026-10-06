//
//  NextStepsCardView.swift
//  NotchDrop
//
//  Les étapes proposées par la session : on les touche dans l'ordre voulu, puis « Lancer ».
//  L'encoche ne renvoie que des numéros : le texte des étapes reste dans la session.
//

import SwiftUI

struct NextStepsCardView: View {
    let sessionName: String
    let labels: [String]
    let position: String
    let showsPosition: Bool
    let onLaunch: ([Int]) -> Void

    @State private var picked: [Int]

    init(
        sessionName: String, labels: [String], position: String, showsPosition: Bool,
        onLaunch: @escaping ([Int]) -> Void, initiallyPicked: [Int] = []
    ) {
        self.sessionName = sessionName
        self.labels = labels
        self.position = position
        self.showsPosition = showsPosition
        self.onLaunch = onLaunch
        _picked = State(initialValue: initiallyPicked)
    }

    private var launchTitle: String {
        picked.isEmpty ? "Launch" : "Launch " + picked.map { String($0 + 1) }.joined(separator: " then ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 2) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    optionRow(index: index, label: label)
                }
            }
            HStack(spacing: 8) {
                Button(launchTitle) { onLaunch(picked) }
                    .buttonStyle(StepButtonStyle(fill: SessionPalette.done, text: Color(red: 0.03, green: 0.13, blue: 0.06)))
                    .disabled(picked.isEmpty)
                    .opacity(picked.isEmpty ? 0.4 : 1)
                Button("Clear") { picked = [] }
                    .buttonStyle(StepButtonStyle(fill: .white.opacity(0.14), text: .white))
                    .disabled(picked.isEmpty)
                    .opacity(picked.isEmpty ? 0.4 : 1)
                Spacer(minLength: 8)
                Text(showsPosition ? "\(sessionName) · \(position)" : sessionName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func optionRow(index: Int, label: String) -> some View {
        let rank = picked.firstIndex(of: index).map { $0 + 1 }
        return Button {
            picked = togglingStep(picked, index)
        } label: {
            HStack(spacing: 8) {
                Text(String(index + 1))
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(RoundedRectangle(cornerRadius: 5).fill(rank == nil ? .white.opacity(0.12) : SessionPalette.working))
                    .foregroundStyle(rank == nil ? Color.white : Color.black.opacity(0.85))
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if let rank {
                    Text("step \(rank)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SessionPalette.working)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 18)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(rank == nil ? .white.opacity(0.07) : SessionPalette.working.opacity(0.18)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct StepButtonStyle: ButtonStyle {
    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
