import SwiftUI

// Custom calendar data alert view for in-app notifications
struct CalendarDataAlertView: View {
    @Binding var isShowing: Bool
    let calendarData: CalendarData
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
                    Image(systemName: "calendar")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    
                    Text("Calendar Data Received")
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
                
                // Calendar data content
                VStack(alignment: .leading, spacing: 12) {
                    Text("From: \(calendarData.senderName)")
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
                                            .foregroundColor(.blue)
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
                        Text("Received calendar with \(calendarData.entries.count) entries")
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
                        Text("View Calendar")
                            .fontWeight(.medium)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
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

struct BluetoothDeviceListView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    // Add explicit state tracking to ensure alert visibility
    @State private var showDebugAlert = false
    // Add a local state mirror of the BluetoothManager alert state
    @State private var localShowAlert = false
    @State private var localAlertData: CalendarData?
    @State private var localChangeDescriptions: [String] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background - simple color that adapts to light/dark mode
                Color(UIColor.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Error Banner (if needed)
                    if let error = bluetoothManager.error {
                        ErrorBanner(message: error)
                    }
                    
                    // Safe area spacer
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 8)
                    
                    // Simple List with built-in refreshable that works reliably
                    List {
                        // Section header
                        Section(header: Text("NEARBY DEVICES").font(.caption).foregroundColor(.secondary)) {
                            // Empty state or device rows
                            if bluetoothManager.discoveredDevices.isEmpty {
                                EmptyDeviceListView()
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            } else {
                                ForEach(bluetoothManager.discoveredDevices) { device in
                                    ZStack {
                                        // Only use NavigationLink for 12x devices
                                        if device.isSameApp {
                                            NavigationLink(destination: 
                                                DeviceDetailView(device: device)
                                                    .environmentObject(bluetoothManager)
                                            ) {
                                                BluetoothDeviceRow(device: device)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        } else {
                                            BluetoothDeviceRow(device: device)
                                                .opacity(0.6)
                                                .overlay(
                                                    Text("Not available")
                                                        .font(.caption)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.black.opacity(0.6))
                                                        .foregroundColor(.white)
                                                        .cornerRadius(4),
                                                    alignment: .topTrailing
                                                )
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    // Standard pull-to-refresh with an animation that works reliably
                    .refreshable {
                        // Clear & immediate feedback to the user
                        print("Refreshing...")
                        
                        // Perform the scan (this happens AFTER the user releases)
                        await performScan()
                    }
                    
                    // Footer with last scan time
                    BluetoothFooter()
                }
                
                // In-app Calendar Data Alert - Use local state to ensure it's displayed
                if localShowAlert, let alertData = localAlertData {
                    CalendarDataAlertView(
                        isShowing: $localShowAlert,
                        calendarData: alertData,
                        changeDescriptions: localChangeDescriptions,
                        onDismiss: {
                            // Reset both local and manager state
                            localShowAlert = false
                            bluetoothManager.showCalendarDataAlert = false
                        }
                    )
                    .onAppear {
                        print("📢 ALERT APPEARED: showing calendar data from \(alertData.senderName)")
                        print("📢 Change descriptions: \(localChangeDescriptions.count)")
                    }
                }
            }
            .navigationTitle("Nearby Devices")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accentColor(Color.blue)
        // Monitor the bluetoothManager for alert changes
        // This ensures we catch all alerts and display them
        .onReceive(bluetoothManager.$showCalendarDataAlert) { showAlert in
            if showAlert, let alertData = bluetoothManager.alertCalendarData {
                // Sync the local state with the bluetoothManager state
                self.localAlertData = alertData
                self.localChangeDescriptions = bluetoothManager.calendarChangeDescriptions
                self.localShowAlert = true
                print("⚡️ ALERT STATE RECEIVED FROM MANAGER: \(alertData.senderName)")
            }
        }
        // Check periodically for pending alerts
        .onAppear {
            // Check once on appear
            checkPendingAlert()
            
            // Set up a timer to check frequently
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                checkPendingAlert()
            }
        }
    }
    
    // Helper method to handle pull-to-refresh
    func performScan() async {
        // Use the special refresh method that doesn't update UI until complete
        bluetoothManager.performRefresh()
        
        // Wait for scan to complete (3 seconds)
        do {
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        } catch {
            print("Sleep interrupted")
        }
    }
    
    // Check for a pending alert that might not have been shown
    func checkPendingAlert() {
        if bluetoothManager.showCalendarDataAlert, 
           let alertData = bluetoothManager.alertCalendarData,
           !localShowAlert {
            
            print("🚨 FOUND PENDING ALERT that wasn't displayed - showing it now")
            localAlertData = alertData
            localChangeDescriptions = bluetoothManager.calendarChangeDescriptions
            localShowAlert = true
        }
    }
}

// Empty state view with better dark mode support
struct EmptyDeviceListView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 50))
                    .foregroundColor(Color.accentColor)
            }
            .padding(.top, 30)
            
            // Text
            Text("No Bluetooth Devices Found")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Pull down to refresh and scan for nearby Bluetooth devices")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
            
            // Pull indicator
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(Color.accentColor.opacity(0.8))
                .padding(.bottom, 30)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5)
        )
        .padding(.horizontal, 20)
    }
}

