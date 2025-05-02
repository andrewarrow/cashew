import Foundation
import Combine
import SwiftUI

class DataManager: ObservableObject {
    // Published properties that trigger UI updates
    @Published var financeTransactions: [FinanceTransaction] = []
    @Published var debugMessages: [String] = []
    @Published var categories: [Category] = []
    @Published var receivedFinanceData: FinanceData?
    @Published var error: String?
    
    // History entry model to track changes over time
    struct HistoryEntry: Identifiable, Codable {
        var id: UUID
        var date: Date
        var senderName: String
        var changes: [String]
        
        init(senderName: String, changes: [String], date: Date = Date()) {
            self.id = UUID()
            self.date = date
            self.senderName = senderName
            self.changes = changes
        }
    }
    
    // History entries for tracking changes
    @Published var historyEntries: [HistoryEntry] = []
    
    // Alert system for incoming finance data
    @Published var showFinanceDataAlert = false
    @Published var alertFinanceData: FinanceData?
    @Published var financeChangeDescriptions: [String] = []
    
    // Device name
    public var deviceCustomName: String = UIDevice.current.name
    
    init() {
        // Load saved categories first
        loadCategories()
        
        // Load saved finance transactions
        loadFinanceTransactions()
        
        // Load saved history entries
        loadHistoryEntries()
        
        self.addDebugMessage("Initialized DataManager")
    }
    
    // MARK: - Category Management
    
    // Initialize default categories
    private func initializeDefaultCategories() {
        if self.categories.isEmpty {
            let defaultCategories = [
                Category(name: "Food", icon: "cart.fill", color: .blue),
            ]
            
            self.categories = defaultCategories
            self.saveCategories()
            self.addDebugMessage("Initialized \(defaultCategories.count) default categories")
        }
    }
    
    // Save categories to UserDefaults
    func saveCategories() {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(self.categories) {
            UserDefaults.standard.set(encodedData, forKey: "Categories")
            self.addDebugMessage("Saved \(self.categories.count) categories to UserDefaults")
        }
    }
    
    // Load categories from UserDefaults
    private func loadCategories() {
        if let savedData = UserDefaults.standard.data(forKey: "Categories") {
            let decoder = JSONDecoder()
            if let loadedCategories = try? decoder.decode([Category].self, from: savedData) {
                self.categories = loadedCategories
                self.addDebugMessage("Loaded \(loadedCategories.count) categories from UserDefaults")
            } else {
                // If failed to decode, initialize defaults
                initializeDefaultCategories()
            }
        } else {
            // If no saved data, initialize defaults
            initializeDefaultCategories()
        }
    }
    
    // Add a new category
    func addCategory(name: String, icon: String, color: Color) {
        let newCategory = Category(name: name, icon: icon, color: color)
        self.categories.append(newCategory)
        self.saveCategories()
        self.addDebugMessage("Added new category: \(name)")
    }
    
    // Update an existing category
    func updateCategory(id: UUID, name: String? = nil, icon: String? = nil, color: Color? = nil) {
        if let index = self.categories.firstIndex(where: { $0.id == id }) {
            var updatedCategory = self.categories[index]
            
            if let name = name {
                updatedCategory.name = name
            }
            
            if let icon = icon {
                updatedCategory.icon = icon
            }
            
            if let color = color {
                updatedCategory.color = color
            }
            
            self.categories[index] = updatedCategory
            self.addDebugMessage("Updated category with ID: \(id.uuidString)")
            self.saveCategories()
        }
    }
    
    // Delete a category
    func deleteCategory(id: UUID) {
        // Only delete if it's not the last category
        if categories.count > 1, 
           let index = categories.firstIndex(where: { $0.id == id }) {
            
            // Update any transactions using this category to empty/null
            for i in 0..<financeTransactions.count {
                if financeTransactions[i].category == categories[index].name {
                    financeTransactions[i].category = ""
                }
            }
            
            // Remove the category
            categories.remove(at: index)
            self.addDebugMessage("Deleted category with ID: \(id.uuidString)")
            
            // Save both categories and transactions
            saveCategories()
            saveFinanceTransactions()
        }
    }
    
    // Get category by name
    func getCategory(byName name: String) -> Category? {
        return categories.first(where: { $0.name == name })
    }
    
    // MARK: - Finance Transaction Management
    
