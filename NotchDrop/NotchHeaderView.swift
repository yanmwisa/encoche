//
//  NotchHeaderView.swift
//  NotchDrop
//
//  La barre d'onglets de l'encoche ouverte : on voit où l'on est et comment changer d'écran.
//

import SwiftUI

struct NotchHeaderView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        NotchTabBar(
            selection: vm.contentType,
            waitingCount: vm.sessionSummary.waitingCount,
            onSelect: { vm.contentType = $0 }
        )
        .animation(vm.animation, value: vm.contentType)
    }
}

struct NotchTabBar: View {
    let selection: NotchViewModel.ContentType
    let waitingCount: Int
    let onSelect: (NotchViewModel.ContentType) -> Void

    var body: some View {
        HStack(spacing: 4) {
            NotchTab(title: "Files", symbol: "square.and.arrow.down", isSelected: selection == .normal) {
                onSelect(.normal)
            }
            NotchTab(title: "Sessions", symbol: "terminal", badge: waitingCount, isSelected: selection == .sessions) {
                onSelect(.sessions)
            }
            NotchTab(title: "Player", symbol: "play.fill", note: nil, isSelected: selection == .player) {
                onSelect(.player)
            }
            Spacer(minLength: 0)
            // Le menu et ses réglages partagent la même icône : l'un mène à l'autre.
            NotchTab(title: "Settings", symbol: "gearshape.fill", showsTitle: false, isSelected: selection == .menu || selection == .settings) {
                onSelect(.menu)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

private struct NotchTab: View {
    let title: LocalizedStringKey
    let symbol: String
    var badge = 0
    var note: LocalizedStringKey?
    var showsTitle = true
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var background: Color {
        if isSelected { return .white.opacity(0.16) }
        return isHovering ? .white.opacity(0.07) : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                if showsTitle {
                    Text(title)
                }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(SessionPalette.attention))
                }
                if let note {
                    Text(note)
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, showsTitle ? 11 : 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.62))
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if !SWIFT_PACKAGE
#Preview {
    NotchHeaderView(vm: .init())
}
#endif
