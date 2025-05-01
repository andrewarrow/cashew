//
//  cashewApp.swift
//  cashew
//
//  Created by aa on 5/1/25.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct cashewApp: App {
    @StateObject private var dataManager = DataManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "json" else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601 // Ensure dates are decoded properly
            let transactions = try decoder.decode([FinanceTransaction].self, from: data)
            
            // Import the transactions
            dataManager.importTransactions(transactions)
            
            // Show confirmation alert via NotificationCenter
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowImportAlert"),
                object: nil,
                userInfo: ["count": transactions.count]
            )
        } catch {
            print("Failed to import file: \(error)")
            // Show error alert via NotificationCenter
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowImportErrorAlert"),
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
    }
}
