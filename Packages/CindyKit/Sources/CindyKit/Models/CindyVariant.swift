import Foundation

public enum CindyVariant: String, Codable, CaseIterable, Sendable, Identifiable {
    case rx
    case scaled
    case babyCindy
    case weightedVest
    case hardCindy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rx: return "Rx"
        case .scaled: return "Scaled"
        case .babyCindy: return "Baby Cindy"
        case .weightedVest: return "Weighted Vest"
        case .hardCindy: return "Hard Cindy"
        }
    }

    /// The canonical 5 pull-ups / 10 push-ups / 15 air squats scheme is shared by
    /// every variant here — what actually distinguishes a variant is the time cap
    /// (Baby Cindy) or the equipment used to perform the same movements (weighted
    /// vest load, box height for scaled push-ups), captured separately by
    /// `VariantEquipment` rather than by changing the movement/rep sequence itself.
    public var movementSequence: [MovementStep] {
        [
            MovementStep(movement: .pullUp, reps: 5),
            MovementStep(movement: .pushUp, reps: 10),
            MovementStep(movement: .airSquat, reps: 15)
        ]
    }

    public var repsPerRound: Int {
        movementSequence.reduce(0) { $0 + $1.reps }
    }

    public var timeCapSeconds: TimeInterval {
        switch self {
        case .babyCindy: return 720
        case .rx, .scaled, .weightedVest, .hardCindy: return 1200
        }
    }
}

/// User-adjustable equipment config for variants where load/height figures are not
/// canonically fixed (weighted vest, box height) — sourced as "configurable, not
/// hard-coded" per research on Hard Cindy / weighted-vest numeric inconsistency.
public struct VariantEquipment: Codable, Sendable {
    public var vestWeightPounds: Double?
    public var boxHeightInches: Double?

    public init(vestWeightPounds: Double? = nil, boxHeightInches: Double? = nil) {
        self.vestWeightPounds = vestWeightPounds
        self.boxHeightInches = boxHeightInches
    }
}
