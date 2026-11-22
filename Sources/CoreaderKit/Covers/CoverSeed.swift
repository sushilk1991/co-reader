import Foundation

/// Stable 64-bit FNV-1a. `Hasher` is randomly seeded per process, so it cannot be used
/// for anything that must look the same on the next launch (cover palettes, review order).
enum FNV1a {
    static func hash(_ string: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }
}

/// Small deterministic generator (SplitMix64) for seeded geometry and layouts.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit()
    }

    mutating func int(_ upperBound: Int) -> Int {
        upperBound <= 1 ? 0 : Int(next() % UInt64(upperBound))
    }
}
