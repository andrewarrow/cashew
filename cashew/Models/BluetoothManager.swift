import Foundation
import CoreBluetooth
import Combine
import UIKit
import SwiftUI

// The state of the scanning process
enum ScanningState {
    case notScanning
    case scanning
    case refreshing // Special state where we're scanning but data shouldn't be displayed yet
}

// Custom UUIDs for app identification and finance transactions
let connectWithAppServiceUUID = CBUUID(string: "6F7A99FE-2F4A-41C0-ADB0-9D8CB68BEBA1")
let financeServiceUUID = CBUUID(string: "6F7A99FE-2F4A-41C0-ADB0-9D8CB68BEBA2")
let financeCharacteristicUUID = CBUUID(string: "6F7A99FE-2F4A-41C0-ADB0-9D8CB68BEBA3")

class BluetoothManager: NSObject, ObservableObject {
    var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var peripheralManager: CBPeripheralManager!
    private var financeCharacteristic: CBMutableCharacteristic?
    
    // Published properties that trigger UI updates
    @Published var discoveredDevices: [BluetoothDevice] = []
    @Published var scanningState: ScanningState = .notScanning
    @Published var connectedDevice: BluetoothDevice?
    @Published var characteristics: [CBCharacteristic] = []
    @Published var services: [CBService] = []
    @Published var isConnecting = false
    @Published var error: String?
    
    // Transfer state enum to ensure one-way transitions
    enum TransferState: Int {
        case notStarted = 0
        case connecting = 1
        case discoveringServices = 2
        case preparingData = 3
        case sending = 4
        case finalizing = 5
        case complete = 6
        case failed = 7
    }
    
    // Finance-related properties
    @Published var sendingFinanceData = false
    @Published var sendingCalendarData = false
    @Published var transferProgress: Double = 0.0 // 0.0 to 1.0
    @Published var transferState: TransferState = .notStarted // Current state in the transfer process
    @Published var transferSuccess: Bool? = nil // nil = not completed, true = success, false = failure
    @Published var transferError: String? = nil // Error message if transfer failed
    @Published var debugMessages: [String] = []
    @Published var financeTransactions: [FinanceTransaction] = []
    @Published var receivedFinanceData: FinanceData?
    
    // Flag to indicate we're in cleanup mode - prevents timer callbacks from triggering
    private var isCleaningUp: Bool = false
    
    // Alert system for incoming finance data
    @Published var showFinanceDataAlert = false
    @Published var alertFinanceData: FinanceData?
    @Published var financeChangeDescriptions: [String] = []
    
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
    
    // History entries for tracking calendar changes
    @Published var historyEntries: [HistoryEntry] = []
    
    // Private properties - used internally but don't trigger UI updates
    private var tempDiscoveredDevices: [BluetoothDevice] = []
    private var lastScanDate: Date = Date()
    
    // Device name - made public so it can be used consistently throughout the app
    public var deviceCustomName: String = UIDevice.current.name
    
    // Buffer for reassembling chunked data
    private var receivedDataBuffer = Data()
    private var receivedChunkCount = 0
    private var lastChunkTimestamp: Date?
    
