	//
	//  AppIntent.swift
	//  ConnectBlue Widget
	//
	//  Created by Matthijs on 31/03/2026.
	//

	import WidgetKit
	import AppIntents

	struct ConfigurationAppIntent: WidgetConfigurationIntent {
			static var title: LocalizedStringResource { "Configuration" }
			static var description: IntentDescription { "This is a quickselect setting" }

			// Configurable parameter for selecting the output device.
			@Parameter(title: "Sound Device Output", default: "System")
			var soundDeviceOutput: String
	}
