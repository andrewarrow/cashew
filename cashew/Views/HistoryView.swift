import SwiftUI

// Transaction History View for displaying past changes
struct HistoryView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @State private var showClearConfirmation = false
    
    var body: some View {
        List {
            ForEach(dataManager.historyEntries.sorted(by: { $0.date > $1.date })) { entry in
                Section(header: 
                    HStack {
                        Text(formattedDate(entry.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("From: \(entry.senderName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                ) {
                    ForEach(entry.changes, id: \.self) { change in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                                .frame(width: 12, height: 12)
                                .padding(.top, 4)
                            
                            Text(change)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            
            if dataManager.historyEntries.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No History Yet")
                                .font(.headline)
                            
                            Text("Transaction changes will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Transaction History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !dataManager.historyEntries.isEmpty {
                    Button(action: {
                        // Show confirmation dialog
                        showClearConfirmation = true
                    }) {
                        Text("Clear")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert(isPresented: $showClearConfirmation) {
            Alert(
                title: Text("Clear History"),
                message: Text("Are you sure you want to clear all history entries? This cannot be undone."),
                primaryButton: .destructive(Text("Clear")) {
                    clearAllHistory()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func clearAllHistory() {
        dataManager.updateOnMainThread {
            dataManager.historyEntries.removeAll()
            dataManager.saveHistoryEntries()
        }
    }
}

#Preview {
    NavigationView {
        HistoryView()
            .environmentObject(DataManager())
    }
}