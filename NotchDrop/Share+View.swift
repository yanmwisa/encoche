//
//  Share+View.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//  Last Modified by 冷月 on 2025/5/5.
//

import ColorfulX
import Pow
import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    enum ShareType {
        case airdrop
        case generic

        var imageName: String {
            switch self {
            case .airdrop: "airplayaudio"
            case .generic: "arrow.up.circle"
            }
        }

        /// Le vrai logo d'AirDrop, celui que le système montre dans ses feuilles de partage.
        var icon: Image {
            if self == .airdrop, let systemImage = NSSharingService(named: .sendViaAirDrop)?.image {
                return Image(nsImage: systemImage)
            }
            return Image(systemName: imageName)
        }

        var title: String {
            switch self {
            case .airdrop: NSLocalizedString("AirDrop", comment: "AirDrop sharing title")
            case .generic: NSLocalizedString("Share", comment: "Generic sharing title")
            }
        }

        var service: ([URL]) -> Share {
            switch self {
            case .airdrop:
                { urls in Share(files: urls, serviceName: .sendViaAirDrop) }
            case .generic:
                { urls in Share(files: urls) }
            }
        }

        var colorfulPresetTargeting: ColorfulPreset {
            switch self {
            case .airdrop: .neon
            case .generic: .sunset
            }
        }

        var colorfulPresetNormal: ColorfulPreset {
            switch self {
            case .airdrop: .aurora
            case .generic: .sunrise
            }
        }
    }

    @StateObject var vm: NotchViewModel
    let type: ShareType

    @State var trigger: UUID = .init()
    @State var targeting = false

    var body: some View {
        dropArea
            .onDrop(of: [.data], isTargeted: $targeting) { providers in
                trigger = .init()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    vm.notchClose()
                }
                DispatchQueue.global().async { beginDrop(providers) }
                return true
            }
    }

    var dropArea: some View {
        ShareTile(type: type, cornerRadius: vm.cornerRadius, isTargeting: targeting, onTap: pickFilesToShare)
            .contentShape(Rectangle())
            .changeEffect(
                .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                    Image(systemName: "paperplane")
                        .foregroundStyle(.white)
                },
                value: trigger
            )
    }

    func pickFilesToShare() {
        trigger = .init()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            vm.notchClose()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let picker = NSOpenPanel()
            picker.allowsMultipleSelection = true
            picker.canChooseDirectories = true
            picker.canChooseFiles = true
            picker.begin { response in
                if response == .OK {
                    let drop = type.service(picker.urls)
                    drop.begin()
                }
            }
        }
    }

    func beginDrop(_ providers: [NSItemProvider]) {
        assert(!Thread.isMainThread)
        guard let urls = providers.interfaceConvert() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let drop = type.service(urls)
            drop.begin()
        }
    }
}

/// Le dessin de la tuile de partage, sans l'état de l'app : ShareView la compose avec le glisser-déposer,
/// et `--render-preview` la dessine seule.
struct ShareTile: View {
    let type: ShareView.ShareType
    let cornerRadius: CGFloat
    let isTargeting: Bool
    let onTap: () -> Void
    /// Faux pour `--render-preview` : le fond animé est une vue AppKit qu'une image ne sait pas dessiner.
    var hasAnimatedBackground = true

    var colors: [NSColor] {
        if isTargeting {
            type.colorfulPresetTargeting.colors
        } else {
            type.colorfulPresetNormal.colors
        }
    }

    var body: some View {
        background
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay { label }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    var background: some View {
        if hasAnimatedBackground {
            ColorfulView(
                color: .init(get: { colors.map { Color($0) } }, set: { _ in }),
                speed: .init(get: { isTargeting ? 1.5 : 0 }, set: { _ in }),
                transitionSpeed: .constant(25)
            )
            .opacity(0.5)
        } else {
            Color.clear
        }
    }

    var label: some View {
        VStack(spacing: 8) {
            type.icon
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
            Text(type.title)
        }
        .font(.system(.headline, design: .rounded))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