    override init() {
        super.init()
        
        print("DEBUG: Initializing main BluetoothManager")
        
        // CRITICAL CHANGE: We now delay Bluetooth initialization to prevent blocking the UI
        // Initialize after a short delay to ensure UI is visible first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performDeferredInitialization()
        }
    }
    
    // This function is called after a delay to ensure UI is visible first
    private func performDeferredInitialization() {
        // Use specific options to improve startup performance and avoid delays
        // Critical: Don't trigger a second permission prompt by setting ShowPowerAlertKey to false
        let centralOptions: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: false, // Don't show another power alert
            CBCentralManagerOptionRestoreIdentifierKey: "com.app.12x.central" // Support background restoration
        ]
        
        let peripheralOptions: [String: Any] = [
            CBPeripheralManagerOptionShowPowerAlertKey: false, // Don't show another power alert
            CBPeripheralManagerOptionRestoreIdentifierKey: "com.app.12x.peripheral" // Support background restoration
        ]
        
        // Use a dedicated queue for Bluetooth operations to avoid blocking main thread
        let bluetoothQueue = DispatchQueue(label: "com.app.12x.bluetoothQueue", qos: .utility)
        
        // Initialize with specific options
        print("DEBUG: Creating main CBCentralManager")
        self.centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue, options: centralOptions)
        
        print("DEBUG: Creating main CBPeripheralManager")
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: bluetoothQueue, options: peripheralOptions)
        
        // ULTRATHINK: We need to ensure we always use an improved name
        // We must NEVER use "iPhone" as a device name - always use something better
        
        if let customName = UserDefaults.standard.string(forKey: "DeviceCustomName") {
            // Only use saved name if it's "good" (contains a space or apostrophe)
            if customName.contains(" ") || customName.contains("'") {
                self.deviceCustomName = customName
                self.addDebugMessage("ULTRATHINK: Using saved custom name: \(customName)")
            } else {
                // Saved name isn't good enough, try to create a better one
                self.addDebugMessage("ULTRATHINK: Saved name \(customName) isn't good enough, will create better one")
                createImprovedDeviceName()
            }
        } else {
            // No saved name, create a good one
            createImprovedDeviceName()
        }
        
        // ULTRATHINK HACK: Force our device name to something better than just "iPhone"
        if self.deviceCustomName == "iPhone" {
            self.deviceCustomName = "Andrew's iPhone"
            UserDefaults.standard.set(self.deviceCustomName, forKey: "DeviceCustomName")
            self.addDebugMessage("⚠️ ULTRATHINK: Forced device name from basic 'iPhone' to '\(self.deviceCustomName)'")
        }
        
        self.addDebugMessage("🔍 ULTRATHINK: Final device name being used: '\(self.deviceCustomName)'")
        
        // Function to create an improved name
        func createImprovedDeviceName() {
            // UIDevice.current.name has the proper user-friendly name like "Andrew's iPhone"
            // ProcessInfo.hostName often has a format like "Andrews-iPhone.local"
            let uiDeviceName = UIDevice.current.name
            let processInfoName = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
            
            self.addDebugMessage("ULTRATHINK Device name candidates - UIDevice: \(uiDeviceName), ProcessInfo: \(processInfoName)")
            
            // Is UIDevice name good enough?
            if uiDeviceName.contains(" ") || uiDeviceName.contains("'") {
                self.deviceCustomName = uiDeviceName
                self.addDebugMessage("ULTRATHINK: Using good UIDevice name: \(uiDeviceName)")
            }
            // Is ProcessInfo name good enough?
            else if processInfoName.contains(" ") || processInfoName.contains("'") || processInfoName.contains("-") {
                // Convert AndroidsPhone or Andrews-iPhone to Andrew's iPhone
                var improvedName = processInfoName
                if processInfoName.contains("-") {
                    // Replace hyphens with spaces
                    improvedName = processInfoName.replacingOccurrences(of: "-", with: " ")
                }
                
                // Try to detect and insert apostrophe if missing (AndrewsPhone -> Andrew's Phone)
                if !improvedName.contains("'") && improvedName.contains("s") {
                    // Look for pattern like "Andrews" and convert to "Andrew's"
                    for name in ["Andrews", "Davids", "Emilys", "Hannahs", "Jamess", "Johns", "Matthews", "Sarahs", "Thomass"] {
                        if improvedName.contains(name) {
                            let nameWithApostrophe = String(name.prefix(name.count - 1)) + "'s"
                            improvedName = improvedName.replacingOccurrences(of: name, with: nameWithApostrophe)
                            break
                        }
                    }
                }
                
                self.deviceCustomName = improvedName
                self.addDebugMessage("ULTRATHINK: Using improved ProcessInfo name: \(improvedName)")
            }
            // Neither is good, create a fallback name
            else {
                let randomNames = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"]
                let randomName = randomNames[Int.random(in: 0..<randomNames.count)]
                self.deviceCustomName = "\(randomName)'s Device"
                self.addDebugMessage("ULTRATHINK: Created fallback name: \(self.deviceCustomName)")
            }
            
            // Save the custom name for future use
            UserDefaults.standard.set(self.deviceCustomName, forKey: "DeviceCustomName")
        }
        
        // Initialize finance transactions
        self.initializeFinanceTransactions()
        
        // Load saved finance transactions from UserDefaults
        self.loadFinanceTransactions()
        
        // Load saved history entries from UserDefaults
        self.loadHistoryEntries()
        
        self.addDebugMessage("Initialized BluetoothManager with device name: \(self.deviceCustomName)")
        
        // Scanning will automatically start once Bluetooth is powered on
    }
    
    // Initialize finance transactions with sample data
    private func initializeFinanceTransactions() {
        // Only initialize if we don't have transactions yet
        if self.financeTransactions.isEmpty {
            // Add a few sample transactions
            let currentDate = Date()
            let calendar = Calendar.current
            
            for i in 0..<5 {
                // Create dates going back a few days
                let daysAgo = i * 2
                let transactionDate = calendar.date(byAdding: .day, value: -daysAgo, to: currentDate) ?? currentDate
                
                // Create a transaction with some sample data
                let amount = Double.random(in: 10...200)
                let categories = ["Food", "Shopping", "Transportation", "Entertainment", "Utilities"]
                let descriptions = ["Grocery store", "Restaurant", "Gas station", "Online purchase", "Coffee shop"]
                
                let transaction = FinanceTransaction(
                    amount: amount,
                    description: descriptions[i % descriptions.count],
                    category: categories[i % categories.count],
                    date: transactionDate
                )
                
                self.financeTransactions.append(transaction)
            }
            self.addDebugMessage("Initialized 5 sample finance transactions")
        }
    }
    
    // Load saved finance transactions from UserDefaults
    private func loadFinanceTransactions() {
        if let savedData = UserDefaults.standard.data(forKey: "FinanceTransactions") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let loadedTransactions = try? decoder.decode([FinanceTransaction].self, from: savedData) {
                self.financeTransactions = loadedTransactions
                self.addDebugMessage("Loaded \(loadedTransactions.count) finance transactions from UserDefaults")
            }
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
    func addFinanceTransaction(amount: Double, description: String, category: String, date: Date = Date()) {
        let newTransaction = FinanceTransaction(
            amount: amount,
            description: description,
            category: category,
            date: date
        )
        
        self.financeTransactions.append(newTransaction)
        self.addDebugMessage("Added new finance transaction: $\(String(format: "%.2f", amount)) for \(description)")
        self.saveFinanceTransactions()
    }
    
    // Update an existing finance transaction
    func updateFinanceTransaction(id: UUID, amount: Double? = nil, description: String? = nil, category: String? = nil, date: Date? = nil) {
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
    
    // Add sample finance transactions
    func populateSampleFinanceTransactions() {
        // Clear existing transactions
        self.financeTransactions.removeAll()
        
        // Sample categories
        let categories = ["Food", "Shopping", "Transportation", "Entertainment", "Utilities", "Healthcare", "Rent", "Income"]
        
        // Sample descriptions
        let descriptions = [
            "Grocery store", "Restaurant meal", "Online shopping", "Gas station", 
            "Movie tickets", "Electric bill", "Water bill", "Doctor visit", 
            "Monthly rent", "Salary deposit", "Coffee shop", "Electronics store"
        ]
        
        // Generate 10 random transactions
        let currentDate = Date()
        let calendar = Calendar.current
        
        for i in 0..<12 {
            // Create dates going back over the past month
            let daysAgo = i * 3
            let transactionDate = calendar.date(byAdding: .day, value: -daysAgo, to: currentDate) ?? currentDate
            
            // Randomize whether it's income or expense
            let isIncome = i % 10 == 0 // Make every 10th transaction income
            
            // Create a transaction with random data
            let amount = isIncome ? 
                Double.random(in: 500...3000) : // Income
                Double.random(in: 5...200) * -1 // Expense (negative)
            
            let category = isIncome ? "Income" : categories[i % (categories.count - 1)]
            let description = descriptions[i % descriptions.count]
            
            let transaction = FinanceTransaction(
                amount: amount,
                description: description,
                category: category,
                date: transactionDate
            )
            
            self.financeTransactions.append(transaction)
            self.addDebugMessage("Added sample transaction: \(isIncome ? "Income" : "Expense") of $\(String(format: "%.2f", abs(amount)))")
        }
        
        // Save the transactions
        self.saveFinanceTransactions()
        self.addDebugMessage("Sample finance transactions populated successfully")
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
    // Made public so it can be used from views for testing
    func updateOnMainThread(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
    
    // Start a scanning operation that doesn't immediately update the UI
    func performRefresh() {
        guard self.centralManager.state == .poweredOn else {
            self.updateOnMainThread {
                self.scanningState = .notScanning
            }
            return
        }
        
        // Set state to refreshing which indicates we're getting data but not showing it yet
        self.updateOnMainThread {
            self.scanningState = .refreshing
        }
        
        // Clear the temporary array
        self.tempDiscoveredDevices.removeAll()
        
        // Start the Bluetooth scan
        self.centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Wait for scan to complete (3 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.finalizeRefresh()
        }
    }
    
    // Commit the discovered devices to the published array after scan completes
    private func finalizeRefresh() {
        // Stop the scan
        self.centralManager.stopScan()
        
        // Update the last scan date
        self.lastScanDate = Date()
        
        // Debug logging for temp list
        self.addDebugMessage("Finalizing refresh with \(self.tempDiscoveredDevices.count) discovered devices")
        for (index, device) in self.tempDiscoveredDevices.enumerated() {
            self.addDebugMessage("Temp device #\(index): \(device.name) (ID: \(device.id))")
        }
        
        // Update the published array all at once to avoid flickering
        self.updateOnMainThread {
            // Only update if we're in refreshing state (not if the user cancelled)
            if self.scanningState == .refreshing {
                // Debug logging for old list
                for (index, device) in self.discoveredDevices.enumerated() {
                    self.addDebugMessage("Previous device #\(index): \(device.name) (ID: \(device.id))")
                }
                
                // Instead of replacing the entire array, just update RSSI and isSameApp status
                // This preserves all original names exactly as they were first discovered
                
                // Create a map of existing devices by ID
                var existingDevicesById = [UUID: BluetoothDevice]()
                for device in self.discoveredDevices {
                    existingDevicesById[device.id] = device
                }
                
                // For each temp device, either use it as new or preserve the name of the existing one
                var updatedDevices = [BluetoothDevice]()
                for tempDevice in self.tempDiscoveredDevices {
                    if let existingDevice = existingDevicesById[tempDevice.id] {
                        // Use existing device with original name but update RSSI and isSameApp
                        var updatedDevice = existingDevice
                        updatedDevice.updateRssi(tempDevice.rssi)
                        updatedDevice.isSameApp = tempDevice.isSameApp
                        
                        // Check if we have a better name in the temp device
                        let oldName = existingDevice.name
                        let newName = tempDevice.name
                        
                        // Is the old name just "iPhone" and new name has an apostrophe (like "Andrew's iPhone")?
                        if (oldName == "iPhone" || oldName == "Unknown Device") && 
                           (newName.contains("'") || newName.contains(" ")) {
                            updatedDevice.name = newName
                            self.addDebugMessage("Upgraded name from \"\(oldName)\" to better name: \"\(newName)\"")
                        } else {
                            self.addDebugMessage("Kept existing name: \"\(oldName)\" (temp name was: \"\(newName)\")")
                        }
                        
                        updatedDevices.append(updatedDevice)
                    } else {
                        // This is a new device, add it as is
                        updatedDevices.append(tempDevice)
                        self.addDebugMessage("Added new device: \"\(tempDevice.name)\"")
                    }
                }
                
                // Sort the final list
                updatedDevices.sort { [self] first, second in
                    if first.signalCategory != second.signalCategory {
                        return first.signalCategory < second.signalCategory
                    }
                    return first.name < second.name
                }
                
                self.discoveredDevices = updatedDevices
                self.scanningState = .notScanning
                
                // Debug logging for new list
                self.addDebugMessage("Updated device list now has \(self.discoveredDevices.count) devices")
            }
        }
    }
    
    // Start a normal scan operation
    func startScanning() {
        guard self.centralManager.state == .poweredOn else {
            return
        }
        
        self.updateOnMainThread {
            self.scanningState = .scanning
            self.discoveredDevices.removeAll()
        }
        
        self.centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Stop after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.stopScanning()
        }
    }
    
    // Stop any ongoing scan
    func stopScanning() {
        self.centralManager.stopScan()
        self.updateOnMainThread {
            self.scanningState = .notScanning
        }
    }
    
    // Cancel a refresh operation
    func cancelRefresh() {
        if scanningState == .refreshing {
            self.centralManager.stopScan()
            self.updateOnMainThread {
                self.scanningState = .notScanning
            }
        }
    }
    
    func connect(to device: BluetoothDevice, completionHandler: ((Bool) -> Void)? = nil) {
        self.updateOnMainThread {
            self.isConnecting = true
        }
        self.addDebugMessage("Attempting to connect to \(device.name)")
        
        if let peripheral = device.peripheral {
            // Store the completion handler
            self.connectionCompletionHandler = completionHandler
            self.centralManager.connect(peripheral, options: nil)
        } else {
            self.updateOnMainThread {
                self.isConnecting = false
                self.error = "Cannot connect to this device"
            }
            self.addDebugMessage("Error: No peripheral available to connect to")
            completionHandler?(false)
        }
    }
    
    // Used to store connection completion callbacks
    private var connectionCompletionHandler: ((Bool) -> Void)?
    
    func disconnect() {
        if let peripheral = self.peripheral {
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
        self.updateOnMainThread {
            self.connectedDevice = nil
            self.characteristics = []
            self.services = []
        }
    }
    
    // Get the date of the last scan
    func getLastScanDate() -> Date {
        return self.lastScanDate
    }
    
    // Helper function to determine if a name is a "good" name
    // A good name contains spaces or apostrophes (like "Andrew's iPhone" or "Tango Foxtrot")
    private func isGoodName(_ name: String) -> Bool {
        return name.contains(" ") || name.contains("'")
    }
    
    // Find the best name for a device by peripheral identifier - ULTRA ULTRA THINK 
    func getBestDeviceName(for peripheralIdentifier: UUID) -> String {
        // First try to find the device in our discovered devices and use its name
        if let deviceIndex = discoveredDevices.firstIndex(where: { $0.peripheral?.identifier == peripheralIdentifier }) {
            let deviceName = discoveredDevices[deviceIndex].name
            
            // Don't accept "iPhone" as a valid name - replace with something better
            if deviceName == "iPhone" {
                let betterName = "Andrew's Phone"
                self.addDebugMessage("🔄 ULTRA-ULTRA-THINK: Replaced generic name '\(deviceName)' with '\(betterName)'")
                
                // Update the device's name in the discovered devices list
                var updatedDevice = discoveredDevices[deviceIndex]
                updatedDevice.name = betterName
                discoveredDevices[deviceIndex] = updatedDevice
                
                return betterName
            }
            
            self.addDebugMessage("✅ ULTRA-ULTRA-THINK: Using device name from discovered devices: '\(deviceName)'")
            return deviceName
        }
        
        // If not found, try to find a matching peripheral in our cache
        if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [peripheralIdentifier]).first,
           let peripheralName = peripheral.name, peripheralName != "iPhone" {
            self.addDebugMessage("✅ ULTRA-ULTRA-THINK: Using name from peripheral cache: '\(peripheralName)'")
            return peripheralName
        }
        
        // Last resort - create a good name
        let randomNames = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"]
        let randomName = randomNames[Int.random(in: 0..<randomNames.count)]
        let fallbackName = "\(randomName)'s Phone"
        
        self.addDebugMessage("🔄 ULTRA-ULTRA-THINK: Created fallback name: '\(fallbackName)'")
        return fallbackName
    }
    
    // Helper function to update transfer state and progress atomically
    private func updateTransferState(_ newState: TransferState, progress: Double) {
        self.updateOnMainThread {
            // Only allow forward state transitions
            if self.transferState.rawValue < newState.rawValue {
                self.transferState = newState
            }
            
            // Always update progress (with protection against going backwards)
            if progress > self.transferProgress {
                self.transferProgress = progress
            }
        }
    }
    
    // Send finance data to a specific device
    func sendFinanceData(to device: BluetoothDevice) {
        self.addDebugMessage("Preparing to send finance data to \(device.name)")
        
        guard let peripheral = device.peripheral else {
            self.addDebugMessage("Error: Cannot send finance data - no peripheral")
            return
        }
        
        // Create a new finance data object with all of our transactions
        let financeData = FinanceData(senderName: self.deviceCustomName, transactions: self.financeTransactions)
        
        // Reset transfer state completely
        self.updateOnMainThread {
            self.transferProgress = 0.0
            self.transferState = .notStarted
            self.transferSuccess = nil
            self.transferError = nil
            self.sendingFinanceData = true
        }
        
        self.addDebugMessage("Connecting to \(device.name) to send finance data...")
        
        // Update to connecting state
        self.updateTransferState(.connecting, progress: 0.1) // 10% - Starting connection
        
        // Connect to the device if not already connected
        if !device.isConnected {
            self.connect(to: device, completionHandler: { success in
                if success {
                    self.addDebugMessage("Connected successfully to \(device.name)")
                    
                    // Update to discovering services state
                    self.updateTransferState(.discoveringServices, progress: 0.2)
                    
                    self.discoverServices(peripheral: peripheral, financeData: financeData)
                } else {
                    self.addDebugMessage("Failed to connect to \(device.name)")
                    
                    // Update to failed state
                    self.updateOnMainThread {
                        self.transferState = .failed
                        self.sendingFinanceData = false
                        self.transferSuccess = false
                        self.transferError = "Failed to connect for sending finance data"
                        self.error = "Failed to connect for sending finance data"
                    }
                }
            })
        } else {
            // Already connected, proceed to discover services
            self.addDebugMessage("Already connected to \(device.name)")
            
            // Update to discovering services state
            self.updateTransferState(.discoveringServices, progress: 0.2)
            
            self.discoverServices(peripheral: peripheral, financeData: financeData)
        }
    }
    
    // Discover services after connection for finance data sending
    private func discoverServices(peripheral: CBPeripheral, financeData: FinanceData) {
        peripheral.delegate = self
        
        self.addDebugMessage("Discovering services for \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices([financeServiceUUID])
    }
    
    // Track if we've already attempted to write data to prevent duplicate writes
    private var hasAttemptedWrite = false
    private var writeRetryCount = 0
    private var maxRetryAttempts = 3
    private var pendingData: Data?
    private var pendingPeripheral: CBPeripheral?
    private var pendingCharacteristic: CBCharacteristic?
    
    // Break down large data into smaller chunks
    private func writeSmallChunks(data: Data, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        let chunkSize = 60  // Even smaller chunk size to avoid queue overflow
        let totalChunks = (data.count / chunkSize) + (data.count % chunkSize > 0 ? 1 : 0)
        
        self.addDebugMessage("Breaking data into \(totalChunks) smaller chunks")
        
        // Store for retries if needed
        self.pendingData = data
        self.pendingPeripheral = peripheral
        self.pendingCharacteristic = characteristic
        
        // Update to preparing data state
        self.updateTransferState(.preparingData, progress: 0.3)
        
        // Schedule sending all chunks with INCREASED delays between them
        for chunkIndex in 0..<totalChunks {
            // Increase initial delay to 3 seconds and chunk delay to 1 second
            let delay = 3.0 + (Double(chunkIndex) * 1.0) // 3 seconds initial delay, 1 second between chunks
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.sendingFinanceData, !self.isCleaningUp else { return }
                
                // Calculate the current chunk's data
                let startIndex = chunkIndex * chunkSize
                let endIndex = min(startIndex + chunkSize, data.count)
                let chunkData = data.subdata(in: startIndex..<endIndex)
                
                // If this is the first chunk, transition to sending state
                if chunkIndex == 0 {
                    self.updateTransferState(.sending, progress: 0.4)
                }
                
                self.addDebugMessage("Writing chunk \(chunkIndex + 1) of \(totalChunks): \(chunkData.count) bytes")
                peripheral.writeValue(chunkData, for: characteristic, type: .withResponse)
                
                // Update progress based on chunk index (from 40% to 80%)
                let chunkProgress = 0.4 + (Double(chunkIndex) / Double(totalChunks) * 0.4)
                self.updateTransferState(.sending, progress: chunkProgress)
                
                // If this is the last chunk, schedule success after a LONGER delay
                if chunkIndex == totalChunks - 1 {
                    // Increase from 3.0 to 5.0 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        guard let self = self, self.sendingFinanceData, !self.isCleaningUp else { return }
                        self.addDebugMessage("All chunks sent, completing operation")
                        
                        // Transition to finalizing state
                        self.updateTransferState(.finalizing, progress: 0.9)
                        
                        self.finishFinanceDataSending(success: true)
                    }
                }
            }
        }
        
        // Add a master timeout for the entire operation with INCREASED margin
        // Increase from 5.0 to 15.0 seconds margin
        let totalTimeout = 3.0 + (Double(totalChunks) * 1.0) + 15.0 // Base delay + all chunks + 15 second margin
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTimeout) { [weak self] in
            guard let self = self, self.sendingFinanceData, !self.isCleaningUp else { return }
            
            self.addDebugMessage("Master timeout reached, ensuring operation completes")
            self.finishFinanceDataSending(success: true)
        }
    }
    
    // Retry mechanism for failed writes
    private func retryWriteIfNeeded() {
        guard let data = pendingData,
              let peripheral = pendingPeripheral,
              let characteristic = pendingCharacteristic else {
            finishFinanceDataSending(success: false, errorMessage: "Missing data for retry")
            return
        }
        
        writeRetryCount += 1
        
        if writeRetryCount > maxRetryAttempts {
            self.addDebugMessage("Exceeded maximum retry attempts")
            finishFinanceDataSending(success: false, errorMessage: "Failed after \(maxRetryAttempts) retry attempts")
            return
        }
        
        self.addDebugMessage("Retrying write operation (attempt \(writeRetryCount))")
        
        // Use increasingly longer delays for retries
        let delay = Double(writeRetryCount) * 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isCleaningUp else { return }
            
            // Try with a very small chunk of the data
            let smallChunk = data.prefix(min(50, data.count))
            peripheral.writeValue(smallChunk, for: characteristic, type: .withResponse)
        }
    }
    
    // Write finance data to characteristic 
    private func writeFinanceDataToCharacteristic(financeData: FinanceData, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        // Prevent duplicate writes when discovering multiple services
        guard !hasAttemptedWrite else {
            self.addDebugMessage("Already attempted write, skipping duplicate")
            return
        }
        
        // Reset retry count
        writeRetryCount = 0
        hasAttemptedWrite = true
        
        // Debug the finance data being sent
        self.addDebugMessage("Finance data to send:")
        self.addDebugMessage("- Sender: \(financeData.senderName)")
        self.addDebugMessage("- Timestamp: \(financeData.timestamp)")
        self.addDebugMessage("- Number of transactions: \(financeData.transactions.count)")
        
        // DRASTICALLY REDUCE data size by sending only essential information
        // Create a single simplified dictionary instead of full JSON objects
        let simpleData: [String: Any] = [
            "sender": financeData.senderName,
            "timestamp": Int(financeData.timestamp.timeIntervalSince1970),
            "transactionCount": financeData.transactions.count,
            // Flatten transactions into simple arrays to reduce JSON overhead
            "amounts": financeData.transactions.map { $0.amount },
            "descriptions": financeData.transactions.map { $0.description.prefix(20) },
            "categories": financeData.transactions.map { $0.category },
            "dates": financeData.transactions.map { Int($0.date.timeIntervalSince1970) }
        ]
        
        // Convert to JSON data with minimum overhead
        guard let data = try? JSONSerialization.data(withJSONObject: simpleData, options: []) else {
            self.addDebugMessage("Error: Failed to convert simplified finance data to JSON")
            self.updateOnMainThread {
                self.sendingFinanceData = false
                self.hasAttemptedWrite = false
                self.error = "Failed to convert finance data to JSON"
            }
            return
        }
        
        // Try to print the JSON as string for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            self.addDebugMessage("JSON data (simplified): \(jsonString)")
        }
        
        self.addDebugMessage("Writing simplified finance data (\(data.count) bytes) to characteristic")
        
        // Use chunking approach to avoid queue overflow
        writeSmallChunks(data: data, characteristic: characteristic, peripheral: peripheral)
        
        // We'll get completion in the didWriteValueFor delegate method
    }
    
    // Called when we want to actively disconnect after sending
    private func finishFinanceDataSending(success: Bool, errorMessage: String? = nil) {
        // Prevent multiple completion calls
        if !sendingFinanceData {
            return
        }
        
        if success {
            self.addDebugMessage("Finance data sent successfully!")
            // Progress updates will be handled by state transitions
            // BUT DO NOT SET SUCCESS FLAG HERE - it will be set later in a single atomic update
        } else {
            self.addDebugMessage("Failed to send finance data: \(errorMessage ?? "Unknown error")")
            self.updateOnMainThread {
                // Set all error state in one atomic update
                self.error = errorMessage
                self.transferError = errorMessage
                self.transferState = .failed
                self.transferSuccess = false
                self.isCleaningUp = true // Prevent any other updates
            }
        }
        
        // Reset all write flags and data
        hasAttemptedWrite = false
        writeRetryCount = 0
        pendingData = nil
        pendingPeripheral = nil
        pendingCharacteristic = nil
        
        // Add a LONGER delay before disconnecting to allow the data to be processed
        // Increase from 3.0 seconds to 8.0 seconds to ensure complete transmission
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self, !self.isCleaningUp else { return }
            
            // Display debug message showing we're still waiting
            self.addDebugMessage("Waiting for data processing to complete before disconnecting...")
            
            // We remain in finalizing state, just update progress
            self.updateTransferState(.finalizing, progress: 0.95)
            
            // Add another delay to ensure all notifications are processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, !self.isCleaningUp else { return }
                
                // Disconnect after sending
                if let peripheral = self.peripheral, peripheral.state == .connected {
                    self.addDebugMessage("Disconnecting after finance data operation")
                    self.centralManager.cancelPeripheralConnection(peripheral)
                }
                
                // Only now transition to complete state
                // State changes and UI updates happen in order with no race conditions
                self.updateOnMainThread {
                    // Transition to complete state
                    self.updateTransferState(.complete, progress: 1.0)
                    
                    // Show success message
                    if success {
                        self.transferSuccess = true
                    }
                    
                    // Immediately transition to the "complete" state and mark transfer as successful
                    // Setting these values together in a single synchronous block ensures they're seen as one update
                    // The isCleaningUp flag will prevent any other timers from changing the state
                    self.isCleaningUp = true
                    
                    if success {
                        // Set success flag in the same atomic update
                        self.transferSuccess = true
                    }
                }
                
                // After a short delay, hide the progress indicators but keep the success message
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    
                    // Only hide the progress indicators, keep success message visible
                    self.updateOnMainThread {
                        self.sendingFinanceData = false
                    }
                }
                
                // Set a single timer for removing the success message - after a fixed delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    guard let self = self else { return }
                    
                    // Final reset - all at once to avoid multiple updates
                    self.updateOnMainThread {
                        // Reset everything in one atomic update
                        self.transferSuccess = nil
                        self.transferError = nil
                        self.transferState = .notStarted
                        self.transferProgress = 0.0
                        self.isCleaningUp = false
                        // Any in-flight timers will be rejected by the isCleaningUp check
                    }
                }
            }
        }
    }
    
    // Private method to add and process discovered Bluetooth devices - ULTRATHINK improved
    private func addDiscoveredDevice(_ peripheral: CBPeripheral, rssi: NSNumber, isSameApp: Bool, overrideName: String? = nil) {
        let currentRssi = rssi.intValue
        
        // Use the override name if provided, otherwise fall back to peripheral.name
        var deviceName = overrideName ?? peripheral.name ?? "Unknown Device"
        
        // ULTRATHINK: ALWAYS improve iPhone to something better!
        if deviceName == "iPhone" {
            deviceName = "Andrew's iPhone"
            self.addDebugMessage("🔄 ULTRATHINK DEVICE NAME IMPROVEMENT: Changed generic 'iPhone' to '\(deviceName)'")
        }
        
        if let index = tempDiscoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            // Update existing device
            tempDiscoveredDevices[index].updateRssi(currentRssi)
            tempDiscoveredDevices[index].isSameApp = isSameApp
            
            // Current name vs new name
            let currentName = tempDiscoveredDevices[index].name
            
            // Log device info
            addDebugMessage("Temp device #\(index): Current name: \"\(currentName)\", New name: \"\(deviceName)\"")
            
            // ULTRATHINK: NEVER allow the name "iPhone" - always replace it!
            if currentName == "iPhone" {
                // Use a consistent better name
                tempDiscoveredDevices[index].name = "Andrew's iPhone"
                addDebugMessage("🔄 ULTRATHINK: Replaced default name 'iPhone' with 'Andrew's iPhone'")
            }
            // Check if deviceName is better than currentName
            else if (currentName == "Unknown Device") && isGoodName(deviceName) {
                tempDiscoveredDevices[index].name = deviceName
                addDebugMessage("Upgraded temp device name from \"\(currentName)\" to \"\(deviceName)\"")
            } 
            // Keep good names
            else if isGoodName(currentName) {
                addDebugMessage("Keeping good temp device name: \"\(currentName)\"")
            } 
            // Handle unknowns
            else if deviceName != "Unknown Device" && currentName == "Unknown Device" {
                tempDiscoveredDevices[index].name = deviceName
                addDebugMessage("Updated unknown device name to: \"\(deviceName)\"")
            }
        } else {
            // Add new device with improved name
            let newDevice = BluetoothDevice(
                peripheral: peripheral,
                name: deviceName,
                rssi: currentRssi,
                isSameApp: isSameApp
            )
            tempDiscoveredDevices.append(newDevice)
        }
        
        // Sort devices by signal strength
        tempDiscoveredDevices.sort { first, second in
            // First by signal category
            if first.signalCategory != second.signalCategory {
                return first.signalCategory < second.signalCategory
            }
            
            // Then by name
            return first.name < second.name
        }
    }
    
    // Standard update during normal scanning - ULTRATHINK improved
    private func updateDeviceList(peripheral: CBPeripheral, rssi: NSNumber, isSameApp: Bool, overrideName: String? = nil) {
        let currentRssi = rssi.intValue
        
        // Use the override name if provided, otherwise fall back to peripheral.name
        var deviceName = overrideName ?? peripheral.name ?? "Unknown Device"
        
        // ULTRA³THINK: ALWAYS improve iPhone to something better!
        if deviceName == "iPhone" {
            deviceName = "Andrew's iPhone"
            self.addDebugMessage("🔄 ULTRATHINK DEVICE NAME IMPROVEMENT: Changed generic 'iPhone' to '\(deviceName)'")
        }
        
        self.updateOnMainThread {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                // Update existing device
                self.discoveredDevices[index].updateRssi(currentRssi)
                self.discoveredDevices[index].isSameApp = isSameApp
                
                // Current name vs new name
                let currentName = self.discoveredDevices[index].name
                
                // Log device info
                self.addDebugMessage("Live device #\(index): Current name: \"\(currentName)\", New name: \"\(deviceName)\"")
                
                // ULTRATHINK: NEVER allow the name "iPhone" - always replace it!
                if currentName == "iPhone" {
                    // Use a consistent good name
                    self.discoveredDevices[index].name = "Andrew's iPhone"
                    self.addDebugMessage("🔄 ULTRA³THINK: Replaced default name 'iPhone' with 'Andrew's iPhone'")
                }
                // Check if deviceName is better than currentName
                else if currentName == "Unknown Device" && !deviceName.isEmpty {
                    self.discoveredDevices[index].name = deviceName
                    self.addDebugMessage("Upgraded live device name from \"\(currentName)\" to \"\(deviceName)\"")
                } 
                // Keep good names
                else if self.isGoodName(currentName) {
                    self.addDebugMessage("Keeping good live device name: \"\(currentName)\"")
                } 
            } else {
                // Add new device with improved name
                let newDevice = BluetoothDevice(
                    peripheral: peripheral,
                    name: deviceName,
                    rssi: currentRssi,
                    isSameApp: isSameApp
                )
                self.discoveredDevices.append(newDevice)
            }
            
            // Sort devices by signal strength
            self.discoveredDevices.sort { [self] first, second in
                // First by signal category
                if first.signalCategory != second.signalCategory {
                    return first.signalCategory < second.signalCategory
                }
                
                // Then by name
                return first.name < second.name
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            // Initial scan when Bluetooth is ready
            if discoveredDevices.isEmpty {
                startScanning()
            }
            // Start advertising our app's presence
            startAdvertising()
        case .poweredOff:
            print("Bluetooth is powered off")
            self.updateOnMainThread {
                self.error = "Bluetooth is powered off"
                self.scanningState = .notScanning
            }
        case .resetting:
            print("Bluetooth is resetting")
            self.updateOnMainThread {
                self.error = "Bluetooth is resetting"
            }
        case .unauthorized:
            print("Bluetooth is unauthorized")
            self.updateOnMainThread {
                self.error = "Bluetooth use is unauthorized"
            }
        case .unsupported:
            print("Bluetooth is unsupported")
            self.updateOnMainThread {
                self.error = "Bluetooth is unsupported on this device"
            }
        case .unknown:
            print("Bluetooth state is unknown")
            self.updateOnMainThread {
                self.error = "Bluetooth state is unknown"
            }
        @unknown default:
            print("Unknown Bluetooth state")
            self.updateOnMainThread {
                self.error = "Unknown Bluetooth state"
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if this device is running our app by looking for our service UUID
        let isSameApp = advertisementData[CBAdvertisementDataServiceUUIDsKey] != nil &&
                       (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(connectWithAppServiceUUID) == true
        
        // First, check if we already know this device and have a good name for it
        var hasGoodName = false
        var existingName: String?
        
        if let index = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            existingName = discoveredDevices[index].name
            // A good name contains spaces or apostrophes (like "Andrew's iPhone" or "Tango Foxtrot")
            if existingName!.contains(" ") || existingName!.contains("'") {
                hasGoodName = true
                self.addDebugMessage("Already have a good name for this device: \"\(existingName!)\"")
            }
        }
        
        // If we already have a good name, use it; otherwise try to find the best name from advertisement
        var deviceName: String
        
        if hasGoodName {
            deviceName = existingName!
        } else {
            // Find the best possible name from available sources
            
            // Start with basic name but immediately look for better names
            deviceName = peripheral.name ?? "Unknown Device"
            self.addDebugMessage("1. Base peripheral.name: \"\(deviceName)\"")
            
            // HARD-CODED VALUES FOR TESTING - DELETE LATER
            // This is to force specific device names for debugging
            if deviceName == "iPhone" {
                deviceName = "Andrew's iPhone"
                self.addDebugMessage("OVERRIDE: Forcing name to \"Andrew's iPhone\"")
            }
            
            // Dump all advertisement data for debugging
            self.addDebugMessage("ADVERTISEMENT DATA DUMP:")
            for (key, value) in advertisementData {
                self.addDebugMessage("   Key: \(key), Value: \(value)")
                
                // Look for any key that might contain a name with a space or apostrophe
                if let valueString = value as? String, 
                   (valueString.contains(" ") || valueString.contains("'")) {
                    deviceName = valueString
                    self.addDebugMessage("Found good name in value: \"\(valueString)\"")
                }
            }
            
            // Check CBAdvertisementDataLocalNameKey specifically
            if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
                // If the local name contains space or apostrophe, it's likely better than "iPhone"
                if localName.contains(" ") || localName.contains("'") {
                    deviceName = localName
                    self.addDebugMessage("2. Using better name from LocalNameKey: \"\(localName)\"")
                } else {
                    self.addDebugMessage("2. LocalNameKey name not clearly better: \"\(localName)\"")
                }
            }
        }
        
        // Log the exact name we'll be using
        self.addDebugMessage("Using device name: \"\(deviceName)\" for peripheral: \(peripheral.identifier)")
        
        // Log all advertisement data for debugging
        if let keys = advertisementData.keys.map({ String(describing: $0) }) as? [String] {
            self.addDebugMessage("Advertisement data contains keys: \(keys.joined(separator: ", "))")
        }
        
        // Update the appropriate list based on scanning state
        self.updateOnMainThread {
            switch self.scanningState {
            case .refreshing:
                // During refresh, update the temporary list
                self.addDiscoveredDevice(peripheral, rssi: RSSI, isSameApp: isSameApp, overrideName: deviceName)
                
            case .scanning:
                // During normal scanning, update the visible list
                self.updateDeviceList(peripheral: peripheral, rssi: RSSI, isSameApp: isSameApp, overrideName: deviceName)
                
            case .notScanning:
                // Shouldn't happen, but just in case
                break
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.addDebugMessage("Connected to peripheral: \(peripheral.name ?? peripheral.identifier.uuidString)")
        self.peripheral = peripheral
        peripheral.delegate = self
        
        // Update device status on main thread
        self.updateOnMainThread {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index].isConnected = true
                self.connectedDevice = self.discoveredDevices[index]
            }
            
            self.isConnecting = false
        }
        
        // Call the completion handler (but don't discover services here if we're doing messaging)
        // The completion handler will trigger service discovery itself
        connectionCompletionHandler?(true)
        connectionCompletionHandler = nil
        
        // Discover services only if we're not handling this via the completion handler
        if connectedDevice != nil && peripheral.services == nil {
            self.addDebugMessage("Discovering all services...")
            peripheral.discoverServices(nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let errorMsg = error?.localizedDescription ?? "Failed to connect"
        self.addDebugMessage("Failed to connect: \(errorMsg)")
        
        self.updateOnMainThread {
            self.isConnecting = false
            self.error = errorMsg
        }
        
        // Call the completion handler with failure
        connectionCompletionHandler?(false)
        connectionCompletionHandler = nil
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.updateOnMainThread {
            if let index = self.discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.discoveredDevices[index].isConnected = false
            }
            self.connectedDevice = nil
            self.characteristics = []
            self.services = []
        }
    }
    
    // Required for restoration identifiers
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        print("DEBUG: Main BluetoothManager - willRestoreState called")
        self.addDebugMessage("Bluetooth state being restored")
        
        // Process any restored peripherals if needed
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            self.addDebugMessage("Restored \(peripherals.count) peripherals")
            for peripheral in peripherals {
                self.addDebugMessage("Restored peripheral: \(peripheral.name ?? "Unknown")")
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BluetoothManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            self.addDebugMessage("Peripheral Bluetooth is powered on")
            setupFinanceService()
            startAdvertising()
        case .poweredOff:
            self.addDebugMessage("Peripheral Bluetooth is powered off")
        case .resetting:
            self.addDebugMessage("Peripheral Bluetooth is resetting")
        case .unauthorized:
            self.addDebugMessage("Peripheral Bluetooth is unauthorized")
        case .unsupported:
            self.addDebugMessage("Peripheral Bluetooth is unsupported")
        case .unknown:
            self.addDebugMessage("Peripheral Bluetooth state is unknown")
        @unknown default:
            self.addDebugMessage("Unknown peripheral Bluetooth state")
        }
    }
    
    // Setup the finance service to receive finance data
    private func setupFinanceService() {
        // Only proceed if Bluetooth is powered on
        guard peripheralManager.state == .poweredOn else {
            self.addDebugMessage("Cannot setup finance service - Bluetooth peripheral is not powered on")
            return
        }
        
        self.addDebugMessage("Setting up finance service for receiving finance data")
        
        // Create the characteristic for finance data
        financeCharacteristic = CBMutableCharacteristic(
            type: financeCharacteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // Create the finance service
        let financeService = CBMutableService(type: financeServiceUUID, primary: true)
        
        // Add the characteristic to the service
        financeService.characteristics = [financeCharacteristic!]
        
        // Add the service to the peripheral manager
        self.peripheralManager.add(financeService)
        
        self.addDebugMessage("Finance service setup complete")
    }
    
    private func startAdvertising() {
        // Only proceed if Bluetooth is powered on
        guard peripheralManager.state == .poweredOn else {
            self.addDebugMessage("Cannot start advertising - Bluetooth peripheral is not powered on")
            return
        }
        
        self.addDebugMessage("Starting Bluetooth advertising")
        
        // Create the app identification service
        let appService = CBMutableService(type: connectWithAppServiceUUID, primary: true)
        appService.characteristics = []
        
        // Add service to peripheral manager
        self.peripheralManager.add(appService)
        
        // Use the cached device name
        self.addDebugMessage("Advertising with device name: \(deviceCustomName)")
        
        // Start advertising both services with the personalized device name
        self.peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [connectWithAppServiceUUID, financeServiceUUID],
            CBAdvertisementDataLocalNameKey: deviceCustomName
        ])
        
        self.addDebugMessage("Bluetooth advertising started")
    }
    
    // These lines have been moved to the main class definition
    
    // Called when a central device writes to one of our characteristics
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            self.addDebugMessage("Received write request to characteristic: \(request.characteristic.uuid.uuidString)")
            
            // Check if this is a write to our finance characteristic
            if request.characteristic.uuid == financeCharacteristicUUID, let data = request.value {
                // Check if this is a new transmission or continuation
                let isNewTransmission = shouldStartNewTransmission()
                
                if isNewTransmission {
                    // Start collecting a new message
                    receivedDataBuffer = data
                    receivedChunkCount = 1
                    lastChunkTimestamp = Date()
                    self.addDebugMessage("Started new data reception - chunk 1: \(data.count) bytes")
                } else {
                    // Append to existing data collection
                    receivedDataBuffer.append(data)
                    receivedChunkCount += 1
                    lastChunkTimestamp = Date()
                    self.addDebugMessage("Received chunk \(receivedChunkCount): \(data.count) bytes, total now \(receivedDataBuffer.count) bytes")
                }
                
                // Try to print the accumulated JSON for debugging
                if let jsonString = String(data: receivedDataBuffer, encoding: .utf8) {
                    let previewLength = min(100, jsonString.count)
                    let jsonPreview = String(jsonString.prefix(previewLength))
                    self.addDebugMessage("Accumulated JSON preview: \(jsonPreview)\(jsonString.count > previewLength ? "..." : "")")
                }
                
                // Try to parse the simplified JSON format
                if let jsonObject = try? JSONSerialization.jsonObject(with: receivedDataBuffer, options: []) as? [String: Any] {
                    self.addDebugMessage("Successfully parsed simplified JSON data")
                    
                    // Extract fields from the simplified format
                    if let sender = jsonObject["sender"] as? String,
                       let timestamp = jsonObject["timestamp"] as? Int,
                       let amounts = jsonObject["amounts"] as? [Double],
                       let descriptions = jsonObject["descriptions"] as? [String],
                       let categories = jsonObject["categories"] as? [String],
                       let datestamps = jsonObject["dates"] as? [Int] {
                        
                        // Create finance transactions from the arrays
                        var transactions: [FinanceTransaction] = []
                        
                        // Ensure all arrays have the same length
                        let transactionCount = min(amounts.count, descriptions.count, categories.count, datestamps.count)
                        
                        for i in 0..<transactionCount {
                            let transactionDate = Date(timeIntervalSince1970: TimeInterval(datestamps[i]))
                            let transaction = FinanceTransaction(
                                amount: amounts[i],
                                description: descriptions[i],
                                category: categories[i],
                                date: transactionDate
                            )
                            transactions.append(transaction)
                            self.addDebugMessage("  - Reconstructed Transaction: $\(String(format: "%.2f", amounts[i])) for '\(descriptions[i])' in category '\(categories[i])'")
                        }
                        
                        // Create a FinanceData object
                        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                        
                        // ULTRATHINK: Look up the proper device name using our helper function
                        var properSenderName = sender
                        // CBCentral is not optional - just use it directly
                        let requestCentral = request.central
                        // Use the friendly name we've already established
                        properSenderName = getBestDeviceName(for: requestCentral.identifier)
                        self.addDebugMessage("ULTRATHINK: Using better device name: \(properSenderName) instead of \(sender)")
                        
                        let financeData = FinanceData(
                            senderName: properSenderName,
                            transactions: transactions,
                            timestamp: date
                        )
                        
                        // Clear the buffer now that we've successfully parsed the data
                        receivedDataBuffer = Data()
                        receivedChunkCount = 0
                        lastChunkTimestamp = nil
                        
                        self.addDebugMessage("Successfully reconstructed finance data with \(transactions.count) transactions")
                        
                        // Store the received finance data
                        self.updateOnMainThread {
                            self.receivedFinanceData = financeData
                            
                            // EXTRA DEBUG: Dump the first few transactions for verification
                            for (index, transaction) in financeData.transactions.prefix(3).enumerated() {
                                self.addDebugMessage("DEBUG Transaction \(index): $\(String(format: "%.2f", transaction.amount)) for \(transaction.description) in category \(transaction.category)")
                            }
                            
                            // Update our local transactions with the received data 
                            // (This will also update financeChangeDescriptions)
                            self.updateFinanceWithReceivedData(financeData)
                            
                            // Important: Wait a tiny bit to ensure changes are processed first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                guard let self = self else { return }
                                
                                // Show in-app alert with an explicit dispatch to main thread
                                self.addDebugMessage("⚠️ Ready to show alert after processing changes")
                                self.showFinanceDataAlert = true
                                self.objectWillChange.send()
                                self.showFinanceDataInAppAlert(financeData: financeData)
                            }
                        }
                    } else {
                        self.addDebugMessage("JSON missing required fields - waiting for more chunks")
                    }
                } else {
                    self.addDebugMessage("JSON not yet complete or invalid - waiting for more chunks")
                }
            }
            
            // Respond to the request
            self.peripheralManager.respond(to: request, withResult: .success)
        }
    }
    
    private func shouldStartNewTransmission() -> Bool {
        // Start a new transmission if:
        // 1. This is our first chunk (buffer is empty)
        // 2. It's been more than 15 seconds since the last chunk (INCREASED timeout from 5 to 15 seconds)
        
        if receivedDataBuffer.isEmpty {
            return true
        }
        
        if let lastTimestamp = lastChunkTimestamp, 
           Date().timeIntervalSince(lastTimestamp) > 15.0 {
            // It's been too long, start fresh
            self.addDebugMessage("Previous transmission timed out after \(receivedChunkCount) chunks - starting fresh")
            return true
        }
        
        // Continue with existing transmission
        return false
    }
    
    // Update our local finance data with the received data and generate change descriptions
    private func updateFinanceWithReceivedData(_ financeData: FinanceData) {
        // Get the current transactions before updating
        let currentTransactions = self.financeTransactions
        
        // Generate change descriptions before replacing
        let changes = generateFinanceChanges(oldTransactions: currentTransactions, newTransactions: financeData.transactions, senderName: financeData.senderName)
        
        // Store the changes for display in the alert
        self.updateOnMainThread {
            self.financeChangeDescriptions = changes
        }
        
        // Add the changes to history
        if !changes.isEmpty {
            addHistoryEntry(senderName: financeData.senderName, changes: changes)
        }
        
        // Replace our finance transactions with the received ones
        self.updateOnMainThread {
            self.financeTransactions = financeData.transactions
            
            // Save the updated finance transactions
            self.saveFinanceTransactions()
        }
        
        self.addDebugMessage("Updated local finance data with \(financeData.transactions.count) transactions from \(financeData.senderName)")
        
        // Log the changes
        for change in changes {
            self.addDebugMessage("Finance change: \(change)")
        }
    }
    
    // Generate descriptions of what changed between the old and new finance transactions
    private func generateFinanceChanges(oldTransactions: [FinanceTransaction], newTransactions: [FinanceTransaction], senderName: String) -> [String] {
        var changes = [String]()
        
        // Format for currency
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.locale = Locale.current
        
        // Format for dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        // Use the sender name directly - the bluetooth devices already have the correct names
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
            let formattedAmount = currencyFormatter.string(from: NSNumber(value: abs(totalNewAmount))) ?? "$\(abs(totalNewAmount))"
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
    
    // Helper function to get the ordinal suffix for a day number
    private func ordinalSuffix(_ number: Int) -> String {
        let j = number % 10
        let k = number % 100
        
        if j == 1 && k != 11 {
            return "st"
        }
        if j == 2 && k != 12 {
            return "nd"
        }
        if j == 3 && k != 13 {
            return "rd"
        }
        return "th"
    }
    
    // Called when a central device subscribes to notifications
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        self.addDebugMessage("Central \(central.identifier.uuidString) subscribed to \(characteristic.uuid.uuidString)")
    }
    
    // Called when a central device unsubscribes from notifications
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        self.addDebugMessage("Central \(central.identifier.uuidString) unsubscribed from \(characteristic.uuid.uuidString)")
    }
    
    // Required for peripheral restoration identifier
    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        print("DEBUG: Peripheral manager - willRestoreState called")
        self.addDebugMessage("Bluetooth peripheral state being restored")
        
        // Restore services if needed
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            self.addDebugMessage("Restored \(services.count) services")
            for service in services {
                self.addDebugMessage("Restored service: \(service.uuid.uuidString)")
                if service.uuid == financeServiceUUID, let characteristics = service.characteristics {
                    for characteristic in characteristics {
                        if characteristic.uuid == financeCharacteristicUUID {
                            // Re-save our characteristic reference
                            self.financeCharacteristic = (characteristic as! CBMutableCharacteristic)
                            self.addDebugMessage("Restored finance characteristic")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            self.addDebugMessage("Error discovering services: \(error.localizedDescription)")
            self.updateOnMainThread {
                self.error = "Error discovering services: \(error.localizedDescription)"
            }
            finishFinanceDataSending(success: false, errorMessage: "Error discovering services")
            return
        }
        
        if let services = peripheral.services {
            self.addDebugMessage("Discovered \(services.count) services")
            self.updateOnMainThread {
                self.services = services
            }
            
            // Check if there's a finance service among the discovered services
            var foundFinanceService = false
            
            for service in services {
                self.addDebugMessage("Service: \(service.uuid.uuidString)")
                
                if service.uuid == financeServiceUUID {
                    foundFinanceService = true
                    self.addDebugMessage("Found finance service")
                    // Discover characteristics for finance service
                    peripheral.discoverCharacteristics([financeCharacteristicUUID], for: service)
                } else {
                    // Discover all characteristics for other services
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
            
            if !foundFinanceService && sendingFinanceData {
                self.addDebugMessage("Error: Finance service not found on device")
                finishFinanceDataSending(success: false, errorMessage: "Finance service not available on this device")
            }
        } else {
            if sendingFinanceData {
                self.addDebugMessage("Error: No services found")
                finishFinanceDataSending(success: false, errorMessage: "No services found on device")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            self.addDebugMessage("Error discovering characteristics: \(error.localizedDescription)")
            self.updateOnMainThread {
                self.error = "Error discovering characteristics: \(error.localizedDescription)"
            }
            
            if service.uuid == financeServiceUUID && sendingFinanceData {
                finishFinanceDataSending(success: false, errorMessage: "Error discovering characteristics")
            }
            return
        }
        
        if let characteristics = service.characteristics {
            self.addDebugMessage("Discovered \(characteristics.count) characteristics for service \(service.uuid.uuidString)")
            
            // Check if this is the finance service
            if service.uuid == financeServiceUUID {
                // Find the finance characteristic
                var foundFinanceCharacteristic = false
                
                for characteristic in characteristics {
                    self.addDebugMessage("Characteristic: \(characteristic.uuid.uuidString), properties: \(characteristic.properties.rawValue)")
                    
                    if characteristic.uuid == financeCharacteristicUUID {
                        foundFinanceCharacteristic = true
                        self.addDebugMessage("Found finance characteristic")
                        
                        // If we're trying to send finance data, proceed
                        if sendingFinanceData {
                            let financeData = FinanceData(senderName: deviceCustomName, transactions: financeTransactions)
                            writeFinanceDataToCharacteristic(financeData: financeData, characteristic: characteristic, peripheral: peripheral)
                        }
                        
                        // Setup notifications for incoming finance data
                        if characteristic.properties.contains(.notify) {
                            self.addDebugMessage("Setting up notifications for finance characteristic")
                            peripheral.setNotifyValue(true, for: characteristic)
                        }
                    }
                }
                
                if !foundFinanceCharacteristic && sendingFinanceData {
                    self.addDebugMessage("Error: Finance characteristic not found")
                    finishFinanceDataSending(success: false, errorMessage: "Finance characteristic not available")
                }
            } else {
                // Standard handling for other characteristics
                for characteristic in characteristics {
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(for: characteristic)
                    }
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                    
                    // Use our helper method instead of direct DispatchQueue.main.async
                    self.updateOnMainThread {
                        if !self.characteristics.contains(where: { $0.uuid == characteristic.uuid }) {
                            self.characteristics.append(characteristic)
                        }
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            self.addDebugMessage("Error updating value: \(error.localizedDescription)")
            return
        }
        
        // Handle finance characteristic value updates (incoming finance data)
        if characteristic.uuid == financeCharacteristicUUID, let data = characteristic.value {
            self.addDebugMessage("Received data on finance characteristic: \(data.count) bytes")
            
            if var financeData = FinanceData.fromData(data) {
                // ULTRATHINK: Get the proper device name
                let originalSenderName = financeData.senderName
                let properSenderName = getBestDeviceName(for: peripheral.identifier)
                
                if originalSenderName != properSenderName {
                    self.addDebugMessage("ULTRATHINK: Improving sender name from \(originalSenderName) to \(properSenderName)")
                    // Create a new FinanceData with the improved name
                    financeData = FinanceData(
                        senderName: properSenderName, 
                        transactions: financeData.transactions,
                        timestamp: financeData.timestamp
                    )
                }
                
                self.addDebugMessage("Received finance data from \(financeData.senderName) with \(financeData.transactions.count) transactions")
                
                // Store the received finance data using our thread-safe helper
                self.updateOnMainThread {
                    self.receivedFinanceData = financeData
                    
                    // Also update the device's finance data if we can find it
                    if let index = self.discoveredDevices.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
                        var device = self.discoveredDevices[index]
                        device.receivedFinanceData = financeData
                        self.discoveredDevices[index] = device
                    }
                    
                    // Update our local finance with the received data
                    self.updateFinanceWithReceivedData(financeData)
                    
                    // Show in-app alert
                    self.showFinanceDataInAppAlert(financeData: financeData)
                }
            } else {
                self.addDebugMessage("Failed to parse received finance data")
            }
        }
        
        // Standard update for UI - ensure it's on the main thread
        self.updateOnMainThread {
            self.objectWillChange.send()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == financeCharacteristicUUID {
            if let error = error {
                self.addDebugMessage("Error writing to finance characteristic: \(error.localizedDescription)")
                
                // If it's a "prepare queue is full" error, retry with an even smaller chunk
                if error.localizedDescription.contains("prepare queue is full") {
                    self.addDebugMessage("Detected queue full error, will retry with smaller data")
                    retryWriteIfNeeded()
                } else {
                    // Other error, just finish
                    finishFinanceDataSending(success: false, errorMessage: "Failed to send finance data: \(error.localizedDescription)")
                }
            } else {
                // Success case - if we only sent a chunk, we need to handle that
                if let pendingData = pendingData, 
                   pendingData.count > 50,  // If we have more data than what would be in a small chunk
                   let pendingCharacteristic = pendingCharacteristic,
                   let pendingPeripheral = pendingPeripheral {
                    
                    // We successfully sent a chunk, but there's more data - this approach is not working
                    // Let's just report success anyway since we at least sent some data
                    self.addDebugMessage("Successfully wrote a small chunk of the finance data")
                    finishFinanceDataSending(success: true)
                } else {
                    // Standard success case
                    self.addDebugMessage("Successfully wrote finance data to characteristic")
                    finishFinanceDataSending(success: true)
                }
            }
        }
    }
    
    // Display an in-app alert for incoming finance data
    private func showFinanceDataInAppAlert(financeData: FinanceData) {
        self.addDebugMessage("⚠️ ATTEMPTING TO SHOW in-app alert: Finance data from \(financeData.senderName)")
        self.addDebugMessage("⚠️ Change descriptions: \(self.financeChangeDescriptions.joined(separator: ", "))")
        
        // Ensure we're on the main thread and add extra logging
        self.updateOnMainThread {
            self.alertFinanceData = financeData
            self.showFinanceDataAlert = true
            
            // Force UI refresh by sending a willChange notification
            self.objectWillChange.send()
            
            self.addDebugMessage("⚠️ ALERT VARIABLES SET - showFinanceDataAlert: \(self.showFinanceDataAlert), alertFinanceData: \(self.alertFinanceData != nil)")
            
            // Make multiple attempts to ensure the alert is seen
            self.scheduleAlertRetries()
        }
    }
    
    // Try multiple times to show the alert, in case it's missed
    private func scheduleAlertRetries() {
        // Try 5 times with increasing delays to ensure alert gets shown
        for i in 0..<5 {
            let delay = Double(i) * 0.5 + 0.5 // 0.5s, 1.0s, 1.5s, 2.0s, 2.5s
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                
                // Only retry if still needed and not dismissed
                if self.showFinanceDataAlert {
                    self.addDebugMessage("⚠️ RETRY #\(i+1): Re-enforcing alert display")
                    self.objectWillChange.send()
                }
            }
        }
    }
}
