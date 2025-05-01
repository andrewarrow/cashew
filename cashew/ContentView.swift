//
//  ContentView.swift
//  cashew
//
//  Created by aa on 5/1/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        TabView {
            ShareView()
                .environmentObject(bluetoothManager)
                .tabItem {
                    Image(systemName: "square.and.arrow.up.on.square")
                    Text("Share")
                }
            
            TransactionsView()
                .environmentObject(bluetoothManager)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Transactions")
                }
            
            CategoryView()
                .environmentObject(bluetoothManager)
                .tabItem {
                    Image(systemName: "tag.fill")
                    Text("Categories")
                }
        }
    }
}

#Preview {
    ContentView()
}
