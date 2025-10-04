import Foundation
import IOBluetooth
import CoreAudio
import AudioToolbox

/// Sleeps the current thread for the specified number of seconds using microsecond precision.
/// - Parameter seconds: The duration to sleep.
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


/// Returns the CoreAudio transport type constant value for Bluetooth devices.
/// Falls back to the four-character code 'blut' when the SDK constant is unavailable.
/// - Returns: The UInt32 transport type value representing Bluetooth transport.
@inline(__always)
private func bluetoothTransportConstant() -> UInt32 {
    #if canImport(AudioToolbox)
    return kAudioDeviceTransportTypeBluetooth
    #else
    // Fallback to the CoreAudio four-character code 'blut'
    return 0x626C7574
    #endif
}

/// Returns the AudioObjectID of the current default output device, or 0 if unavailable.
@inline(__always)
private func defaultOutputDeviceID() -> AudioObjectID {
    var defaultDeviceID = AudioObjectID(bitPattern: 0)
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &defaultDeviceID
    )
    return (status == noErr) ? defaultDeviceID : AudioObjectID(bitPattern: 0)
}

/// Determines whether the current default output device corresponds to the specified Bluetooth device.
/// This checks that the current default device's transport type is Bluetooth and compares the device name
/// as a pragmatic heuristic.
/// - Parameter device: The Bluetooth device to compare against the current default audio output.
/// - Returns: `true` if the default output appears to be the provided Bluetooth device; otherwise `false`.
@inline(__always)
func isDefaultOutput(for device: IOBluetoothDevice) -> Bool {
    let defaultID = defaultOutputDeviceID()
    if defaultID == AudioObjectID(bitPattern: 0) { return false }

    // Ensure transport is Bluetooth
    var transportType: UInt32 = 0
    var transportAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var transportSize = UInt32(MemoryLayout<UInt32>.size)
    let transportStatus = AudioObjectGetPropertyData(
        defaultID,
        &transportAddress,
        0,
        nil,
        &transportSize,
        &transportType
    )
    if transportStatus != noErr || transportType != bluetoothTransportConstant() { return false }

    // Compare the CoreAudio device name to the Bluetooth device name as a pragmatic heuristic.
    var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var unmanagedName: Unmanaged<CFString>?
    var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let nameStatus = AudioObjectGetPropertyData(
        defaultID,
        &nameAddress,
        0,
        nil,
        &nameSize,
        &unmanagedName
    )
    if nameStatus != noErr { return false }
    guard let cfName = unmanagedName?.takeRetainedValue() else { return false }

    let audioName = cfName as String
    let btName = device.name ?? device.addressString ?? ""

    if audioName.caseInsensitiveCompare(btName) == .orderedSame { return true }
    if audioName.lowercased().hasPrefix(btName.lowercased()) { return true }

    return false
}

/// Switches the system audio output to the device with the given display name.
/// - Parameter outputName: The exact display name of the audio output device to select.
func setDefaultOutput(named outputName: String) {
    var deviceIDs = [AudioDeviceID](repeating: 0, count: 64)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size * deviceIDs.count)

    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &size,
        &deviceIDs
    )

    if status != noErr {
        print("Failed to get audio devices")
        return
    }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    for i in 0..<count {
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var unmanagedName: Unmanaged<CFString>?
        let getNameErr = AudioObjectGetPropertyData(
            deviceIDs[i],
            &nameAddr,
            0,
            nil,
            &nameSize,
            &unmanagedName
        )
        if getNameErr != noErr { continue }
        guard let cfName = unmanagedName?.takeRetainedValue() else { continue }
        let nameString = cfName as String

        if nameString == outputName {
            var defaultDevice = deviceIDs[i]
            var setAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let setErr = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &setAddr,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &defaultDevice
            )

            if setErr == noErr {
                print("Switched output to \(outputName)")
            } else {
                print("Failed to set output: \(setErr)")
            }
            return
        }
    }
    print("Audio device \(outputName) not found")
}

/// Parses command-line arguments for device MAC address and display name.
/// Supports flags (--address/-a, --name/-n) or positional arguments in order: <MAC> <Name>.
/// - Parameters:
///   - defaultAddress: The default Bluetooth MAC address to use when not provided.
///   - defaultName: The default display name to use when not provided.
/// - Returns: A tuple containing the resolved address and name.
func parseArgs(defaultAddress: String, defaultName: String) -> (address: String, name: String) {
    var address = defaultAddress
    var name = defaultName
    var addressSet = false
    var nameSet = false

    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--help", "-h":
            let tool = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "tool"
            print("Usage: \(tool) [--address <MAC>] [--name <DeviceName>] or positional: <MAC> <DeviceName>")
            print("Examples:")
            print("  \(tool) 11:22:33:44:55:66 \"My Headphones\"")
            print("  \(tool) --address 11:22:33:44:55:66 --name \"My Headphones\"")
            exit(0)
        case "--address", "-a":
            if i + 1 < args.count { address = args[i + 1]; addressSet = true; i += 1 }
        case "--name", "-n":
            if i + 1 < args.count { name = args[i + 1]; nameSet = true; i += 1 }
        default:
            if !addressSet { address = arg; addressSet = true }
            else if !nameSet { name = arg; nameSet = true }
        }
        i += 1
    }
    return (address, name)
}

/// Program entry point that attempts to connect the target Bluetooth device and set it as default output.
func main() {
    print("[Main] Starting Bluetooth connect flow...")

    // Defaults can be overridden via CLI args.
    let defaultDeviceAddress = "88:C9:E8:F4:23:32"
    let defaultDeviceName = "Headphones"
    let (deviceAddress, deviceName) = parseArgs(defaultAddress: defaultDeviceAddress, defaultName: defaultDeviceName)

    print("Attempting connection to \(deviceName)...")
    print("[Main] Target device address: \(deviceAddress)")

    let (device, connected) = connectBluetoothDevice(addressString: deviceAddress, timeout: 20, pollInterval: 0.5)
    print("[Main] connectBluetoothDevice returned connected=\(connected)")

    guard let dev = device else {
        print("Could not find device at address \(deviceAddress).")
        return
    }

    guard connected else {
        print("[Main] Timed out waiting for Bluetooth connection to \(deviceName).")
        return
    }

    if isDefaultOutput(for: dev) {
        print("[Main] Default output already set to \(deviceName). No switch needed.")
    } else {
        print("[Main] Bluetooth connected, switching system output to \(deviceName)...")
        setDefaultOutput(named: deviceName)
    }
}

main()
