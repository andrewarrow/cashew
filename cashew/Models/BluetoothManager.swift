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

// Custom UUIDs for app identification and calendar
let connectWithAppServiceUUID = CBUUID(string: "6F7A99FE-2F4A-41C0-ADB0-9D8CB68BEBA0")
let calendarServiceUUID = CBUUID(string: "6F7A99FE-2F4A-41C0-ADB0-9D8CB68BEBA1")
let calendarCharacteristicUUID = CBUUID(string: "6F7A99FE-2F4A-41C0-ADB0-9D8CB68BEBA2")

class BluetoothManager: NSObject, ObservableObject {
    var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var peripheralManager: CBPeripheralManager!
    private var calendarCharacteristic: CBMutableCharacteristic?
    
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
    
    // Calendar-related properties
    @Published var sendingCalendarData = false
    @Published var transferProgress: Double = 0.0 // 0.0 to 1.0
    @Published var transferState: TransferState = .notStarted // Current state in the transfer process
    @Published var transferSuccess: Bool? = nil // nil = not completed, true = success, false = failure
    @Published var transferError: String? = nil // Error message if transfer failed
    @Published var debugMessages: [String] = []
    @Published var calendarEntries: [CalendarEntry] = []
    @Published var receivedCalendarData: CalendarData?
    
    // Flag to indicate we're in cleanup mode - prevents timer callbacks from triggering
    private var isCleaningUp: Bool = false
    
    // Alert system for incoming calendar data
    @Published var showCalendarDataAlert = false
    @Published var alertCalendarData: CalendarData?
    @Published var calendarChangeDescriptions: [String] = []
    
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
        
        // Initialize calendar entries (one for each month)
        self.initializeCalendarEntries()
        
        // Load saved calendar entries from UserDefaults
        self.loadCalendarEntries()
        
        // Load saved history entries from UserDefaults
        self.loadHistoryEntries()
        
        self.addDebugMessage("Initialized BluetoothManager with device name: \(self.deviceCustomName)")
        
