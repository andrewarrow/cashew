import Foundation
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

// Finance transaction entry with amount in pennies, description, category, and date
struct FinanceTransaction: Identifiable, Codable {
    let id: UUID
    var amount: Int // Amount in pennies (e.g., $10.25 would be stored as 1025)
    var description: String
    var category: String
    var date: Date
    
    init(amount: Int = 0, description: String = "", category: String = "", date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.description = description
        self.category = category
        self.date = date
    }
}

// Finance data model
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
    
    // Convert to Data for transmission
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
    
    // Convert from Data
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