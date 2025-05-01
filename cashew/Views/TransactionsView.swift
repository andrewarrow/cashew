import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddDataModal = false
    @State private var transactionText = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var currentDate: Date? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                if dataManager.financeTransactions.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 70))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Text("No Transactions Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add transaction data to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button {
                            showingAddDataModal = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Transaction Data")
                            }
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top, 20)
                        
                        Spacer()
                    }
                } else {
                    // Day navigation and transactions for the selected date
                    VStack {
                        // Day navigation bar
                        HStack {
                            Button(action: {
                                navigateToPreviousDay()
                            }) {
                                Image(systemName: "chevron.left")
                                    .imageScale(.large)
                            }
                            .disabled(!hasPreviousDay)
                            
                            Spacer()
                            
                            if let date = currentDate {
                                Text(formatDate(date))
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                navigateToNextDay()
                            }) {
                                Image(systemName: "chevron.right")
                                    .imageScale(.large)
                            }
                            .disabled(!hasNextDay)
                        }
                        .padding()
                        
                        // List of transactions for the current date
                        List {
                            ForEach(transactionsForCurrentDate) { transaction in
                                TransactionRow(transaction: transaction)
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddDataModal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDataModal) {
                AddTransactionDataView(isPresented: $showingAddDataModal, onImport: importTransactions)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                // Initialize to the most recent date when the view appears
                if currentDate == nil {
                    currentDate = availableDates.first
                }
            }
        }
    }
    
    // Get all distinct dates in the dataset, sorted newest first
    private var availableDates: [Date] {
        let calendar = Calendar.current
        var dates: Set<Date> = []
        
        for transaction in dataManager.financeTransactions {
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: transaction.date)
            if let date = calendar.date(from: dateComponents) {
                dates.insert(date)
            }
        }
        
        return dates.sorted(by: >)
    }
    
    // Get transactions for the current date
    private var transactionsForCurrentDate: [FinanceTransaction] {
        guard let currentDate = currentDate else { return [] }
        
        let calendar = Calendar.current
        return dataManager.financeTransactions.filter { transaction in
            let transactionDateComponents = calendar.dateComponents([.year, .month, .day], from: transaction.date)
            let currentDateComponents = calendar.dateComponents([.year, .month, .day], from: currentDate)
            return transactionDateComponents.year == currentDateComponents.year &&
                   transactionDateComponents.month == currentDateComponents.month &&
                   transactionDateComponents.day == currentDateComponents.day
        }.sorted(by: { $0.amount > $1.amount })
    }
    
    // Check if there is a previous day available
    private var hasPreviousDay: Bool {
        guard let currentDate = currentDate, let index = availableDates.firstIndex(of: currentDate) else { return false }
        return index < availableDates.count - 1
    }
    
    // Check if there is a next day available
    private var hasNextDay: Bool {
        guard let currentDate = currentDate, let index = availableDates.firstIndex(of: currentDate) else { return false }
        return index > 0
    }
    
    // Navigate to the previous day
    private func navigateToPreviousDay() {
        guard let currentDate = currentDate, let index = availableDates.firstIndex(of: currentDate), index < availableDates.count - 1 else { return }
        self.currentDate = availableDates[index + 1]
    }
    
    // Navigate to the next day
    private func navigateToNextDay() {
        guard let currentDate = currentDate, let index = availableDates.firstIndex(of: currentDate), index > 0 else { return }
        self.currentDate = availableDates[index - 1]
    }
    
    // Format date for section headers
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Import transactions from text
    private func importTransactions(_ text: String) {
        let lines = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var importedCount = 0
        
        for line in lines {
            let components = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
            if components.count >= 3 {
                // Extract the date
                let dateString = components[0]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd/yyyy"
                
                // Extract the amount
                let amountString = components[1].replacingOccurrences(of: ",", with: "")
                
                // Extract the description (everything after amount)
                let descriptionComponents = Array(components[2...])
                let description = descriptionComponents.joined(separator: " ")
                
                if let date = dateFormatter.date(from: dateString),
                   let amountInDollars = Double(amountString) {
                    
                    // Convert dollars to pennies (cents)
                    let amountInPennies = Int(amountInDollars * 100)
                    
                    // Determine the category based on description
                    let category = determineCategory(from: description)
                    
                    // Add the transaction
                    dataManager.addFinanceTransaction(
                        amount: amountInPennies,
                        description: description,
                        category: category,
                        date: date
                    )
                    
                    importedCount += 1
                }
            }
        }
        
        // Show success or failure alert
        if importedCount > 0 {
            alertTitle = "Import Successful"
            alertMessage = "Imported \(importedCount) transactions."
        } else {
            alertTitle = "Import Failed"
            alertMessage = "No valid transactions found. Please check the format."
        }
        showAlert = true
    }
    
    // Simple logic to determine a category based on the transaction description
    private func determineCategory(from description: String) -> String {
        let lowercased = description.lowercased()
        
        if lowercased.contains("trader") || lowercased.contains("grocery") {
            return "Groceries"
        } else if lowercased.contains("fil") || lowercased.contains("restaurant") {
            return "Dining"
        } else if lowercased.contains("game") || lowercased.contains("bingo") {
            return "Entertainment"
        } else if lowercased.contains("equinox") {
            return "Fitness"
        } else if lowercased.contains("dr") {
            return "Healthcare"
        }
        
        return "Other"
    }
}

