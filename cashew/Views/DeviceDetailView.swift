import SwiftUI
import CoreBluetooth

struct DeviceDetailView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    let device: BluetoothDevice
    
    var body: some View {
        // Use more animation control to prevent unwanted animations
        VStack {
            Spacer()
            
            // Information about the device
            VStack(spacing: 15) {
                Image(systemName: "iphone.circle")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Connected to \(device.name)")
                    .font(.headline)
                
                Text("Signal Strength: \(device.signalStrengthDescription)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Device ID: \(device.id.uuidString.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .id("device-info") // Fixed ID to prevent animations
            
            Spacer()
            
            // Use a stable approach to show success/failure messages
            // By using Group with a single conditional content approach
            // we avoid multiple views being created and destroyed
            Group {
                if let transferSuccess = bluetoothManager.transferSuccess {
                    if transferSuccess {
                        // Success message
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                            
                            Text("Calendar Sent Successfully!")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                        .padding()
                        .transition(.opacity)
                        .id("success-message") // Stable ID
                    } else {
                        // Error message
                        VStack(spacing: 10) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            
                            Text("Failed to Send Calendar")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            if let errorMessage = bluetoothManager.transferError {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                        .padding()
                        .transition(.opacity)
                        .id("error-message") // Stable ID
                    }
                } else {
                    // Empty spacer with the same height to prevent layout shifts
                    Color.clear
                        .frame(height: 140)
                        .id("no-message") // Stable ID
                }
            }
            .animation(.easeInOut(duration: 0.5), value: bluetoothManager.transferSuccess != nil)
            
            // Send data button
            Button(action: {
                // Send calendar data to this device
                bluetoothManager.sendFinanceData(to: device)
            }) {
                HStack {
                    Image(systemName: "arrow.up.doc.fill")
                    Text("Send Calendar to \(device.name)")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(bluetoothManager.sendingCalendarData)
            
            // Progress bar and status
            if bluetoothManager.sendingCalendarData {
                VStack(spacing: 12) {
                    // Use a more stable approach to display status
                    Text(progressStatusText)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .animation(.none) // Disable animations for text
                        .frame(height: 20) // Fixed height
                        .fixedSize(horizontal: false, vertical: true) // Prevent layout shifts
                        .id(bluetoothManager.transferState) // ID based on state ensures stable identity
                    
                    // Progress bar using the actual transfer progress
                    ProgressView(value: bluetoothManager.transferProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                        .animation(.linear(duration: 0.3), value: bluetoothManager.transferProgress)
                    
                    // Percentage text - lock to state changes to reduce flickering
                    Text("\(Int(bluetoothManager.transferProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.none)
                        .id("percent-\(Int(bluetoothManager.transferProgress * 100/5)*5)") // Update in 5% increments
                    
                    // Only show spinner for active states
                    if bluetoothManager.transferState != .complete {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Processing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                // Use a key value to ensure SwiftUI treats the whole progress section as one view
                // that doesn't get recreated or animated independently
                .id("progress-section")
                .transition(.opacity) // Use a simple opacity transition when shown/hidden
                .transaction { transaction in
                    // Disable all animations by default
                    transaction.animation = nil
                }
            }
            
            Spacer()
        }
        .navigationTitle("Connect with \(device.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Get status text based on the current transfer state
    private var progressStatusText: String {
        // Use the state instead of the progress percentage
        switch bluetoothManager.transferState {
        case .notStarted:
            return "Ready to send"
        case .connecting:
            return "Connecting to device..."
        case .discoveringServices:
            return "Discovering services..."
        case .preparingData:
            return "Preparing data to send..."
        case .sending:
            return "Sending calendar data..."
        case .finalizing:
            return "Finalizing transfer..."
        case .complete:
            return "Transfer complete!"
        case .failed:
            return "Transfer failed"
        }
    }
}

#Preview {
    NavigationView {
        DeviceDetailView(device: BluetoothDevice(peripheral: nil, name: "Test Device", rssi: -50, isSameApp: true))
            .environmentObject(BluetoothManager())
    }
}