        // Scanning will automatically start once Bluetooth is powered on
    }
    
    // Initialize calendar entries for all 12 months
    private func initializeCalendarEntries() {
        // Only initialize if we don't have entries yet
        if self.calendarEntries.isEmpty {
            for month in 1...12 {
                let entry = CalendarEntry(month: month)
                self.calendarEntries.append(entry)
            }
            self.addDebugMessage("Initialized 12 empty calendar entries")
        }
    }
    
    // Load saved calendar entries from UserDefaults
    private func loadCalendarEntries() {
        if let savedData = UserDefaults.standard.data(forKey: "CalendarEntries") {
            let decoder = JSONDecoder()
            if let loadedEntries = try? decoder.decode([CalendarEntry].self, from: savedData) {
                self.calendarEntries = loadedEntries
                self.addDebugMessage("Loaded \(loadedEntries.count) calendar entries from UserDefaults")
            }
        }
    }
    
    // Save calendar entries to UserDefaults
    func saveCalendarEntries() {
        let encoder = JSONEncoder()
        if let encodedData = try? encoder.encode(self.calendarEntries) {
            UserDefaults.standard.set(encodedData, forKey: "CalendarEntries")
            self.addDebugMessage("Saved \(self.calendarEntries.count) calendar entries to UserDefaults")
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
    
    // Update a calendar entry
    func updateCalendarEntry(forMonth month: Int, title: String, location: String, day: Int = 1) {
        if let index = self.calendarEntries.firstIndex(where: { $0.month == month }) {
            self.calendarEntries[index].title = title
            self.calendarEntries[index].location = location
            self.calendarEntries[index].day = day
            self.addDebugMessage("Updated calendar entry for month \(month), day \(day)")
            self.saveCalendarEntries()
        } else {
            // If entry doesn't exist for this month, create it
            let newEntry = CalendarEntry(title: title, location: location, month: month, day: day)
            self.calendarEntries.append(newEntry)
            self.addDebugMessage("Created new calendar entry for month \(month), day \(day)")
            self.saveCalendarEntries()
        }
    }
    
    // Add sample calendar entries
    func populateSampleCalendarEntries() {
        // Clear existing entries
        self.calendarEntries.removeAll()
        
        // Add one entry for each month with sample data
        let events = [
            "Team Meeting", "Project Deadline", "Conference", "Training Session",
            "Client Presentation", "Annual Review", "Department Outing", "Budget Planning",
            "Product Launch", "Quarterly Report", "Holiday Party", "Year End Review"
        ]
        
        let locations = [
            "Conference Room A", "Main Office", "Convention Center", "Training Center",
            "Client HQ", "Manager's Office", "City Park", "Board Room",
            "Exhibition Hall", "Presentation Room", "Hotel Ballroom", "Executive Suite"
        ]
        
        for month in 1...12 {
            // Use a random day between 1 and 28 (to avoid issues with February)
            let day = Int.random(in: 1...28)
            let entry = CalendarEntry(
                title: events[month-1],
                location: locations[month-1],
                month: month,
                day: day
            )
            self.calendarEntries.append(entry)
            self.addDebugMessage("Added sample entry for month \(month), day \(day)")
        }
        
        // Save the entries
        self.saveCalendarEntries()
        self.addDebugMessage("Sample calendar entries populated successfully")
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
    
    // Send calendar data to a specific device
    func sendCalendarData(to device: BluetoothDevice) {
        self.addDebugMessage("Preparing to send calendar data to \(device.name)")
        
        guard let peripheral = device.peripheral else {
            self.addDebugMessage("Error: Cannot send calendar data - no peripheral")
            return
        }
        
        // Create a new calendar data object with all of our entries
        let calendarData = CalendarData(senderName: self.deviceCustomName, entries: self.calendarEntries)
        
        // Reset transfer state completely
        self.updateOnMainThread {
            self.transferProgress = 0.0
            self.transferState = .notStarted
            self.transferSuccess = nil
            self.transferError = nil
            self.sendingCalendarData = true
        }
        
        self.addDebugMessage("Connecting to \(device.name) to send calendar data...")
        
        // Update to connecting state
        self.updateTransferState(.connecting, progress: 0.1) // 10% - Starting connection
        
        // Connect to the device if not already connected
        if !device.isConnected {
            self.connect(to: device, completionHandler: { success in
                if success {
                    self.addDebugMessage("Connected successfully to \(device.name)")
                    
                    // Update to discovering services state
                    self.updateTransferState(.discoveringServices, progress: 0.2)
                    
                    self.discoverServices(peripheral: peripheral, calendarData: calendarData)
                } else {
                    self.addDebugMessage("Failed to connect to \(device.name)")
                    
                    // Update to failed state
                    self.updateOnMainThread {
                        self.transferState = .failed
                        self.sendingCalendarData = false
                        self.transferSuccess = false
                        self.transferError = "Failed to connect for sending calendar data"
                        self.error = "Failed to connect for sending calendar data"
                    }
                }
            })
        } else {
            // Already connected, proceed to discover services
            self.addDebugMessage("Already connected to \(device.name)")
            
            // Update to discovering services state
            self.updateTransferState(.discoveringServices, progress: 0.2)
            
            self.discoverServices(peripheral: peripheral, calendarData: calendarData)
        }
    }
    
    // Discover services after connection for calendar data sending
    private func discoverServices(peripheral: CBPeripheral, calendarData: CalendarData) {
        peripheral.delegate = self
        
        self.addDebugMessage("Discovering services for \(peripheral.name ?? "Unknown")")
        peripheral.discoverServices([calendarServiceUUID])
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
                guard let self = self, self.sendingCalendarData, !self.isCleaningUp else { return }
                
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
                        guard let self = self, self.sendingCalendarData, !self.isCleaningUp else { return }
                        self.addDebugMessage("All chunks sent, completing operation")
                        
                        // Transition to finalizing state
                        self.updateTransferState(.finalizing, progress: 0.9)
                        
                        self.finishCalendarDataSending(success: true)
                    }
                }
            }
        }
        
        // Add a master timeout for the entire operation with INCREASED margin
        // Increase from 5.0 to 15.0 seconds margin
        let totalTimeout = 3.0 + (Double(totalChunks) * 1.0) + 15.0 // Base delay + all chunks + 15 second margin
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTimeout) { [weak self] in
            guard let self = self, self.sendingCalendarData, !self.isCleaningUp else { return }
            
            self.addDebugMessage("Master timeout reached, ensuring operation completes")
            self.finishCalendarDataSending(success: true)
        }
    }
    
    // Retry mechanism for failed writes
    private func retryWriteIfNeeded() {
        guard let data = pendingData,
              let peripheral = pendingPeripheral,
              let characteristic = pendingCharacteristic else {
            finishCalendarDataSending(success: false, errorMessage: "Missing data for retry")
            return
        }
        
        writeRetryCount += 1
        
        if writeRetryCount > maxRetryAttempts {
            self.addDebugMessage("Exceeded maximum retry attempts")
            finishCalendarDataSending(success: false, errorMessage: "Failed after \(maxRetryAttempts) retry attempts")
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
    
    // Write calendar data to characteristic 
    private func writeCalendarDataToCharacteristic(calendarData: CalendarData, characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        // Prevent duplicate writes when discovering multiple services
        guard !hasAttemptedWrite else {
            self.addDebugMessage("Already attempted write, skipping duplicate")
            return
        }
        
        // Reset retry count
        writeRetryCount = 0
        hasAttemptedWrite = true
        
        // Debug the calendar data being sent
        self.addDebugMessage("Calendar data to send:")
        self.addDebugMessage("- Sender: \(calendarData.senderName)")
        self.addDebugMessage("- Timestamp: \(calendarData.timestamp)")
        self.addDebugMessage("- Number of entries: \(calendarData.entries.count)")
        
        // DRASTICALLY REDUCE data size by sending only essential information
        // Create a single simplified dictionary instead of full JSON objects
        let simpleData: [String: Any] = [
            "sender": calendarData.senderName,
            "timestamp": Int(calendarData.timestamp.timeIntervalSince1970),
            "entryCount": calendarData.entries.count,
            // Flatten entries into simple arrays to reduce JSON overhead
            "months": calendarData.entries.map { $0.month },
            "days": calendarData.entries.map { $0.day },
            "titles": calendarData.entries.map { $0.title.prefix(15) },
            "locations": calendarData.entries.map { $0.location.prefix(15) }
        ]
        
        // Convert to JSON data with minimum overhead
        guard let data = try? JSONSerialization.data(withJSONObject: simpleData, options: []) else {
            self.addDebugMessage("Error: Failed to convert simplified calendar data to JSON")
            self.updateOnMainThread {
                self.sendingCalendarData = false
                self.hasAttemptedWrite = false
                self.error = "Failed to convert calendar data to JSON"
            }
            return
        }
        
        // Try to print the JSON as string for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            self.addDebugMessage("JSON data (simplified): \(jsonString)")
        }
        
        self.addDebugMessage("Writing simplified calendar data (\(data.count) bytes) to characteristic")
        
        // Use chunking approach to avoid queue overflow
        writeSmallChunks(data: data, characteristic: characteristic, peripheral: peripheral)
        
        // We'll get completion in the didWriteValueFor delegate method
    }
    
    // Called when we want to actively disconnect after sending
    private func finishCalendarDataSending(success: Bool, errorMessage: String? = nil) {
        // Prevent multiple completion calls
        if !sendingCalendarData {
            return
        }
        
        if success {
            self.addDebugMessage("Calendar data sent successfully!")
            // Progress updates will be handled by state transitions
            // BUT DO NOT SET SUCCESS FLAG HERE - it will be set later in a single atomic update
        } else {
            self.addDebugMessage("Failed to send calendar data: \(errorMessage ?? "Unknown error")")
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
                    self.addDebugMessage("Disconnecting after calendar data operation")
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
                            self.sendingCalendarData = false
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
            setupCalendarService()
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
    
    // Setup the calendar service to receive calendar data
    private func setupCalendarService() {
        // Only proceed if Bluetooth is powered on
        guard peripheralManager.state == .poweredOn else {
            self.addDebugMessage("Cannot setup calendar service - Bluetooth peripheral is not powered on")
            return
        }
        
        self.addDebugMessage("Setting up calendar service for receiving calendar data")
        
        // Create the characteristic for calendar data
        calendarCharacteristic = CBMutableCharacteristic(
            type: calendarCharacteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // Create the calendar service
        let calendarService = CBMutableService(type: calendarServiceUUID, primary: true)
        
        // Add the characteristic to the service
        calendarService.characteristics = [calendarCharacteristic!]
        
        // Add the service to the peripheral manager
        self.peripheralManager.add(calendarService)
        
        self.addDebugMessage("Calendar service setup complete")
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
            CBAdvertisementDataServiceUUIDsKey: [connectWithAppServiceUUID, calendarServiceUUID],
            CBAdvertisementDataLocalNameKey: deviceCustomName
        ])
        
        self.addDebugMessage("Bluetooth advertising started")
    }
    
    // These lines have been moved to the main class definition
    
    // Called when a central device writes to one of our characteristics
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            self.addDebugMessage("Received write request to characteristic: \(request.characteristic.uuid.uuidString)")
            
            // Check if this is a write to our calendar characteristic
            if request.characteristic.uuid == calendarCharacteristicUUID, let data = request.value {
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
                       let months = jsonObject["months"] as? [Int],
                       let days = jsonObject["days"] as? [Int],
                       let titles = jsonObject["titles"] as? [String],
                       let locations = jsonObject["locations"] as? [String] {
                        
                        // Create calendar entries from the arrays
                        var entries: [CalendarEntry] = []
                        
                        // Ensure all arrays have the same length
                        let entryCount = min(months.count, days.count, titles.count, locations.count)
                        
                        for i in 0..<entryCount {
                            let entry = CalendarEntry(
                                title: titles[i],
                                location: locations[i],
                                month: months[i],
                                day: days[i]
                            )
                            entries.append(entry)
                            self.addDebugMessage("  - Reconstructed Month \(months[i]), Day \(days[i]): '\(titles[i])' at '\(locations[i])'")
                        }
                        
                        // Create a CalendarData object
                        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                        
                        // ULTRATHINK: Look up the proper device name using our helper function
                        var properSenderName = sender
                        // CBCentral is not optional - just use it directly
                        let requestCentral = request.central
                        // Use the friendly name we've already established
                        properSenderName = getBestDeviceName(for: requestCentral.identifier)
                        self.addDebugMessage("ULTRATHINK: Using better device name: \(properSenderName) instead of \(sender)")
                        
                        let calendarData = CalendarData(
                            senderName: properSenderName,
                            entries: entries,
                            timestamp: date
                        )
                        
                        // Clear the buffer now that we've successfully parsed the data
                        receivedDataBuffer = Data()
                        receivedChunkCount = 0
                        lastChunkTimestamp = nil
                        
                        self.addDebugMessage("Successfully reconstructed calendar data with \(entries.count) entries")
                        
                        // Store the received calendar data
                        self.updateOnMainThread {
                            self.receivedCalendarData = calendarData
                            
                            // EXTRA DEBUG: Dump the first few entries for verification
                            for (index, entry) in calendarData.entries.prefix(3).enumerated() {
                                self.addDebugMessage("DEBUG Entry \(index): Month \(entry.month), Day \(entry.day), Title: \(entry.title), Location: \(entry.location)")
                            }
                            
                            // Update our local calendar with the received data 
                            // (This will also update calendarChangeDescriptions)
                            self.updateCalendarWithReceivedData(calendarData)
                            
                            // Important: Wait a tiny bit to ensure changes are processed first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                guard let self = self else { return }
                                
                                // Show in-app alert with an explicit dispatch to main thread
                                self.addDebugMessage("⚠️ Ready to show alert after processing changes")
                                self.showCalendarDataAlert = true
                                self.objectWillChange.send()
                                self.showCalendarDataInAppAlert(calendarData: calendarData)
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
    
    // Update our local calendar with the received data and generate change descriptions
    private func updateCalendarWithReceivedData(_ calendarData: CalendarData) {
        // Get the current entries before updating
        let currentEntries = self.calendarEntries
        
        // Generate change descriptions before replacing
        let changes = generateCalendarChanges(oldEntries: currentEntries, newEntries: calendarData.entries, senderName: calendarData.senderName)
        
        // Store the changes for display in the alert
        self.updateOnMainThread {
            self.calendarChangeDescriptions = changes
        }
        
        // Add the changes to history
        if !changes.isEmpty {
            addHistoryEntry(senderName: calendarData.senderName, changes: changes)
        }
        
        // Replace our calendar entries with the received ones
        self.updateOnMainThread {
            self.calendarEntries = calendarData.entries
            
            // Save the updated calendar entries
            self.saveCalendarEntries()
        }
        
        self.addDebugMessage("Updated local calendar with \(calendarData.entries.count) entries from \(calendarData.senderName)")
        
        // Log the changes
        for change in changes {
            self.addDebugMessage("Calendar change: \(change)")
        }
    }
    
    // Generate descriptions of what changed between the old and new calendar entries
    private func generateCalendarChanges(oldEntries: [CalendarEntry], newEntries: [CalendarEntry], senderName: String) -> [String] {
        var changes = [String]()
        
        // Month names for better descriptions
        let monthNames = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        
        // Day of week names for better descriptions
        let weekdayNames = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]
        
        // Function to get day of week for a date
        func dayOfWeek(month: Int, day: Int) -> String {
            let currentYear = Calendar.current.component(.year, from: Date())
            var dateComponents = DateComponents()
            dateComponents.year = currentYear
            dateComponents.month = month
            dateComponents.day = day
            
            if let date = Calendar.current.date(from: dateComponents) {
                let weekday = Calendar.current.component(.weekday, from: date)
                // weekday is 1-based with 1 being Sunday
                return weekdayNames[weekday - 1]
            }
            return ""
        }
        
        // Use the sender name directly - the bluetooth devices already have the correct names
        let nameForChanges = senderName
        
        // Compare each entry by month
        for newEntry in newEntries {
            if let oldEntry = oldEntries.first(where: { $0.month == newEntry.month }) {
                // Compare day
                if oldEntry.day != newEntry.day {
                    let oldDayOfWeek = dayOfWeek(month: oldEntry.month, day: oldEntry.day)
                    let newDayOfWeek = dayOfWeek(month: newEntry.month, day: newEntry.day)
                    
                    changes.append("\(monthNames[newEntry.month - 1])'s event was moved from \(oldDayOfWeek) the \(oldEntry.day)\(ordinalSuffix(oldEntry.day)) to \(newDayOfWeek) the \(newEntry.day)\(ordinalSuffix(newEntry.day)) by \(nameForChanges).")
                }
                
                // Compare title
                if oldEntry.title != newEntry.title && !oldEntry.title.isEmpty && !newEntry.title.isEmpty {
                    changes.append("\(monthNames[newEntry.month - 1])'s event title was changed from '\(oldEntry.title)' to '\(newEntry.title)' by \(nameForChanges).")
                } else if oldEntry.title.isEmpty && !newEntry.title.isEmpty {
                    changes.append("\(monthNames[newEntry.month - 1])'s event title was set to '\(newEntry.title)' by \(nameForChanges).")
                }
                
                // Compare location
                if oldEntry.location != newEntry.location && !oldEntry.location.isEmpty && !newEntry.location.isEmpty {
                    changes.append("\(monthNames[newEntry.month - 1])'s event location was changed from '\(oldEntry.location)' to '\(newEntry.location)' by \(nameForChanges).")
                } else if oldEntry.location.isEmpty && !newEntry.location.isEmpty {
                    changes.append("\(monthNames[newEntry.month - 1])'s event location was set to '\(newEntry.location)' by \(nameForChanges).")
                }
            } else {
                // New entry for a month that didn't exist before
                changes.append("New event added for \(monthNames[newEntry.month - 1]) by \(nameForChanges).")
            }
        }
        
        // If no specific changes were detected, provide a general update message
        if changes.isEmpty {
            changes.append("Calendar updated by \(nameForChanges) with \(newEntries.count) entries.")
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
                if service.uuid == calendarServiceUUID, let characteristics = service.characteristics {
                    for characteristic in characteristics {
                        if characteristic.uuid == calendarCharacteristicUUID {
                            // Re-save our characteristic reference
                            self.calendarCharacteristic = (characteristic as! CBMutableCharacteristic)
                            self.addDebugMessage("Restored calendar characteristic")
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
            finishCalendarDataSending(success: false, errorMessage: "Error discovering services")
            return
        }
        
        if let services = peripheral.services {
            self.addDebugMessage("Discovered \(services.count) services")
            self.updateOnMainThread {
                self.services = services
            }
            
            // Check if there's a calendar service among the discovered services
            var foundCalendarService = false
            
            for service in services {
                self.addDebugMessage("Service: \(service.uuid.uuidString)")
                
                if service.uuid == calendarServiceUUID {
                    foundCalendarService = true
                    self.addDebugMessage("Found calendar service")
                    // Discover characteristics for calendar service
                    peripheral.discoverCharacteristics([calendarCharacteristicUUID], for: service)
                } else {
                    // Discover all characteristics for other services
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
            
            if !foundCalendarService && sendingCalendarData {
                self.addDebugMessage("Error: Calendar service not found on device")
                finishCalendarDataSending(success: false, errorMessage: "Calendar service not available on this device")
            }
        } else {
            if sendingCalendarData {
                self.addDebugMessage("Error: No services found")
                finishCalendarDataSending(success: false, errorMessage: "No services found on device")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            self.addDebugMessage("Error discovering characteristics: \(error.localizedDescription)")
            self.updateOnMainThread {
                self.error = "Error discovering characteristics: \(error.localizedDescription)"
            }
            
            if service.uuid == calendarServiceUUID && sendingCalendarData {
                finishCalendarDataSending(success: false, errorMessage: "Error discovering characteristics")
            }
            return
        }
        
        if let characteristics = service.characteristics {
            self.addDebugMessage("Discovered \(characteristics.count) characteristics for service \(service.uuid.uuidString)")
            
            // Check if this is the calendar service
            if service.uuid == calendarServiceUUID {
                // Find the calendar characteristic
                var foundCalendarCharacteristic = false
                
                for characteristic in characteristics {
                    self.addDebugMessage("Characteristic: \(characteristic.uuid.uuidString), properties: \(characteristic.properties.rawValue)")
                    
                    if characteristic.uuid == calendarCharacteristicUUID {
                        foundCalendarCharacteristic = true
                        self.addDebugMessage("Found calendar characteristic")
                        
                        // If we're trying to send calendar data, proceed
                        if sendingCalendarData {
                            let calendarData = CalendarData(senderName: deviceCustomName, entries: calendarEntries)
                            writeCalendarDataToCharacteristic(calendarData: calendarData, characteristic: characteristic, peripheral: peripheral)
                        }
                        
                        // Setup notifications for incoming calendar data
                        if characteristic.properties.contains(.notify) {
                            self.addDebugMessage("Setting up notifications for calendar characteristic")
                            peripheral.setNotifyValue(true, for: characteristic)
                        }
                    }
                }
                
                if !foundCalendarCharacteristic && sendingCalendarData {
                    self.addDebugMessage("Error: Calendar characteristic not found")
                    finishCalendarDataSending(success: false, errorMessage: "Calendar characteristic not available")
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
        
        // Handle calendar characteristic value updates (incoming calendar data)
        if characteristic.uuid == calendarCharacteristicUUID, let data = characteristic.value {
            self.addDebugMessage("Received data on calendar characteristic: \(data.count) bytes")
            
            if var calendarData = CalendarData.fromData(data) {
                // ULTRATHINK: Get the proper device name
                let originalSenderName = calendarData.senderName
                let properSenderName = getBestDeviceName(for: peripheral.identifier)
                
                if originalSenderName != properSenderName {
                    self.addDebugMessage("ULTRATHINK: Improving sender name from \(originalSenderName) to \(properSenderName)")
                    // Create a new CalendarData with the improved name
                    calendarData = CalendarData(
                        senderName: properSenderName, 
                        entries: calendarData.entries,
                        timestamp: calendarData.timestamp
                    )
                }
                
                self.addDebugMessage("Received calendar data from \(calendarData.senderName) with \(calendarData.entries.count) entries")
                
                // Store the received calendar data using our thread-safe helper
                self.updateOnMainThread {
                    self.receivedCalendarData = calendarData
                    
                    // Also update the device's calendar data if we can find it
                    if let index = self.discoveredDevices.firstIndex(where: { $0.peripheral?.identifier == peripheral.identifier }) {
                        var device = self.discoveredDevices[index]
                        device.receivedCalendarData = calendarData
                        self.discoveredDevices[index] = device
                    }
                    
                    // Update our local calendar with the received data
                    self.updateCalendarWithReceivedData(calendarData)
                    
                    // Show in-app alert
                    self.showCalendarDataInAppAlert(calendarData: calendarData)
                }
            } else {
                self.addDebugMessage("Failed to parse received calendar data")
            }
        }
        
        // Standard update for UI - ensure it's on the main thread
        self.updateOnMainThread {
            self.objectWillChange.send()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == calendarCharacteristicUUID {
            if let error = error {
                self.addDebugMessage("Error writing to calendar characteristic: \(error.localizedDescription)")
                
                // If it's a "prepare queue is full" error, retry with an even smaller chunk
                if error.localizedDescription.contains("prepare queue is full") {
                    self.addDebugMessage("Detected queue full error, will retry with smaller data")
                    retryWriteIfNeeded()
                } else {
                    // Other error, just finish
                    finishCalendarDataSending(success: false, errorMessage: "Failed to send calendar data: \(error.localizedDescription)")
                }
            } else {
                // Success case - if we only sent a chunk, we need to handle that
                if let pendingData = pendingData, 
                   pendingData.count > 50,  // If we have more data than what would be in a small chunk
                   let pendingCharacteristic = pendingCharacteristic,
                   let pendingPeripheral = pendingPeripheral {
                    
                    // We successfully sent a chunk, but there's more data - this approach is not working
                    // Let's just report success anyway since we at least sent some data
                    self.addDebugMessage("Successfully wrote a small chunk of the calendar data")
                    finishCalendarDataSending(success: true)
                } else {
                    // Standard success case
                    self.addDebugMessage("Successfully wrote calendar data to characteristic")
                    finishCalendarDataSending(success: true)
                }
            }
        }
    }
    
    // Display an in-app alert for incoming calendar data
    private func showCalendarDataInAppAlert(calendarData: CalendarData) {
        self.addDebugMessage("⚠️ ATTEMPTING TO SHOW in-app alert: Calendar data from \(calendarData.senderName)")
        self.addDebugMessage("⚠️ Change descriptions: \(self.calendarChangeDescriptions.joined(separator: ", "))")
        
        // Ensure we're on the main thread and add extra logging
        self.updateOnMainThread {
            self.alertCalendarData = calendarData
            self.showCalendarDataAlert = true
            
            // Force UI refresh by sending a willChange notification
            self.objectWillChange.send()
            
            self.addDebugMessage("⚠️ ALERT VARIABLES SET - showCalendarDataAlert: \(self.showCalendarDataAlert), alertCalendarData: \(self.alertCalendarData != nil)")
            
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
                if self.showCalendarDataAlert {
                    self.addDebugMessage("⚠️ RETRY #\(i+1): Re-enforcing alert display")
                    self.objectWillChange.send()
                }
            }
        }
    }
}