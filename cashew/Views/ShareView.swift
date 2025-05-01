import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var isImporting: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportData: Data?
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    
    // For handling app open with URL
    @State private var importObserver: NSObjectProtocol?
    @State private var importErrorObserver: NSObjectProtocol?
    
    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Error Banner (if needed)
                if let error = dataManager.error {
                    ErrorBanner(message: error)
                }
                
                // Main content - removing nested VStack
                // Import Card
                ShareActionCard(
                    iconName: "square.and.arrow.down",
                    title: "Import",
                    description: "Import transaction data from JSON files",
                    buttonText: "Import",
                    action: { isImporting = true }
                )
                
                // Export Card
                ShareActionCard(
                    iconName: "square.and.arrow.up",
                    title: "Export",
                    description: "Save your transaction data as a JSON file",
                    buttonText: "Export",
                    action: { prepareAndExport() }
                )
                
                Spacer()
                
                // History button
                NavigationLink(destination: HistoryView()) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.headline)
                        Text("View Transaction History")
                            .font(.headline)
                    }
                    .foregroundColor(.blue)
                    .padding()
                }
                
                // Adding some padding at the bottom
                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: JSONDocument(data: exportData ?? Data()),
            contentType: UTType.json,
            defaultFilename: "cashew_transactions.json"
        ) { result in
            handleExport(result: result)
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .accentColor(.blue)
        .onAppear {
            // Set up observers for file import notifications
            importObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowImportAlert"),
                object: nil,
                queue: .main
            ) { notification in
                if let count = notification.userInfo?["count"] as? Int {
                    alertTitle = "Import Successful"
                    alertMessage = "Successfully imported \(count) transactions"
                    showAlert = true
                }
            }
            
            importErrorObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowImportErrorAlert"),
                object: nil,
                queue: .main
            ) { notification in
                if let errorMessage = notification.userInfo?["error"] as? String {
                    alertTitle = "Import Error"
                    alertMessage = "Failed to import file: \(errorMessage)"
                    showAlert = true
                }
            }
        }
        .onDisappear {
            // Remove observers when view disappears
            if let observer = importObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = importErrorObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    
    private func prepareAndExport() {
        // Create JSON from transactions
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601 // Ensure dates are encoded properly
            
            // Get the transactions from the DataManager
            let transactions = dataManager.getAllTransactions()
            exportData = try encoder.encode(transactions)
            isExporting = true
        } catch {
            alertTitle = "Export Error"
            alertMessage = "Failed to prepare data: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedFile = urls.first else {
                alertTitle = "Import Error"
                alertMessage = "No file was selected"
                showAlert = true
                return
            }
            
            // Access and process the file
            if selectedFile.startAccessingSecurityScopedResource() {
                defer { selectedFile.stopAccessingSecurityScopedResource() }
                
                do {
                    let data = try Data(contentsOf: selectedFile)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601 // Ensure dates are decoded properly
                    
                    // Decode the transactions from the JSON file
                    let transactions = try decoder.decode([FinanceTransaction].self, from: data)
                    dataManager.importTransactions(transactions)
                    
                    alertTitle = "Import Successful"
                    alertMessage = "Successfully imported \(transactions.count) transactions"
                    showAlert = true
                } catch {
                    alertTitle = "Import Error"
                    alertMessage = "Failed to parse file: \(error.localizedDescription)"
                    showAlert = true
                }
            } else {
                alertTitle = "Import Error"
                alertMessage = "Permission denied to access file"
                showAlert = true
            }
            
        case .failure(let error):
            alertTitle = "Import Error"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    
    private func handleExport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            alertTitle = "Export Successful"
            alertMessage = "Your transactions have been exported to \(url.lastPathComponent)"
            showAlert = true
        case .failure(let error):
            alertTitle = "Export Error"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

// Card layout for share actions
struct ShareActionCard: View {
    let iconName: String
    let title: String
    let description: String
    let buttonText: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon and title
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            // Description
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            // Button
            Button(action: action) {
                Text(buttonText)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// Document for exporting JSON
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType.json] }
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    ShareView()
        .environmentObject(DataManager())
}