// Single transaction row
struct TransactionRow: View {
    @EnvironmentObject var dataManager: DataManager
    let transaction: FinanceTransaction
    @State private var showingCategoryPicker = false
    
    var body: some View {
        HStack {
            // Category icon based on the actual Category object
            Image(systemName: categoryIcon)
                .foregroundColor(categoryColor)
                .font(.system(size: 24))
                .frame(width: 32, height: 32)
                .background(categoryColor.opacity(0.1))
                .cornerRadius(8)
            
            // Description and date
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .fontWeight(.medium)
                
                Text(transaction.category)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount
            Text(formatAmount(transaction.amount))
                .fontWeight(.semibold)
                .foregroundColor(transaction.amount >= 0 ? .green : .red)
                
            // Add an edit button
            Button(action: {
                showingCategoryPicker = true
            }) {
                Image(systemName: "pencil")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingCategoryPicker) {
            TransactionCategoryPickerView(transaction: transaction, isPresented: $showingCategoryPicker)
        }
    }
    
    // Format currency amount from pennies
    private func formatAmount(_ amountInPennies: Int) -> String {
        let amountInDollars = Double(amountInPennies) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amountInDollars)) ?? "$\(amountInDollars)"
    }
    
    // Get icon based on the category model
    private var categoryIcon: String {
        if let category = dataManager.getCategory(byName: transaction.category) {
            return category.icon
        } else {
            // Fallbacks based on category name if no corresponding Category object
            switch transaction.category.lowercased() {
            case "groceries", "food":
                return "cart.fill"
            case "dining":
                return "fork.knife"
            case "entertainment":
                return "gamecontroller.fill"
            case "fitness":
                return "figure.walk"
            case "healthcare":
                return "heart.fill"
            case "income":
                return "arrow.down.circle.fill"
            default:
                return "dollarsign.circle.fill"
            }
        }
    }
    
    // Get color based on the category model
    private var categoryColor: Color {
        if let category = dataManager.getCategory(byName: transaction.category) {
            return category.color
        } else {
            // Fallbacks based on category name if no corresponding Category object
            switch transaction.category.lowercased() {
            case "groceries", "food":
                return .blue
            case "dining":
                return .orange
            case "entertainment":
                return .purple
            case "fitness", "income":
                return .green
            case "healthcare":
                return .red
            default:
                return .gray
            }
        }
    }
}

// View for picking a category for a transaction
struct TransactionCategoryPickerView: View {
    @EnvironmentObject var dataManager: DataManager
    let transaction: FinanceTransaction
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(dataManager.categories) { category in
                    Button(action: {
                        updateTransactionCategory(to: category.name)
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(category.color)
                                .font(.system(size: 24))
                                .frame(width: 32, height: 32)
                                .background(category.color.opacity(0.1))
                                .cornerRadius(8)
                            
                            Text(category.name)
                                .font(.headline)
                            
                            Spacer()
                            
                            if transaction.category == category.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func updateTransactionCategory(to categoryName: String) {
        dataManager.updateFinanceTransaction(
            id: transaction.id,
            category: categoryName
        )
    }
}

// Modal view for adding transaction data
struct AddTransactionDataView: View {
    @Binding var isPresented: Bool
    @State private var transactionText = ""
    var onImport: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Paste your transaction data below. Each line should be in the format:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
                
                Text("MM/DD/YYYY -XX.XX Description")
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.bottom)
                
                // Sample text
                Text("Example: 04/24/2025 -16.75 7-eleven")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
                
                // Text area for input
                TextEditor(text: $transactionText)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Transaction Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        onImport(transactionText)
                        isPresented = false
                    }
                    .disabled(transactionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    TransactionsView()
        .environmentObject(DataManager())
}