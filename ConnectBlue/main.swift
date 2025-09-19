import Foundation
import IOBluetooth

print("[Main] Starting Bluetooth connect flow...")

// Replace with your headphone's Bluetooth MAC
let deviceAddress = "00:A4:1C:CA:4B:D9"
let deviceName = "JBL Tune 770NC"

print("Attempting connection to \(deviceName)...")
print("[Main] Target device address: \(deviceAddress)")
let (device, connected) = connectBluetoothDevice(addressString: deviceAddress, timeout: 20, pollInterval: 0.5)
print("[Main] connectBluetoothDevice returned connected=\(connected)")

if let _ = device {
    if connected {
        if let dev = device {
            if isDefaultOutput(for: dev) {
                print("[Main] Default output already set to \(deviceName). No switch needed.")
            } else {
                print("[Main] Bluetooth connected, switching system output to \(deviceName)...")
                setDefaultOutput(named: deviceName)
            }
        }
    } else {
        print("[Main] Timed out waiting for Bluetooth connection to \(deviceName).")
    }
} else {
    print("Could not find device at address \(deviceAddress).")
}
