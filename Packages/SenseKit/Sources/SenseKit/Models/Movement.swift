import Foundation

/// The three movements performed in Cindy, always logged in this fixed order.
public enum Movement: String, Codable, CaseIterable, Sendable {
    case pullUp
    case pushUp
    case airSquat

    public var displayName: String {
        switch self {
        case .pullUp: return "Pull-Up"
        case .pushUp: return "Push-Up"
        case .airSquat: return "Air Squat"
        }
    }
}

/// One movement's rep target within a round, in scoring order.
public struct MovementStep: Sendable, Hashable, Codable {
    public let movement: Movement
    public let reps: Int

    public init(movement: Movement, reps: Int) {
        self.movement = movement
        self.reps = reps
    }
}
