//
//  TrayDrop+View.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/8.
//

import SwiftUI

struct TrayView: View {
    @StateObject var vm: NotchViewModel
    @StateObject var tvm = TrayDrop.shared

    @State private var targeting = false
    @State private var scrollIndex = 0

    var storageTime: String {
        switch tvm.selectedFileStorageTime {
        case .oneHour:
            return NSLocalizedString("an hour", comment: "")
        case .oneDay:
            return NSLocalizedString("a day", comment: "")
        case .twoDays:
            return NSLocalizedString("two days", comment: "")
        case .threeDays:
            return NSLocalizedString("three days", comment: "")
        case .oneWeek:
            return NSLocalizedString("a week", comment: "")
        case .never:
            return NSLocalizedString("forever", comment: "")
        case .custom:
            let localizedTimeUnit = NSLocalizedString(tvm.customStorageTimeUnit.localized.lowercased(), comment: "")
            return "\(tvm.customStorageTime) \(localizedTimeUnit)"
        }
    }

    var body: some View {
        panel
            .onDrop(of: [.data], isTargeted: $targeting) { providers in
                if tvm.ownDrag.shouldIgnoreDrop() { return true }
                DispatchQueue.global().async { tvm.load(providers) }
                return true
            }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: vm.cornerRadius)
            .strokeBorder(style: StrokeStyle(lineWidth: 4, dash: [10]))
            .foregroundStyle(.white.opacity(0.1))
            .background(loading)
            .overlay {
                content
                    .padding()
            }
            .animation(vm.animation, value: tvm.items)
            .animation(vm.animation, value: tvm.isLoading)
    }

    var loading: some View {
        RoundedRectangle(cornerRadius: vm.cornerRadius)
            .foregroundStyle(.white.opacity(0.1))
            .conditionalEffect(
                .repeat(
                    .glow(color: .blue, radius: 50),
                    every: 1.5
                ),
                condition: tvm.isLoading > 0
            )
    }

    var text: String {
        [
            String(
                format: NSLocalizedString("Drag files here to keep them for %@", comment: ""),
                storageTime
            ),
            "&",
            NSLocalizedString("Press Option to delete", comment: ""),
        ].joined(separator: " ")
    }

    /// Les fichiers, avec de quoi voir ceux qui dépassent (flèches) et tout retirer d'un geste.
    var filledTray: some View {
        ScrollViewReader { scroller in
            VStack(spacing: 6) {
                trayActions(scroller)
                ScrollView(.horizontal) {
                    HStack(spacing: vm.spacing) {
                        ForEach(tvm.items) { item in
                            DropItemView(item: item, vm: vm, tvm: tvm)
                                .id(item.id)
                        }
                    }
                    .padding(vm.spacing)
                }
                .padding(-vm.spacing)
                .scrollIndicators(.visible)
            }
        }
    }

    private func trayActions(_ scroller: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            Text(tvm.items.count == 1 ? "1 file" : "\(tvm.items.count) files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            if TrayScroll.needsArrows(itemCount: tvm.items.count) {
                arrowButton("chevron.left", .earlier, scroller)
                arrowButton("chevron.right", .later, scroller)
            }
            Button("Clear all") { tvm.removeAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
    }

    private func arrowButton(_ symbol: String, _ direction: TrayScrollDirection, _ scroller: ScrollViewProxy) -> some View {
        Button {
            let items = tvm.items
            let target = TrayScroll.targetIndex(current: scrollIndex, direction: direction, itemCount: items.count)
            scrollIndex = target
            withAnimation(vm.animation) { scroller.scrollTo(items[target].id, anchor: .leading) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 18)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                    Text(text)
                        .multilineTextAlignment(.center)
                        .font(.system(.headline, design: .rounded))
                }
            } else {
                filledTray
            }
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 550, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
#endif
