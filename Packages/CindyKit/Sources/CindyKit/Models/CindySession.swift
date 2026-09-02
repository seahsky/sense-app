import Foundation
import SwiftData

public enum SessionSource: String, Codable, Sendable {
    case watch
    case iPhone
    case manual
}

@Model
public final class CindySession {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var variantRawValue: String
    public var durationSeconds: TimeInterval
    public var completedRounds: Int
    public var partialReps: Int
    public var averageHeartRate: Double?
    public var activeEnergyBurned: Double?
    public var notes: String
    public var sourceRawValue: String

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        variant: CindyVariant = .rx,
        durationSeconds: TimeInterval,
        completedRounds: Int,
        partialReps: Int,
        averageHeartRate: Double? = nil,
        activeEnergyBurned: Double? = nil,
        notes: String = "",
        source: SessionSource = .watch
    ) {
        self.id = id
        self.date = date
        self.variantRawValue = variant.rawValue
        self.durationSeconds = durationSeconds
        self.completedRounds = completedRounds
        self.partialReps = partialReps
        self.averageHeartRate = averageHeartRate
        self.activeEnergyBurned = activeEnergyBurned
        self.notes = notes
        self.sourceRawValue = source.rawValue
    }

    public var variant: CindyVariant {
        CindyVariant(rawValue: variantRawValue) ?? .rx
    }

    public var source: SessionSource {
        SessionSource(rawValue: sourceRawValue) ?? .manual
    }

    public var totalReps: Int {
        completedRounds * variant.repsPerRound + partialReps
    }

    public var scoreString: String {
        "\(completedRounds)+\(partialReps)"
    }
}

public enum SessionSchema {
    public static var schema: Schema {
        Schema([CindySession.self])
    }

    /// `cloudKitDatabase: .none` is the load-bearing part of this configuration —
    /// it's what keeps the store local-only, since SwiftData/CloudKit mirroring is
    /// opt-in but the ModelConfiguration default is `.automatic` when a container
    /// is otherwise eligible.
    public static func makeLocalContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
