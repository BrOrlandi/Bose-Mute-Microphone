import Foundation

/// Synthesizes short cue sounds in memory (no recorded audio, no files).
public enum ToneGenerator {
    public struct Note {
        public var frequency: Double
        public var duration: Double
        public init(_ frequency: Double, _ duration: Double) {
            self.frequency = frequency
            self.duration = duration
        }
    }

    /// Descending pair: "microphone off".
    public static let muteCue = [Note(880, 0.09), Note(0, 0.04), Note(440, 0.16)]
    /// Ascending pair: "microphone on".
    public static let unmuteCue = [Note(440, 0.09), Note(0, 0.04), Note(880, 0.16)]

    /// 16-bit mono PCM WAV.
    public static func wav(_ notes: [Note], sampleRate: Double = 44_100, amplitude: Double = 0.35) -> Data {
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.duration * sampleRate)
            let fade = min(Int(0.008 * sampleRate), count / 2)
            for i in 0..<count {
                guard note.frequency > 0 else { samples.append(0); continue }
                var env = 1.0
                if i < fade { env = Double(i) / Double(fade) } else if i > count - fade { env = Double(count - i) / Double(fade) }
                let v = sin(2 * .pi * note.frequency * Double(i) / sampleRate) * amplitude * env
                samples.append(Int16(v * Double(Int16.max)))
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(dataBytes)
        samples.forEach { append($0) }
        return data
    }
}