    // Load saved finance transactions from UserDefaults
    private func loadFinanceTransactions() {
        if let savedData = UserDefaults.standard.data(forKey: "FinanceTransactions") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loadedTransactions = try? decoder.decode([FinanceTransaction].self, from: savedData) {
                self.financeTransactions = loadedTransactions
                self.addDebugMessage("Loaded \(loadedTransactions.count) finance transactions from UserDefaults")
            } else {
                // If loading fails, initialize with sample data
                initializeFinanceTransactions()
            }
        } else {
            // If no saved data, initialize with sample data
            initializeFinanceTransactions()
        }
    }
    
    // Initialize finance transactions (empty for new users)
    private func initializeFinanceTransactions() {
        // Simply ensure that financeTransactions is initialized as an empty array
        if self.financeTransactions.isEmpty {
            // New users start with zero transactions
            self.addDebugMessage("Initialized with zero finance transactions")
            self.saveFinanceTransactions()
        }
    }
    
    // Save finance transactions to UserDefaults
    func saveFinanceTransactions() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encodedData = try? encoder.encode(self.financeTransactions) {
            UserDefaults.standard.set(encodedData, forKey: "FinanceTransactions")
            self.addDebugMessage("Saved \(self.financeTransactions.count) finance transactions to UserDefaults")
        }
    }
    
    // Get all transactions - used for export
    func getAllTransactions() -> [FinanceTransaction] {
        return self.financeTransactions
    }
    
    // Import transactions from external source
    func importTransactions(_ transactions: [FinanceTransaction]) {
        let currentTransactions = self.financeTransactions
        var importedTransactions = transactions
        var newCategoriesFound = [String]()
        
        // Check for new categories and create them if needed
        for transaction in importedTransactions {
            let categoryName = transaction.category
            // Skip if it's an empty category
            if categoryName.isEmpty {
                continue
            }
            
            // Check if category exists
            if getCategory(byName: categoryName) == nil {
                // Category doesn't exist, create a new one
                // Use a default icon and a random color from our supported colors
                let defaultIcon = "dollarsign.circle.fill"
                let colors: [Color] = [.blue, .red, .green, .orange, .purple, .yellow, .pink]
                let randomColor = colors.randomElement() ?? .gray
                
                // Add the new category
                let newCategory = Category(name: categoryName, icon: defaultIcon, color: randomColor)
                self.categories.append(newCategory)
                
                // Track it for logging
                newCategoriesFound.append(categoryName)
                
                self.addDebugMessage("Created new category: \(categoryName) during import")
            }
        }
        
        // Save any new categories
        if !newCategoriesFound.isEmpty {
            self.saveCategories()
            self.addDebugMessage("Created \(newCategoriesFound.count) new categories during import: \(newCategoriesFound.joined(separator: ", "))")
        }
        
        // Generate change descriptions for history
        let changes = self.generateFinanceChanges(
            oldTransactions: currentTransactions, 
            newTransactions: importedTransactions, 
            senderName: "Imported Data"
        )
        
        // Add the changes to history if there are any
        if !changes.isEmpty {
            self.addHistoryEntry(senderName: "Imported Data", changes: changes)
        }
        
        // Update transactions on main thread
        self.updateOnMainThread {
            // Merge transactions, avoiding duplicates by ID
            for transaction in importedTransactions {
                if !self.financeTransactions.contains(where: { $0.id == transaction.id }) {
                    self.financeTransactions.append(transaction)
                }
            }
            
            // Sort transactions by date (newest first)
            self.financeTransactions.sort { $0.date > $1.date }
            
            // Save to persistent storage
            self.saveFinanceTransactions()
            
            self.addDebugMessage("Imported \(importedTransactions.count) transactions")
        }
    }
    
    // Save history entries to UserDefaults
    func saveHistoryEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encodedData = try? encoder.encode(self.historyEntries) {
            UserDefaults.standard.set(encodedData, forKey: "HistoryEntries")
            self.addDebugMessage("Saved \(self.historyEntries.count) history entries to UserDefaults")
        }
    }
    
    // Load saved history entries from UserDefaults
    private func loadHistoryEntries() {
        if let savedData = UserDefaults.standard.data(forKey: "HistoryEntries") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            if let loadedEntries = try? decoder.decode([HistoryEntry].self, from: savedData) {
                self.historyEntries = loadedEntries
                self.addDebugMessage("Loaded \(loadedEntries.count) history entries from UserDefaults")
            }
        }
    }
    
    // Add a new history entry 
    private func addHistoryEntry(senderName: String, changes: [String]) {
        // Create a new history entry
        let entry = HistoryEntry(senderName: senderName, changes: changes)
        
        // Add the entry to the array
        self.updateOnMainThread {
            // Limit to 100 most recent entries to avoid excessive storage
            if self.historyEntries.count >= 100 {
                self.historyEntries.removeFirst(self.historyEntries.count - 99)
            }
            
            // Add new entry
            self.historyEntries.append(entry)
            
            // Save to persistent storage
            self.saveHistoryEntries()
        }
        
        self.addDebugMessage("Added history entry with \(changes.count) changes from \(senderName)")
    }
    
    // Add a new finance transaction
    func addFinanceTransaction(amount: Int, description: String, category: String, date: Date = Date()) {
        let newTransaction = FinanceTransaction(
            amount: amount,
            description: description,
            category: category,
            date: date
        )
        
        self.financeTransactions.append(newTransaction)
        let dollars = Double(amount) / 100.0
        self.addDebugMessage("Added new finance transaction: $\(String(format: "%.2f", dollars)) for \(description)")
        self.saveFinanceTransactions()
    }
    
    // Update an existing finance transaction
    func updateFinanceTransaction(id: UUID, amount: Int? = nil, description: String? = nil, category: String? = nil, date: Date? = nil) {
        if let index = self.financeTransactions.firstIndex(where: { $0.id == id }) {
            var updatedTransaction = self.financeTransactions[index]
            
            if let amount = amount {
                updatedTransaction.amount = amount
            }
            
            if let description = description {
                updatedTransaction.description = description
            }
            
            if let category = category {
                updatedTransaction.category = category
            }
            
            if let date = date {
                updatedTransaction.date = date
            }
            
            self.financeTransactions[index] = updatedTransaction
            self.addDebugMessage("Updated finance transaction with ID: \(id.uuidString)")
            self.saveFinanceTransactions()
        }
    }
    
    // Generate descriptions of what changed between the old and new finance transactions
    func generateFinanceChanges(oldTransactions: [FinanceTransaction], newTransactions: [FinanceTransaction], senderName: String) -> [String] {
        var changes = [String]()
        
        // Format for currency
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.locale = Locale.current
        
        // Format for dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        let nameForChanges = senderName
        
        // Count new transactions by category
        var newTransactionsByCategory: [String: Int] = [:]
        for transaction in newTransactions {
            if !oldTransactions.contains(where: { $0.id == transaction.id }) {
                let category = transaction.category
                newTransactionsByCategory[category] = (newTransactionsByCategory[category] ?? 0) + 1
            }
        }
        
        // Add descriptions for new transactions by category
        for (category, count) in newTransactionsByCategory {
            changes.append("\(count) new \(category) transaction\(count > 1 ? "s" : "") received from \(nameForChanges).")
        }
        
        // Calculate total amount of new transactions
        let totalNewAmount = newTransactions.filter { transaction in
            !oldTransactions.contains(where: { $0.id == transaction.id })
        }.reduce(0) { $0 + $1.amount }
        
        if totalNewAmount != 0 {
            // Convert pennies to dollars for display
            let totalNewAmountInDollars = Double(totalNewAmount) / 100.0
            let formattedAmount = currencyFormatter.string(from: NSNumber(value: abs(totalNewAmountInDollars))) ?? "$\(abs(totalNewAmountInDollars))"
            if totalNewAmount > 0 {
                changes.append("Total income of \(formattedAmount) received from \(nameForChanges).")
            } else {
                changes.append("Total expense of \(formattedAmount) received from \(nameForChanges).")
            }
        }
        
        // If no specific changes were detected, provide a general update message
        if changes.isEmpty {
            changes.append("Finance data updated by \(nameForChanges) with \(newTransactions.count) transactions.")
        }
        
        return changes
    }
    
    // Add debug message to the log - both UI and console
    func addDebugMessage(_ message: String) {
        print("DEBUG: \(message)")
        self.updateOnMainThread {
            self.debugMessages.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
            
            // Keep only last 100 messages to avoid memory issues
            if self.debugMessages.count > 100 {
                self.debugMessages.removeFirst()
            }
        }
    }
    
    // Helper to ensure updates happen on main thread
    func updateOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
}