// Bluetooth device row with better dark mode support
struct BluetoothDeviceRow: View {
    let device: BluetoothDevice
    @State private var showTooltip = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(device.name)
                        .font(.headline)
                        .foregroundColor(device.isSameApp ? .white : .primary)
                    
                    if device.isSameApp {
                        Text("(12x)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
                
                HStack {
                    Text("RSSI: \(device.displayRssi) dBm")
                        .font(.subheadline)
                        .foregroundColor(device.isSameApp ? .white.opacity(0.9) : .secondary)
                    
                    Text("•")
                        .foregroundColor(device.isSameApp ? .white.opacity(0.9) : .secondary)
                    
                    Text(device.signalStrengthDescription)
                        .font(.subheadline)
                        .foregroundColor(device.isSameApp ? .white : signalColor(for: device.displayRssi))
                        .fontWeight(.medium)
                }
            }
            
            Spacer()
            
            // Signal strength indicator with better visual style
            HStack(spacing: 8) {
                SignalStrengthIndicator(strength: signalStrength(for: device.displayRssi))
                    .foregroundColor(device.isSameApp ? .white : signalColor(for: device.displayRssi))
                
                if device.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(device.isSameApp ? .white : .green)
                        .font(.system(size: 18))
                }
                
                if device.isSameApp {
                    Image(systemName: "person.wave.2.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(device.isSameApp ? 
                      (colorScheme == .dark ? Color.blue : Color.blue) : 
                      Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(device.isSameApp ? 
                        Color.white.opacity(0.3) : 
                        Color.gray.opacity(colorScheme == .dark ? 0.1 : 0.2), 
                        lineWidth: device.isSameApp ? 2.0 : 0.5)
        )
    }
    
    private func signalColor(for rssi: Int) -> Color {
        if rssi > -50 {
            return .green
        } else if rssi > -70 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    private func signalStrength(for rssi: Int) -> Int {
        if rssi > -50 {
            return 3       // Strong
        } else if rssi > -70 {
            return 2       // Medium
        } else {
            return 1       // Weak
        }
    }
}

// Custom signal strength indicator with modern design
struct SignalStrengthIndicator: View {
    let strength: Int  // 1-3, where 3 is strongest
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 3) {
            Capsule()
                .frame(width: 4, height: 8)
                .opacity(strength >= 1 ? 1.0 : (colorScheme == .dark ? 0.4 : 0.25))
            
            Capsule()
                .frame(width: 4, height: 12)
                .opacity(strength >= 2 ? 1.0 : (colorScheme == .dark ? 0.4 : 0.25))
            
            Capsule()
                .frame(width: 4, height: 16)
                .opacity(strength >= 3 ? 1.0 : (colorScheme == .dark ? 0.4 : 0.25))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }
}

// Enhanced footer with adaptive colors
struct BluetoothFooter: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(Color.accentColor.opacity(0.8))
            
            Text("Last scan: \(formattedDate())")
                .font(.caption)
                .foregroundColor(.primary.opacity(0.8))
                .fontWeight(.medium)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(UIColor.systemGroupedBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: -2)
        )
    }
    
    private func formattedDate() -> String {
        if bluetoothManager.discoveredDevices.isEmpty {
            return "Never"
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        
        // Use the tracked last scan date
        return formatter.string(from: bluetoothManager.getLastScanDate())
    }
}

// Calendar History View for displaying past changes
struct HistoryView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        List {
            ForEach(bluetoothManager.historyEntries.sorted(by: { $0.date > $1.date })) { entry in
                Section(header: 
                    HStack {
                        Text(formattedDate(entry.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("From: \(formatSenderName(entry.senderName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                ) {
                    ForEach(entry.changes, id: \.self) { change in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
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
            
            if bluetoothManager.historyEntries.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No History Yet")
                                .font(.headline)
                            
                            Text("Calendar changes will appear here")
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
        .navigationTitle("Calendar History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !bluetoothManager.historyEntries.isEmpty {
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
    
    @State private var showClearConfirmation = false
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatSenderName(_ name: String) -> String {
        // Use the name directly - it already has the correct format
        return name
    }
    
    private func clearAllHistory() {
        bluetoothManager.updateOnMainThread {
            bluetoothManager.historyEntries.removeAll()
            bluetoothManager.saveHistoryEntries()
        }
    }
}

// Enhanced error banner
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
    BluetoothDeviceListView()
        .environmentObject(BluetoothManager())
}
