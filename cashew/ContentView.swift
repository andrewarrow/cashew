//
//  ContentView.swift
//  cashew
//
//  Created by aa on 5/1/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0
    @State private var showingAddDataModal = false
    
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

            NavigationView {
                TransactionsView(showingAddDataModal: $showingAddDataModal)
                    .environmentObject(dataManager)
            }
            .tabItem {
                Image(systemName: "dollarsign.circle")
                Text("Transactions")
            }
            .tag(1)
            
            NavigationView {
                CategoryView()
                    .environmentObject(dataManager)
            }
            .tabItem {
                Image(systemName: "tag.fill")
                Text("Categories")
            }
            .tag(2)

            NavigationView {
                ShareView()
                    .environmentObject(dataManager)
            }
            .tabItem {
                Image(systemName: "square.and.arrow.up.on.square")
                Text("Share")
            }
            .tag(3)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager())
}
