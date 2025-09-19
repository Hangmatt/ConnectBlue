import Foundation
import CoreAudio

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
    return (UInt32(bitPattern: Int32(kAudioDeviceTransportType_Bluetooth)))
    #else
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

/// Determines whether the current default output device uses Bluetooth transport.
@inline(__always)
func isDefaultOutputBluetooth() -> Bool {
    let deviceID = defaultOutputDeviceID()
    if deviceID == AudioObjectID(bitPattern: 0) { return false }

    var transportType: UInt32 = 0
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &transportType
    )
    if status != noErr { return false }

    return transportType == bluetoothTransportConstant()
}
