import Foundation
import CoreBluetooth
import SwiftUI

// Category model for organizing finance transactions
struct Category: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var color: Color
    
    // CodingKeys needed since Color is not directly Codable
    enum CodingKeys: String, CodingKey {
        case id, name, icon, colorString
    }
    
    init(id: UUID = UUID(), name: String, icon: String, color: Color) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }
    
    // Custom encoding to handle Color
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        
        // Store color as a string
        if let colorString = Category.colorToString(color) {
            try container.encode(colorString, forKey: .colorString)
        }
    }
    
    // Custom decoding to handle Color
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        
        // Convert string back to color
        let colorString = try container.decode(String.self, forKey: .colorString)
        self.color = Category.stringToColor(colorString) ?? .gray
    }
    
    // Helper function to convert Color to String
    private static func colorToString(_ color: Color) -> String? {
        if color == .blue { return "blue" }
        if color == .red { return "red" }
        if color == .green { return "green" }
        if color == .orange { return "orange" }
        if color == .purple { return "purple" }
        if color == .yellow { return "yellow" }
        if color == .pink { return "pink" }
        if color == .gray { return "gray" }
        return "gray" // Default
    }
    
    // Helper function to convert String to Color
    private static func stringToColor(_ string: String) -> Color? {
        switch string {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "yellow": return .yellow
        case "pink": return .pink
        case "gray": return .gray
        default: return .gray
        }
    }
    
    // Equality check
    static func == (lhs: Category, rhs: Category) -> Bool {
        return lhs.id == rhs.id
    }
}

// Finance transaction entry with amount, description, category, and date
struct FinanceTransaction: Identifiable, Codable {
    let id: UUID
    var amount: Double
    var description: String
    var category: String
    var date: Date
    
    init(amount: Double = 0.0, description: String = "", category: String = "", date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.description = description
        self.category = category
        self.date = date
    }
}

// Finance data model for Bluetooth transmission
struct FinanceData: Identifiable, Codable {
    let id: UUID
    let senderName: String
    let timestamp: Date
    var transactions: [FinanceTransaction]
    
    init(senderName: String, transactions: [FinanceTransaction], timestamp: Date = Date()) {
        self.id = UUID()
        self.senderName = senderName
        self.timestamp = timestamp
        self.transactions = transactions
    }
    
    // Convert to Data for Bluetooth transmission
    func toData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(self)
            print("Successfully encoded FinanceData to \(data.count) bytes")
            return data
        } catch {
            print("Error encoding FinanceData: \(error)")
            return nil
        }
    }
    
    // Convert from Data received over Bluetooth
    static func fromData(_ data: Data) -> FinanceData? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let financeData = try decoder.decode(FinanceData.self, from: data)
            print("Successfully decoded FinanceData with \(financeData.transactions.count) transactions")
            return financeData
        } catch {
            print("Error decoding FinanceData: \(error)")
            return nil
        }
    }
}

struct BluetoothDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral?
    var name: String
    
    // The actual last received RSSI value (updates frequently)
    private var _currentRssi: Int
    // The RSSI snapshot used for display and sorting (updates every 60 seconds)
    private var _displayRssi: Int
    
    // Last time the display RSSI was updated
    var lastSnapshotTime: Date = Date()
    var isConnected: Bool = false
    var lastUpdated: Date = Date()
    var isSameApp: Bool = false
    
    // Finance data received from this device
    var receivedFinanceData: FinanceData?
    
    // Getter for the actual current RSSI (for details screen)
    var rssi: Int { 
        return _currentRssi 
    }
    
    // Getter for the display RSSI (for list sorting and display)
    var displayRssi: Int {
        return _displayRssi
    }
    
    init(peripheral: CBPeripheral?, name: String, rssi: Int, isSameApp: Bool = false) {
        if let peripheral = peripheral {
            self.id = peripheral.identifier
        } else {
            // For preview purposes, generate a random UUID
            self.id = UUID()
        }
        self.peripheral = peripheral
        self.name = name
        self._currentRssi = rssi
        self._displayRssi = rssi
        self.isSameApp = isSameApp
    }
    
    // Called when a new RSSI reading is received
    mutating func updateRssi(_ newRssi: Int) {
        self._currentRssi = newRssi
        self.lastUpdated = Date()
        
        // Only update the display RSSI if it's been at least 60 seconds
        // or if this is a significant change (device getting much closer or farther)
        let timeInterval = Date().timeIntervalSince(lastSnapshotTime)
        let significantChange = abs(newRssi - _displayRssi) > 20 // 20 dBm is a significant change
        
        if timeInterval > 60 || significantChange {
            self._displayRssi = newRssi
            self.lastSnapshotTime = Date()
        }
    }
    
    // Get the sort key - combines category and name for very stable ordering
    var sortKey: String {
        let categoryPrefix = String(format: "%d", signalCategory)
        // Using the full original name without any manipulation
        return "\(categoryPrefix)_\(name)_\(id.uuidString)"
    }
    
    var signalStrengthIcon: String {
        if displayRssi > -50 {
            return "wifi"
        } else if displayRssi > -70 {
            return "wifi"
        } else {
            return "wifi"
        }
    }
    
    var signalStrengthDescription: String {
        if displayRssi > -50 {
            return "Strong"
        } else if displayRssi > -70 {
            return "Good"
        } else if displayRssi > -90 {
            return "Weak"
        } else {
            return "Poor"
        }
    }
    
    // Used for sorting devices into stable buckets
    var signalCategory: Int {
        if displayRssi > -50 {
            return 1  // Close (Strong)
        } else if displayRssi > -80 {
            return 2  // Medium (Good-Weak)
        } else {
            return 3  // Far (Poor)
        }
    }
}