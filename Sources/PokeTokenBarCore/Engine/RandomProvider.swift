import Foundation

/// Indirección sobre el RNG para poder fijar semillas en los tests.
public protocol RandomProvider {
    /// Uniforme en [0, 1).
    mutating func nextUnit() -> Double
    mutating func nextInt(in range: ClosedRange<Int>) -> Int
}

public struct SystemRandomProvider: RandomProvider {
    public init() {}
    public mutating func nextUnit() -> Double { Double.random(in: 0..<1) }
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int { Int.random(in: range) }
}

/// PRNG determinista (SplitMix64) para tests y para fijar ramas evolutivas.
public struct SeededRandomProvider: RandomProvider {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    private mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) &+ 1
        return range.lowerBound + Int(next() % span)
    }
}
