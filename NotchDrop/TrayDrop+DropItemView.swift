//
//  TrayDrop+DropItemView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DropItemView: View {
    let item: TrayDrop.DropItem
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State var hover = false

    /// Évalué au départ du glissement : le dépôt sur la tablette saura qu'il ne s'agit pas d'un fichier venu de l'extérieur.
    private func startOwnDrag(of item: TrayDrop.DropItem) -> TrayDrop.DropItem {
        tvm.ownDrag.beginOwnDrag()
        return item
    }

    /// La croix de suppression se montre au survol, et sur tous les fichiers quand Option est enfoncée.
    private var canDelete: Bool { hover || vm.optionKeyPressed }

    var body: some View {
        VStack {
            Image(nsImage: item.workspacePreviewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 64)
            Text(item.fileName)
                .multilineTextAlignment(.center)
                .font(.system(.footnote, design: .rounded))
                .frame(maxWidth: 64)
        }
        .contentShape(Rectangle())
        // Pas l'effet poof de Pow : ses images vivent dans Pow_Pow.bundle, introuvable dans une app signée (plantage au lancement).
        .transition(.opacity.combined(with: .scale))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .scaleEffect(hover ? 1.05 : 1.0)
        .animation(vm.animation, value: hover)
        .draggable(startOwnDrag(of: item))
        .onTapGesture {
            guard !vm.optionKeyPressed else { return }
            vm.notchClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSWorkspace.shared.open(item.storageURL)
            }
        }
        .overlay {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.red)
                .background(Color.white.clipShape(Circle()).padding(1))
                .frame(width: vm.spacing, height: vm.spacing)
                .opacity(canDelete ? 1 : 0)
                .scaleEffect(canDelete ? 1 : 0.5)
                .animation(vm.animation, value: canDelete)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: vm.spacing / 2, y: -vm.spacing / 2)
                .onTapGesture { tvm.delete(item.id) }
                .allowsHitTesting(canDelete)
                .help("Remove from the shelf")
        }
    }
}
