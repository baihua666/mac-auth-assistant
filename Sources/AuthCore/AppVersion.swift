import Foundation

public struct AppVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let description: String
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pattern = "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$"
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let base = value.split(separator: "+", maxSplits: 1)[0]
        let parts = base.split(separator: "-", maxSplits: 1)
        let core = parts[0].split(separator: ".").compactMap { Int($0) }
        guard core.count == 3 else { return nil }
        let pre = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []
        guard !pre.contains(where: { $0.allSatisfy(\.isNumber) && $0.count > 1 && $0.first == "0" }) else { return nil }
        major = core[0]; minor = core[1]; patch = core[2]; prerelease = pre
        description = value
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            let numericA = a.allSatisfy(\.isNumber), numericB = b.allSatisfy(\.isNumber)
            if numericA != numericB { return numericA }
            if numericA && a.count != b.count { return a.count < b.count }
            return a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
    public func isNewer(than current: Self, build: Int, currentBuild: Int) -> Bool {
        self > current || (self == current && build > currentBuild)
    }
}
