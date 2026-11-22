import Foundation

/// SHA-256 in plain Swift. CoreaderKit is Foundation-only, and this runs once per
/// import to recognise a file that is already in the library.
struct SHA256 {
    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var pending: [UInt8] = []
    private var byteCount: UInt64 = 0

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    mutating func update(_ data: Data) {
        byteCount &+= UInt64(data.count)
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0
            if !pending.isEmpty {
                let take = min(64 - pending.count, bytes.count)
                pending.append(contentsOf: bytes[0..<take])
                offset = take
                if pending.count == 64 {
                    let block = pending
                    pending.removeAll(keepingCapacity: true)
                    block.withUnsafeBytes { compress($0, at: 0) }
                }
            }
            while bytes.count - offset >= 64 {
                compress(bytes, at: offset)
                offset += 64
            }
            if offset < bytes.count { pending.append(contentsOf: bytes[offset...]) }
        }
    }

    mutating func finalize() -> String {
        var tail = pending
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        let bits = byteCount &* 8
        for shift in stride(from: 56, through: 0, by: -8) {
            tail.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift)))
        }
        tail.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: bytes.count, by: 64) { compress(bytes, at: offset) }
        }
        pending.removeAll()
        return state.map { String(format: "%08x", $0) }.joined()
    }

    private mutating func compress(_ bytes: UnsafeRawBufferPointer, at offset: Int) {
        var s = (state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7])
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { w in
            for i in 0..<16 {
                w[i] = UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + i * 4, as: UInt32.self))
            }
            for i in 16..<64 {
                let a = w[i - 15], b = w[i - 2]
                let s0 = (a >> 7 | a << 25) ^ (a >> 18 | a << 14) ^ (a >> 3)
                let s1 = (b >> 17 | b << 15) ^ (b >> 19 | b << 13) ^ (b >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            Self.k.withUnsafeBufferPointer { k in
                for i in 0..<64 {
                    let e = s.4, a = s.0
                    let s1 = (e >> 6 | e << 26) ^ (e >> 11 | e << 21) ^ (e >> 25 | e << 7)
                    let ch = (e & s.5) ^ (~e & s.6)
                    let t1 = s.7 &+ s1 &+ ch &+ k[i] &+ w[i]
                    let s0 = (a >> 2 | a << 30) ^ (a >> 13 | a << 19) ^ (a >> 22 | a << 10)
                    let maj = (a & s.1) ^ (a & s.2) ^ (s.1 & s.2)
                    s = (t1 &+ s0 &+ maj, s.0, s.1, s.2, s.3 &+ t1, s.4, s.5, s.6)
                }
            }
        }
        state[0] &+= s.0; state[1] &+= s.1; state[2] &+= s.2; state[3] &+= s.3
        state[4] &+= s.4; state[5] &+= s.5; state[6] &+= s.6; state[7] &+= s.7
    }

    static func hex(of data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    /// Streams the file so a large PDF is never held in memory whole.
    static func hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalize()
    }
}
