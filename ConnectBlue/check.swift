import Foundation
import CoreAudio
import IOBluetooth

// Fallback for the Bluetooth transport constant if not exposed by the SDK headers.
#if !canImport(AudioToolbox)
// No action needed; CoreAudio provides what we need. Define the constant if missing.
#endif

// Some SDKs may not surface this constant into Swift. Define it explicitly if needed.
private let kBluetoothTransportFallback: UInt32 = 0x62746C20 // 'btl '

@inline(__always)
private func bluetoothTransportConstant() -> UInt32 {
    #if canImport(AudioToolbox)
    // Prefer the SDK constant when available; otherwise, use fallback.
//    return (UInt32(bitPattern: Int32(kAudioDeviceTransportType_Bluetooth)))
//    #else
    return kBluetoothTransportFallback
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

/// Determines whether the current default output device is the given Bluetooth device.
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
    var cfName: CFString = "" as CFString
    var nameSize = UInt32(MemoryLayout<CFString>.size)
    let nameStatus = AudioObjectGetPropertyData(
        defaultID,
        &nameAddress,
        0,
        nil,
        &nameSize,
        &cfName
    )
    if nameStatus != noErr { return false }

    let audioName = cfName as String
    let btName = device.name ?? device.addressString ?? ""

    if audioName.caseInsensitiveCompare(btName) == .orderedSame { return true }
    if audioName.lowercased().hasPrefix(btName.lowercased()) { return true }

    return false
}
