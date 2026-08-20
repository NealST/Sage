//
//  SystemVolumeTools.swift
//  Sage
//

import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Volume Control

nonisolated struct GetSystemVolumeTool: AgentTool {
    let definition = ToolDefinition(
        name: "get_system_volume",
        description: """
            Get the current system output volume level (0–100) and mute state. \
            Returns format: "volume: 50\nmuted: false". \
            Uses CoreAudio default output device.
            """,
        parameters: .schemaObject(properties: [:])
    )

    func call(argumentsJSON: String) throws -> String {
        let (volume, muted) = try getOutputVolume()
        let percent = Int(round(volume * 100))
        return "volume: \(percent)\nmuted: \(muted)"
    }
}

nonisolated struct SetSystemVolumeTool: AgentTool {
    let definition = ToolDefinition(
        name: "set_system_volume",
        description: """
            Set the system output volume level. Value is 0–100 (clamped if out of range). \
            Optionally set mute state. Uses CoreAudio default output device. \
            Note: changing volume while muted does NOT automatically unmute — set mute=false explicitly.
            """,
        parameters: .schemaObject(
            properties: [
                "volume": .intProperty("Volume level 0–100"),
                "mute": .boolProperty("Set true to mute, false to unmute. Omit to leave mute state unchanged."),
            ],
            required: ["volume"]
        )
    )

    private struct Args: Decodable {
        let volume: Int
        let mute: FlexibleBool?
    }

    func call(argumentsJSON: String) throws -> String {
        let args = try decodeToolArgs(argumentsJSON, as: Args.self)
        let clamped = min(max(args.volume, 0), 100)
        let floatVolume = Float32(clamped) / 100.0

        try setOutputVolume(floatVolume)

        var result = "[OK] Volume set to \(clamped)%"
        if clamped != args.volume {
            result += " (clamped from \(args.volume))"
        }

        if let mute = args.mute {
            do {
                try setOutputMute(mute.value)
                result += mute.value ? ", muted" : ", unmuted"
            } catch {
                result += " (warning: volume changed but mute toggle failed: \(error.localizedDescription))"
            }
        }

        return result
    }
}

// MARK: - CoreAudio Helpers

nonisolated private func getDefaultOutputDeviceID() throws -> AudioDeviceID {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &deviceID
    )
    guard status == noErr else {
        throw ToolError.operationFailed("Cannot access audio output device (error \(status)).")
    }
    return deviceID
}

nonisolated private func getOutputVolume() throws -> (Float32, Bool) {
    let deviceID = try getDefaultOutputDeviceID()

    var volume = Float32(0)
    var volumeSize = UInt32(MemoryLayout<Float32>.size)
    var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let volStatus = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &volumeSize, &volume)
    guard volStatus == noErr else {
        throw ToolError.operationFailed("Cannot read volume level (error \(volStatus)).")
    }

    var muted = UInt32(0)
    var muteSize = UInt32(MemoryLayout<UInt32>.size)
    var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    // Mute property may not exist on all devices — treat failure as unmuted
    let muteStatus = AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted)
    let isMuted = (muteStatus == noErr) && (muted != 0)

    return (volume, isMuted)
}

nonisolated private func setOutputVolume(_ volume: Float32) throws {
    let deviceID = try getDefaultOutputDeviceID()
    var vol = volume
    let size = UInt32(MemoryLayout<Float32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
    guard status == noErr else {
        throw ToolError.operationFailed("Cannot set volume (error \(status)). The device may not support volume control.")
    }
}

nonisolated private func setOutputMute(_ mute: Bool) throws {
    let deviceID = try getDefaultOutputDeviceID()
    var muted = UInt32(mute ? 1 : 0)
    let size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muted)
    guard status == noErr else {
        throw ToolError.operationFailed("Cannot set mute state (error \(status)). The device may not support mute.")
    }
}
