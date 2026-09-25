//
//  SettingsStore.swift
//  ConnectBlue
//
//  Created by Matthijs on 31/03/2026.
//

import Foundation

/// Persistent configuration store for ConnectBlue writing to ~/Library/Preferences/com.hangmatt.connectblue.plist.
public struct SettingsStore {
    private static let defaults = UserDefaults(suiteName: "com.hangmatt.connectblue") ?? .standard
    
    public enum Keys {
        public static let macAddress = "macAddress"
        public static let deviceName = "deviceName"
        public static let outputName = "outputName"
    }
    
    public static let fallbackMacAddress: String = "88:C9:E8:F4:23:32"
    public static let fallbackDeviceName: String = "WH-1000XM4"
    
    /// Stored Bluetooth MAC address.
    public static var macAddress: String {
        get {
            defaults.string(forKey: Keys.macAddress) ?? fallbackMacAddress
        }
        set {
            defaults.set(newValue, forKey: Keys.macAddress)
            defaults.synchronize()
        }
    }
    
    /// Stored Bluetooth device / host name.
    public static var deviceName: String {
        get {
            defaults.string(forKey: Keys.deviceName) ?? fallbackDeviceName
        }
        set {
            defaults.set(newValue, forKey: Keys.deviceName)
            defaults.synchronize()
        }
    }
    
    /// Stored system audio output device name.
    public static var outputName: String {
        get {
            defaults.string(forKey: Keys.outputName) ?? deviceName
        }
        set {
            defaults.set(newValue, forKey: Keys.outputName)
            defaults.synchronize()
        }
    }
    
    /// Write the specified settings to persistent storage as defaults in ~/Library/Preferences/com.hangmatt.connectblue.plist.
    public static func save(mac: String, name: String, output: String) {
        macAddress = mac.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        outputName = output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
