import SwiftUI

// Custom finance data alert view for in-app notifications
struct FinanceDataAlertView: View {
    @Binding var isShowing: Bool
    let financeData: FinanceData
    let changeDescriptions: [String]
    var onDismiss: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation {
                        isShowing = false
                        onDismiss()
                    }
                }
            
            // Alert content
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                    
                    Text("Finance Data Received")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            isShowing = false
                            onDismiss()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                
                Divider()
                
                // Finance data content
                VStack(alignment: .leading, spacing: 12) {
                    Text("From: \(financeData.senderName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !changeDescriptions.isEmpty {
                        Text("Changes:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(changeDescriptions, id: \.self) { change in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(.green)
                                            .frame(width: 12, height: 12)
                                            .padding(.top, 4)
                                        
                                        Text(change)
                                            .font(.body)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .frame(maxHeight: 200) // Limit the height of the scroll view
                    } else {
                        Text("Received transactions with \(financeData.transactions.count) entries")
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                
                Spacer()
                
                // Buttons
                HStack {
                    Button(action: {
                        withAnimation {
                            isShowing = false
                            onDismiss()
                        }
                    }) {
                        Text("Dismiss")
                            .fontWeight(.medium)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            isShowing = false
                            onDismiss()
                        }
                    }) {
                        Text("View Transactions")
                            .fontWeight(.medium)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 16)
            .padding(.horizontal, 30)
            .frame(maxWidth: 450)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

// Generic error banner that can be used in multiple views
struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
                .font(.system(size: 16))
                .padding(.trailing, 4)
            
            Text(message)
                .foregroundColor(.white)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.8), Color.red.opacity(0.9)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    FinanceDataAlertView(
        isShowing: .constant(true),
        financeData: FinanceData(
            senderName: "John's iPhone",
            transactions: [
                FinanceTransaction(amount: 50.0, description: "Dinner", category: "Food"),
                FinanceTransaction(amount: 25.0, description: "Movie", category: "Entertainment")
            ]
        ),
        changeDescriptions: [
            "2 new transactions received from John's iPhone",
            "Total expense of $75.00 received from John's iPhone"
        ],
        onDismiss: {}
    )
}