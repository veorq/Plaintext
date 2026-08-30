import AppKit
import Foundation

@MainActor
final class TypewriterSoundPlayer {
    static let shared = TypewriterSoundPlayer()

    private var sounds: [TypewriterSound: NSSound] = [:]
    private var lastPlay = Date.distantPast

    func play(_ style: TypewriterSound) {
        guard style != .off, Date().timeIntervalSince(lastPlay) > 0.025 else { return }
        lastPlay = .now
        let sound = sounds[style] ?? makeSound(for: style)
        guard let sound else { return }
        sounds[style] = sound
        sound.stop()
        sound.volume = 0.16
        sound.play()
    }

    private func makeSound(for style: TypewriterSound) -> NSSound? {
        let destination = cacheDirectory.appendingPathComponent("plaintext-v4-\(style.rawValue).wav")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? renderWAV(style: style).write(to: destination, options: .atomic)
        }
        return NSSound(contentsOf: destination, byReference: true)
    }

    private var cacheDirectory: URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func renderWAV(style: TypewriterSound) -> Data {
        let sampleRate = 44_100
        let duration: Double = 0.058
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data()

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let sample: Double
            switch style {
            case .soft:
                sample = softSample(at: time, index: index)
            case .off:
                sample = 0
            }
            pcm.appendLittleEndian(Int16(max(-1, min(1, sample)) * Double(Int16.max)))
        }

        var wav = Data("RIFF".utf8)
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.append(Data("WAVEfmt ".utf8))
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(UInt32(sampleRate))
        wav.appendLittleEndian(UInt32(sampleRate * 2))
        wav.appendLittleEndian(UInt16(2))
        wav.appendLittleEndian(UInt16(16))
        wav.append(Data("data".utf8))
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    private func softSample(at time: Double, index: Int) -> Double {
        let lowNoise = (
            noise(index, salt: 0x50F7) +
            noise(index - 1, salt: 0x50F7) +
            noise(index - 2, salt: 0x50F7) +
            noise(index - 3, salt: 0x50F7) +
            noise(index - 4, salt: 0x50F7)
        ) / 5
        let cushion = lowNoise * exp(-time / 0.018) * 0.20
        let warmth = sin(2 * .pi * 235 * time) * exp(-time / 0.024) * 0.10
        return (cushion + warmth) * 0.60
    }

    private func noise(_ index: Int, salt: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(index)) &+ salt
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value & 0xFFFF) / 32_767.5 - 1
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
