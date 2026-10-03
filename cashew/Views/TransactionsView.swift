import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingAddDataModal = false
    @State private var transactionText = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        Group {
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
                // List of transactions
                List {
                    ForEach(transactionsByDate.keys.sorted(by: >), id: \.self) { date in
                        Section(header: Text(formatDate(date))) {
                            ForEach(transactionsByDate[date] ?? []) { transaction in
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
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
    }
    
    // Group transactions by date
    private var transactionsByDate: [Date: [FinanceTransaction]] {
        let calendar = Calendar.current
        var result: [Date: [FinanceTransaction]] = [:]
        
        for transaction in dataManager.financeTransactions {
            // Create date with time components set to 0
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: transaction.date)
            if let date = calendar.date(from: dateComponents) {
                if result[date] == nil {
                    result[date] = []
                }
                result[date]?.append(transaction)
            }
        }
        
        // Sort transactions within each day by amount
        for (date, transactions) in result {
            result[date] = transactions.sorted(by: { $0.amount > $1.amount })
        }
        
        return result
    }
    
    // Format date for section headers
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Import transactions from text
    private func importTransactions(_ text: String, defaultYear: Int) -> String? {
        let result = TransactionTextParser.parse(text, defaultYear: defaultYear)
        guard !result.transactions.isEmpty else {
            return "No valid transactions found. Check the dates, amounts, and descriptions, then try again."
        }

        for transaction in result.transactions {
            let category = determineCategory(from: transaction.description)
            dataManager.addFinanceTransaction(
                amount: transaction.amount,
                description: transaction.description,
                category: category,
                date: transaction.date
            )
        }

        alertTitle = "Import Successful"
        let skipped = result.skippedRecordCount
        alertMessage = "Imported \(result.transactions.count) transactions.\(skipped > 0 ? " Skipped \(skipped) invalid record\(skipped == 1 ? "" : "s")." : "")"
        if result.assumedYearCount > 0 {
            alertMessage += " Dates without a year use \(defaultYear)."
        }
        showAlert = true
        return nil
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
    @State private var statementYear = String(Calendar(identifier: .gregorian).component(.year, from: Date()))
    @State private var importError: String?
    var onImport: (String, Int) -> String?
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste bank activity, statement rows, or CSV/TSV data.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Statement year")
                    Spacer()
                    TextField("Year", text: $statementYear)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityLabel("Statement year")
                }

                Text("Used for dates without a year.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $transactionText)
                    .accessibilityLabel("Transaction data")
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                if let importError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .onChange(of: transactionText) { _ in
                importError = nil
            }
            .onChange(of: statementYear) { _ in
                importError = nil
            }
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
                        guard let year = Int(statementYear.trimmingCharacters(in: .whitespacesAndNewlines)),
                              (1...9999).contains(year) else {
                            importError = "Enter a valid statement year, such as 2026."
                            return
                        }
                        if let error = onImport(transactionText, year) {
                            importError = error
                        } else {
                            isPresented = false
                        }
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
