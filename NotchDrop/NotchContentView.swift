//
//  NotchContentView.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/7.
//  Last Modified by 冷月 on 2025/5/5.
//

import ColorfulX
import SwiftUI
import UniformTypeIdentifiers

struct NotchContentView: View {
    @StateObject var vm: NotchViewModel

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                HStack(spacing: vm.spacing) {
                    ShareView(vm: vm, type: .airdrop)
                    TrayView(vm: vm)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .sessions:
                sessionsScreen
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .player:
                NotchPlayerView()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .menu:
                NotchMenuView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .settings:
                NotchSettingsView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(vm.animation, value: vm.contentType)
    }

    /// Une demande en attente (autorisation, choix d'étapes) passe avant la liste : une session attend.
    @ViewBuilder
    private var sessionsScreen: some View {
        if let request = vm.pendingRequests.first {
            RequestCardView(
                request: request,
                position: "1 sur \(vm.pendingRequests.count)",
                showsPosition: vm.pendingRequests.count > 1,
                onReply: { vm.answerRequest(request, $0) }
            )
            .id(request.replyID)
        } else {
            SessionsListView(summary: vm.sessionSummary, onGoTo: vm.goToSession)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    NotchContentView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
#endif
