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
        BluetoothDeviceListView()
            .environmentObject(bluetoothManager)
    }
}

#Preview {
    ContentView()
}
