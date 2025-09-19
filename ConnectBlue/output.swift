import Foundation
import CoreAudio

// Switch system audio output to the device with the given name
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
        var dataSize: UInt32 = 0
        let nameErr = AudioObjectGetPropertyDataSize(
            deviceIDs[i],
            &nameAddr,
            0,
            nil,
            &dataSize
        )
        if nameErr != noErr {
            continue
        }

        var mutableNameCF: CFString? = nil
        let getNameErr = withUnsafeMutablePointer(to: &mutableNameCF) { ptr in
            AudioObjectGetPropertyData(
                deviceIDs[i],
                &nameAddr,
                0,
                nil,
                &dataSize,
                ptr
            )
        }
        if getNameErr != noErr {
            continue
        }
        let nameString = (mutableNameCF as String?) ?? ""

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
