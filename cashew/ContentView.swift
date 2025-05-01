//
//  ContentView.swift
//  cashew
//
//  Created by aa on 5/1/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        TabView {
            ShareView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "square.and.arrow.up.on.square")
                    Text("Share")
                }
            
            TransactionsView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Transactions")
                }
            
            CategoryView()
                .environmentObject(dataManager)
                .tabItem {
                    Image(systemName: "tag.fill")
                    Text("Categories")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DataManager())
}
