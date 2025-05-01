import Foundation
import CoreBluetooth
import Combine
import UIKit

/// Helper class designed to request Bluetooth permissions as early as possible in the app lifecycle
class BluetoothPermissionHelper: NSObject {
    static let shared = BluetoothPermissionHelper()
    
    private var temporaryCentralManager: CBCentralManager?
    private let bluetoothQueue = DispatchQueue(label: "com.12x.bluetoothPermissionQueue")
    
    private override init() {
        super.init()
        print("Initializing BluetoothPermissionHelper")
    }
    
    /// Request Bluetooth permissions explicitly, as early as possible
    func requestPermissions() {
        print("Requesting Bluetooth permissions early")
        
        // Create options that show the permission dialog immediately
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: "early-permission-manager"
        ]
        
        // Create a temporary manager just to trigger the permission dialog
        // This will show the permission alert without waiting for the main manager to initialize
        temporaryCentralManager = CBCentralManager(
            delegate: self,
            queue: bluetoothQueue,
            options: options
        )
        
        print("Temporary Bluetooth manager created to trigger permissions")
    }
    
    /// Clean up the temporary manager once permissions have been requested
    func cleanup() {
        print("Cleaning up temporary Bluetooth manager")
        temporaryCentralManager = nil
    }
}

extension BluetoothPermissionHelper: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Temporary Bluetooth manager state updated: \(central.state.rawValue)")
        
        // We've triggered the permission dialog, we can clean up this temporary manager
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.cleanup()
        }
    }
}