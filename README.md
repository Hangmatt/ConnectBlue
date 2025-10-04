# ConnectBlue

A small macOS utility that connects to a specific Bluetooth audio device and (once connected) switches the system’s default audio output to that device.

It uses:
- `IOBluetooth` to locate and connect to a device by MAC address
- `CoreAudio` to read and set the system default output device

> Platform: macOS

## Why this exists
When you have a favorite Bluetooth headset or speaker, macOS doesn’t always reconnect it on demand or make it the default output. This tool automates both steps: connect the device and set it as the default output if it’s a Bluetooth device that matches the expected name.

## Features
- Connect to a Bluetooth device by MAC address
- Poll with a timeout until the device reports as connected
- Verify the default output is a Bluetooth device with the expected name
- Switch the default audio output to the target device when needed

## Requirements
- macOS with Bluetooth available
- Xcode (recommended) to build and run
- Bluetooth permission granted to the app (System Settings → Privacy & Security → Bluetooth)

## Permissions and notes
- On first run, macOS may prompt you to allow Bluetooth access for the app/binary. You must allow it for connections to work.
- If you package this as a sandboxed app, ensure the proper Bluetooth entitlements/usage descriptions.
- `IOBluetooth` is a legacy framework but remains commonly used on macOS for classic Bluetooth device control. For BLE-only scenarios, `CoreBluetooth` is typical, but audio profiles (A2DP/HFP) are classic Bluetooth and managed at the system level.

## Setup
1. Open the project in Xcode.
2. Update the configuration constants at the top of the example (see below):
   - `deviceAddress`: the Bluetooth MAC address of your device (format like `01-23-45-67-89-AB`).
   - `deviceName`: the expected display name of the device as reported to CoreAudio.
   - `connectTimeout`: how long to wait for a connection before giving up.
   - `pollInterval`: how frequently to poll the connection state.

> Tip: You can find the MAC address from the Bluetooth debug logs or third-party tools. Many UI surfaces in recent macOS versions do not display MAC addresses directly.

## Usage
The simplest usage is to build and run the tool. If the device is reachable, it attempts to connect and then make it the default audio output.

- If your target includes argument parsing, consider adding flags like:
  - `--address 01-23-45-67-89-AB`
  - `--name "Device Name"`
  - `--timeout 20`
  - `--poll-interval 0.5`

If argument parsing is not implemented, edit the constants in the source before building.

## How it works (high level)
1. Convert the MAC address string into an `IOBluetoothDeviceAddress` and look up the device.
2. If not already connected, call `openConnection()` and poll until the device reports `isConnected()` or the timeout expires.
3. Query CoreAudio for the default output device; verify it’s Bluetooth and the name matches the expected one.
4. If not already default, set the system default output to the target device via `AudioObjectSetPropertyData`.

## Full example (Swift)
```swift
import Foundation
import IOBluetooth
import CoreAudio

// Replace with your device's Bluetooth MAC address and display name
let deviceAddress = "XX-XX-XX-XX-XX-XX"
let deviceName = "Your Bluetooth Device Name"
let connectTimeout: TimeInterval = 20.0
let pollInterval: TimeInterval = 0.5

func connectBluetoothDevice(addressString: String, timeout: TimeInterval, pollInterval: TimeInterval) -> Bool {
    guard let btAddress = IOBluetoothDevice.addressStringToDeviceAddress(addressString) else {
        print("Invalid Bluetooth address format: \(addressString)")
        return false
    }
    guard let device = IOBluetoothDevice(withAddress: &btAddress) else {
        print("Could not find device with address \(addressString)")
        return false
    }

    if device.isConnected() {
        print("Device \(device.name ?? "Unknown") is already connected.")
        return true
    }

    let openResult = device.openConnection()
    if openResult != kIOReturnSuccess {
        print("Failed to open connection to \(device.addressString ?? addressString), error: \(openResult)")
        return false
    }
    print("Connecting to \(device.name ?? addressString)...")

    let startTime = Date()
    while !device.isConnected() {
        if Date().timeIntervalSince(startTime) > timeout {
            print("Timeout waiting for device to connect.")
            device.closeConnection()
            return false
        }
        usleep(useconds_t(pollInterval * 1_000_000))
    }
    print("Device connected: \(device.name ?? addressString)")
    return true
}

func getAllAudioDevices() -> [AudioDeviceID] {
    var propertySize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                                &AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                                            mElement: kAudioObjectPropertyElementMaster),
                                                0, nil,
                                                &propertySize)
    if status != noErr {
        return []
    }
    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                        &AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                                    mElement: kAudioObjectPropertyElementMaster),
                                        0, nil,
                                        &propertySize,
                                        &devices)
    if status != noErr {
        return []
    }
    return devices
}

func getDeviceName(_ device: AudioDeviceID) -> String? {
    var name: CFString = "" as CFString
    var propertySize = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMaster)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &propertySize, &name)
    if status == noErr {
        return name as String
    }
    return nil
}

func getDeviceTransportType(_ device: AudioDeviceID) -> UInt32? {
    var transportType: UInt32 = 0
    var propertySize = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMaster)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &propertySize, &transportType)
    if status == noErr {
        return transportType
    }
    return nil
}

func isDefaultOutput(for expectedName: String) -> Bool {
    var defaultDeviceID = AudioDeviceID(0)
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMaster)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                            &address, 0, nil, &propertySize, &defaultDeviceID)
    if status != noErr {
        return false
    }
    guard let name = getDeviceName(defaultDeviceID) else {
        return false
    }

    guard let transportType = getDeviceTransportType(defaultDeviceID) else {
        return false
    }

    let kAudioDeviceTransportTypeBluetooth: UInt32 = {
        #if os(macOS)
        if #available(macOS 10.13, *) {
            return UInt32(kAudioDeviceTransportTypeBluetooth)
        } else {
            return FourCharCode("blut")
        }
        #else
        return FourCharCode("blut")
        #endif
    }()

    if transportType != kAudioDeviceTransportTypeBluetooth {
        return false
    }

    return name == expectedName
}

func setDefaultOutput(named desiredName: String) -> Bool {
    let devices = getAllAudioDevices()
    for device in devices {
        if let name = getDeviceName(device), name == desiredName {
            var deviceID = device
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMaster)
            let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                    &address,
                                                    0, nil,
                                                    UInt32(MemoryLayout<AudioDeviceID>.size),
                                                    &deviceID)
            if status == noErr {
                print("Set default audio output to: \(name)")
                return true
            } else {
                print("Failed to set default audio output, error: \(status)")
                return false
            }
        }
    }
    print("Could not find audio device named: \(desiredName)")
    return false
}

// Main flow
if connectBluetoothDevice(addressString: deviceAddress, timeout: connectTimeout, pollInterval: pollInterval) {
    if isDefaultOutput(for: deviceName) {
        print("Device \(deviceName) is already the default audio output.")
    } else {
        if setDefaultOutput(named: deviceName) {
            print("Default output switched to \(deviceName).")
        } else {
            print("Failed to switch default audio output.")
        }
    }
} else {
    print("Failed to connect to Bluetooth device.")
}
