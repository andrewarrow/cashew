//
//  ContentView.swift
//  cashew
//
//  Created by aa on 5/1/25.
//

import SwiftUI
import StoreKit
import UIKit

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var selectedTab = 0
    @State private var showingAddDataModal = false
    @State private var reviewRequestTask: Task<Void, Never>?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView {
                    selectedTab = 1
                    showingAddDataModal = true
                }
            }
            .tabItem {
                Image(systemName: "house")
                Text("Home")
            }
            .tag(0)

            NavigationStack {
                TransactionsView(showingAddDataModal: $showingAddDataModal)
                    .environmentObject(dataManager)
            }
            .tabItem {
                Image(systemName: "dollarsign.circle")
                Text("Transactions")
            }
            .tag(1)
            
            NavigationStack {
                CategoryView()
                    .environmentObject(dataManager)
            }
            .tabItem {
                Image(systemName: "tag.fill")
                Text("Categories")
            }
            .tag(2)

            NavigationStack {
                ShareView()
                    .environmentObject(dataManager)
            }
            .tabItem {
                Image(systemName: "square.and.arrow.up.on.square")
                Text("Share")
            }
            .tag(3)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                dataManager.reviewPromptTracker.recordAppOpen()
            } else {
                reviewRequestTask?.cancel()
                if phase == .background {
                    dataManager.reviewPromptTracker.recordAppBackground()
                }
            }
        }
        .onReceive(dataManager.reviewOpportunities) {
            scheduleReviewRequest()
        }
        .onChange(of: selectedTab) { _, _ in
            reviewRequestTask?.cancel()
        }
        .onChange(of: showingAddDataModal) { _, isPresented in
            if isPresented { reviewRequestTask?.cancel() }
        }
        .onDisappear {
            reviewRequestTask?.cancel()
        }
    }

    private func scheduleReviewRequest() {
        reviewRequestTask?.cancel()
        guard scenePhase == .active,
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              dataManager.reviewPromptTracker.shouldRequestReview(version: version) else { return }

        reviewRequestTask = Task { @MainActor in
            do {
                // Give the user a pause after completing their task.
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            // A new sheet, alert, or file picker may have opened during the pause.
            let hasPresentation = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap(\.windows)
                .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
            guard !Task.isCancelled, scenePhase == .active,
                  !showingAddDataModal, !hasPresentation,
                  !dataManager.showFinanceDataAlert,
                  dataManager.reviewPromptTracker.recordReviewRequest(version: version) else { return }
            requestReview()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager())
}
