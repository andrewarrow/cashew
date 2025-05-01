import Foundation
import CoreBluetooth

// Calendar entry for each month with a title, location, and day
struct CalendarEntry: Identifiable, Codable {
    let id: UUID
    var title: String
    var location: String
    var month: Int // 1-12 for the months of the year
    var day: Int // 1-31 for the day of the month
    
    init(title: String = "", location: String = "", month: Int, day: Int = 1) {
        self.id = UUID()
        self.title = title
        self.location = location
        self.month = month
        self.day = day
    }
}

// Calendar data model for Bluetooth transmission
struct CalendarData: Identifiable, Codable {
    let id: UUID
    let senderName: String
    let timestamp: Date
    var entries: [CalendarEntry]
    
    init(senderName: String, entries: [CalendarEntry], timestamp: Date = Date()) {
        self.id = UUID()
        self.senderName = senderName
        self.timestamp = timestamp
        self.entries = entries
    }
    
    // Convert to Data for Bluetooth transmission
    func toData() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(self)
            print("Successfully encoded CalendarData to \(data.count) bytes")
            return data
        } catch {
            print("Error encoding CalendarData: \(error)")
            return nil
        }
    }
    
    // Convert from Data received over Bluetooth
    static func fromData(_ data: Data) -> CalendarData? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let calendarData = try decoder.decode(CalendarData.self, from: data)
            print("Successfully decoded CalendarData with \(calendarData.entries.count) entries")
            return calendarData
        } catch {
            print("Error decoding CalendarData: \(error)")
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
    
    // Calendar data received from this device
    var receivedCalendarData: CalendarData?
    
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