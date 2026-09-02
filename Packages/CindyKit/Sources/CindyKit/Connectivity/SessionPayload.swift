import Foundation

/// Codable DTO bridging `CindySession` (a SwiftData `@Model`, not itself `Codable`)
/// and the `[String: Any]` dictionaries `WCSession` transfers use.
public struct SessionPayload: Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let variantRawValue: String
    public let durationSeconds: TimeInterval
    public let completedRounds: Int
    public let partialReps: Int
    public let averageHeartRate: Double?
    public let activeEnergyBurned: Double?
    public let notes: String

    public init(session: CindySession) {
        self.id = session.id
        self.date = session.date
        self.variantRawValue = session.variantRawValue
        self.durationSeconds = session.durationSeconds
        self.completedRounds = session.completedRounds
        self.partialReps = session.partialReps
        self.averageHeartRate = session.averageHeartRate
        self.activeEnergyBurned = session.activeEnergyBurned
        self.notes = session.notes
    }

    /// The synthesized `Encodable` conformance calls `encodeIfPresent` for the two
    /// optional properties, so a `nil` heart rate / energy value is *omitted* from
    /// the JSON rather than encoded as `null`. That matters here: `WCSession`
    /// user-info dictionaries must be property-list-compatible, and `NSNull` (what
    /// `JSONSerialization` would produce for a JSON `null`) is not a valid plist
    /// value — so this bridge only ever produces plist-safe dictionaries.
    public func asDictionary() -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(self),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    public init?(dictionary: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: dictionary),
            let payload = try? JSONDecoder().decode(SessionPayload.self, from: data)
        else {
            return nil
        }
        self = payload
    }

    public func makeSession(source: SessionSource) -> CindySession {
        CindySession(
            id: id,
            date: date,
            variant: CindyVariant(rawValue: variantRawValue) ?? .rx,
            durationSeconds: durationSeconds,
            completedRounds: completedRounds,
            partialReps: partialReps,
            averageHeartRate: averageHeartRate,
            activeEnergyBurned: activeEnergyBurned,
            notes: notes,
            source: source
        )
    }
}
