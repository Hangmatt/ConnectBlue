import Foundation
import IOBluetooth

@inline(__always)
func sleepSeconds(_ seconds: TimeInterval) {
    let interval = useconds_t(seconds * 1_000_000)
    usleep(interval)
}

/// Poll until the Bluetooth device reports connected (or until timeout)
/// - Returns: true if connected within timeout, false otherwise
func waitForBluetoothConnection(device: IOBluetoothDevice, timeout: TimeInterval = 15, pollInterval: TimeInterval = 0.5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if device.isConnected() {
            return true
        }
        sleepSeconds(pollInterval)
    }
    return device.isConnected()
}

/// Attempts to open a connection to a device at the given address and waits until connected or timeout.
/// - Returns: the device if found, and a Bool indicating if it became connected.
@discardableResult
func connectBluetoothDevice(addressString: String, timeout: TimeInterval = 20, pollInterval: TimeInterval = 0.5) -> (device: IOBluetoothDevice?, connected: Bool) {
    guard let device = IOBluetoothDevice(addressString: addressString) else {
        return (nil, false)
    }
    // If already connected and audio output is already routed to a Bluetooth device, exit successfully.
    if device.isConnected() && isDefaultOutput(for: device) {
        print("[Bluetooth] Device \(device.name ?? device.addressString ?? "<unknown>") is already connected and set as default audio output. Skipping connect.")
        return (device, true)
    }
    let result = device.openConnection()
    print("[Bluetooth] Open connection returned: \(result)")
    if result != kIOReturnSuccess {
        print("[Bluetooth] Failed to open connection to \(device.name ?? device.addressString ?? "<unknown>") with status \(result)")
        return (device, false)
    }
    let connected = waitForBluetoothConnection(device: device, timeout: timeout, pollInterval: pollInterval)
    print("[Bluetooth] Wait-for-connection result for \(device.name ?? device.addressString ?? "<unknown>"): \(connected)")
    return (device, connected)
}

