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

/// Appends a timestamped success/failure result and CLI options log entry to ~/Library/Logs/connectBlue.log.
func logExecutionResult(success: Bool, message: String, options: CLIOptions) {
    let logPath = NSString(string: "~/Library/Logs/connectBlue.log").expandingTildeInPath
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = formatter.string(from: Date())

    let statusString = success ? "SUCCESS" : "FAILURE"
    let logLine = "[\(timestamp)] STATUS: \(statusString) | Message: \(message) | MAC: \(options.macAddress) | Host: \(options.deviceName) | Output: \(options.outputName)\n"

    let fileManager = FileManager.default
    let logDir = (logPath as NSString).deletingLastPathComponent
    try? fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true, attributes: nil)

    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
        fileHandle.seekToEndOfFile()
        if let data = logLine.data(using: .utf8) {
            fileHandle.write(data)
        }
        fileHandle.closeFile()
    } else {
        try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

/// Checks if the target Bluetooth device is available (exists and is paired/known) before attempting connection.
/// - Returns: Tuple containing optional device, availability boolean, and descriptive message.
func checkDeviceAvailability(addressString: String, nameString: String) -> (device: IOBluetoothDevice?, available: Bool, reason: String) {
    guard let device = IOBluetoothDevice(addressString: addressString) else {
        return (nil, false, "Invalid MAC address or Bluetooth device creation failed for \(addressString)")
    }

    // Check paired device list or device status
    let pairedDevices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    let isPaired = device.isPaired() || pairedDevices.contains(where: {
        ($0.addressString?.caseInsensitiveCompare(addressString) == .orderedSame) ||
        ($0.name?.caseInsensitiveCompare(nameString) == .orderedSame)
    })

    if !isPaired && !device.isConnected() {
        return (device, false, "Device '\(nameString)' (\(addressString)) is not paired or registered in system Bluetooth")
    }

    return (device, true, "Device is available")
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
func connectBluetoothDevice(device: IOBluetoothDevice, timeout: TimeInterval = 20, pollInterval: TimeInterval = 0.5) -> Bool {
    // If already connected and audio output is already routed to a Bluetooth device, exit successfully.
    if device.isConnected() && isDefaultOutput(for: device) {
        print("[Bluetooth] Device \(device.name ?? device.addressString ?? "<unknown>") is already connected and set as default audio output. Skipping connect.")
        return true
    }
    let result = device.openConnection()
    print("[Bluetooth] Open connection returned: \(result)")
    if result != kIOReturnSuccess {
        print("[Bluetooth] Failed to open connection to \(device.name ?? device.addressString ?? "<unknown>") with status \(result)")
        return false
    }
    let connected = waitForBluetoothConnection(device: device, timeout: timeout, pollInterval: pollInterval)
    print("[Bluetooth] Wait-for-connection result for \(device.name ?? device.addressString ?? "<unknown>"): \(connected)")
    return connected
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

/// Returns the display name of the current system default audio output device.
func currentDefaultOutputDeviceName() -> String {
    let defaultID = defaultOutputDeviceID()
    if defaultID == AudioObjectID(bitPattern: 0) { return "<None>" }

    var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var unmanagedName: Unmanaged<CFString>?
    var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(
        defaultID,
        &nameAddress,
        0,
        nil,
        &nameSize,
        &unmanagedName
    )
    if status == noErr, let cfName = unmanagedName?.takeRetainedValue() {
        return cfName as String
    }
    return "<Unknown>"
}

/// Determines whether the current default output device corresponds to the specified Bluetooth device.
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

/// Parsed CLI arguments and options.
struct CLIOptions {
    var macAddress: String
    var deviceName: String
    var outputName: String
    var writeSettings: Bool = false
    var showSettings: Bool = false
    var printHelp: Bool = false
}

/// Prints CLI usage and available flag options.
func printHelpMessage() {
    let tool = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ConnectBlue"
    print("""
    ConnectBlue - Quick Bluetooth Device & Audio Routing Utility

    Usage:
      \(tool) [options] [MAC_ADDRESS] [DEVICE_NAME] [OUTPUT_NAME]

    Options:
      -m <mac>      Bluetooth MAC address (e.g. -m 88:C9:E8:F4:23:32)
      -d <name>     Bluetooth device / host display name (e.g. -d "Headphones")
      -o <output>   Audio output device name (defaults to --device / --mac)
      -w            Write / save specified options as persistent defaults to ~/Library/Preferences/com.hangmatt.connectblue.plist
      --show        Print currently stored default settings
      -h, --help    Show this help message

    Examples:
      \(tool) -m 88:C9:E8:F4:23:32 -d "Headphones"
      \(tool) -m 88:C9:E8:F4:23:32 -d "Headphones" -w
      \(tool) -h
      \(tool) --show
    """)
}

/// Parses command-line arguments for device MAC address, device name, audio output name, and write flags.
func parseArgs() -> CLIOptions {
    var mac = SettingsStore.macAddress
    var name = SettingsStore.deviceName
    var output: String? = nil
    var write = false
    var show = false
    var help = false
    
    var macSet = false
    var nameSet = false

    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "-m", "--mac", "--address", "-a":
            if i + 1 < args.count {
                mac = args[i + 1]
                macSet = true
                i += 1
            }
        case "-d", "--device", "--host", "--name", "-n":
            if i + 1 < args.count {
                name = args[i + 1]
                nameSet = true
                i += 1
            }
        case "-o", "--output":
            if i + 1 < args.count {
                output = args[i + 1]
                i += 1
            }
        case "-w", "--write", "--save", "-S":
            write = true
        case "--show":
            show = true
        case "-h", "--help", "help", "-?":
            help = true
        default:
            if !macSet {
                mac = arg
                macSet = true
            } else if !nameSet {
                name = arg
                nameSet = true
            } else if output == nil {
                output = arg
            }
        }
        i += 1
    }

    // Output device defaults always to --device / --mac (deviceName)
    let finalOutput = output ?? name
    return CLIOptions(
        macAddress: mac,
        deviceName: name,
        outputName: finalOutput,
        writeSettings: write,
        showSettings: show,
        printHelp: help
    )
}

/// Program entry point that attempts to connect the target Bluetooth device and set it as default output.
func main() {
    let options = parseArgs()

    if options.printHelp {
        printHelpMessage()
        return
    }

    if options.writeSettings {
        SettingsStore.save(mac: options.macAddress, name: options.deviceName, output: options.outputName)
        print("✓ Successfully saved CLI options to ~/Library/Preferences/com.hangmatt.connectblue.plist:")
        print("  MAC Address   : \(options.macAddress)")
        print("  Device Name   : \(options.deviceName)")
        print("  Output Name   : \(options.outputName)")
    }

    if options.showSettings {
        print("ConnectBlue Currently Saved Default Settings:")
        print("  -m \(SettingsStore.macAddress)")
        print("  -d \(SettingsStore.deviceName)")
        print("  -o \(SettingsStore.outputName)")
        return
    }

    print("[Main] Pre-connection availability check for '--device/--mac' (\(options.deviceName) / \(options.macAddress))...")

    // Availability check before connecting
    let (btDevice, isAvailable, availReason) = checkDeviceAvailability(addressString: options.macAddress, nameString: options.deviceName)

    guard let dev = btDevice, isAvailable else {
        let errorMsg = "Bluetooth device '--device/--mac' (\(options.deviceName) / \(options.macAddress)) is unavailable. Reason: \(availReason)"
        print("✗ FAILURE: \(errorMsg)")
        logExecutionResult(success: false, message: errorMsg, options: options)
        return
    }

    print("[Main] Target device is available. Attempting connection to \(options.deviceName)...")

    let connected = connectBluetoothDevice(device: dev, timeout: 20, pollInterval: 0.5)

    guard connected else {
        let failMsg = "Timed out or failed to connect to Bluetooth device \(options.deviceName) (\(options.macAddress))"
        print("✗ FAILURE: \(failMsg)")
        logExecutionResult(success: false, message: failMsg, options: options)
        return
    }

    if isDefaultOutput(for: dev) {
        print("[Main] Default output already set to \(options.outputName). No switch needed.")
    } else {
        print("[Main] Bluetooth connected, switching system output to \(options.outputName)...")
        setDefaultOutput(named: options.outputName)
    }

    // Verify system default output device before exiting & display success/failure message
    let currentOutput = currentDefaultOutputDeviceName()
    let isOutputVerified = isDefaultOutput(for: dev) || currentOutput.caseInsensitiveCompare(options.outputName) == .orderedSame

    if isOutputVerified {
        let succMsg = "Output device verified as '\(options.outputName)'"
        print("✓ SUCCESS: \(succMsg) (\(options.macAddress)).")
        logExecutionResult(success: true, message: succMsg, options: options)
    } else {
        let failMsg = "System output device is '\(currentOutput)', expected '\(options.outputName)'"
        print("✗ FAILURE: \(failMsg) (\(options.macAddress)).")
        logExecutionResult(success: false, message: failMsg, options: options)
    }
}

main()
