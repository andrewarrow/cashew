//
//  ContentView.swift
//  cashew
//
//  Created by aa on 5/1/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        TabView {
            BluetoothDeviceListView()
                .environmentObject(bluetoothManager)
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Devices")
                }
            
            TransactionsView()
                .environmentObject(bluetoothManager)
                .tabItem {
                    Image(systemName: "dollarsign.circle")
                    Text("Transactions")
                }
        }
    }
}

#Preview {
    ContentView()
}
