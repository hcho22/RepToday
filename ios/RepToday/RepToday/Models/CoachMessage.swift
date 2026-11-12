import Foundation

/// One message in the Coach conversation (M4, US-CA03), as the account keeps it (`convex/coach.ts`).
///
/// The conversation lives with the user's account, not on the device: the Coach tab loads it from
/// `coach:history` and every turn returns the stored user message and the Coach's reply. A Coach reply
/// may carry **proposals** - actions the model suggested through its tools, which only the user can
/// apply.
struct CoachMessage: Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case coach
    }

    let id: String
    let role: Role
    let text: String
    let createdAt: Date
    var proposals: [CoachProposal]
}

/// An action the Coach proposed (M4, US-CA03/US-CA04, decision 26/27). It is a suggestion, never a
/// change: the Coach tab shows it as a card, and only the user's tap applies it - through the same
/// on-device paths the user's own controls take (`CoachProposalApplier`) - with Undo afterwards.
///
/// The set of actions is closed and mirrors the server's tools (`convex/coachTools.ts`). There is
/// deliberately no case for a de-load, a Return, the cold start, the progression pace, the earned
/// phase or an injury flag: those stay owned by the engine and by the user (ADR-0005), so they cannot
/// be expressed here, let alone applied.
struct CoachProposal: Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        /// Waiting for the user's answer.
        case proposed
        /// The user applied it.
        case applied
        /// The user applied it, then undid it.
        case undone
        /// The user said no.
        case declined
    }

    enum Day: String, Codable, Sendable {
        case today
        case yesterday
    }

    enum RestChoice: String, Codable, Sendable {
        /// Rest today instead of training.
        case restToday
        /// Train today even though it is a Rest Day.
        case trainAnyway
    }

    enum Action: Equatable, Sendable {
        case outsideActivity(type: OutsideActivityType, minutes: Int, distanceMeters: Double?, day: Day)
        case restChoice(RestChoice)
        case todayLength(minutes: Int)
        case swapMovement(exerciseId: String, exerciseName: String)
        case focusAreas([FocusArea])
        /// A repeating reminder: local hour and minute, on `Calendar` weekdays (1 = Sunday).
        case reminder(hour: Int, minute: Int, weekdays: [Int])
        case customWorkout(CustomWorkoutDraft)
    }

    let id: String
    var status: Status
    let action: Action
}

/// A Custom Workout as the Coach wrote it, before the user has reviewed it (M4, US-CA04).
struct CustomWorkoutDraft: Codable, Equatable, Sendable {
    var title: String
    var note: String
    var steps: [Step]

    struct Step: Codable, Equatable, Sendable {
        var name: String
        /// A served catalog movement's id, so the step shows its Trainer art; `nil` for any other
        /// movement, which the app shows as text only.
        var exerciseId: String?
        var sets: Int
        var reps: Int?
        var seconds: Int?
        var perSide: Bool
        var restSeconds: Int
    }
}

/// Today's plan as the phone computed it, sent with each Coach turn so the Coach can talk about - and
/// propose swaps from - the session on the user's screen. Only the engine on the phone can compute it.
struct CoachTodaySnapshot: Encodable, Equatable, Sendable {
    enum Kind: String, Encodable, Sendable {
        case train
        case rest
    }

    struct Movement: Encodable, Equatable, Sendable {
        let id: String
        let name: String
    }

    /// The user's local date, `yyyy-MM-dd`.
    let localDate: String
    /// The user's offset from UTC, so the server writes past sessions' dates in the user's own days.
    let utcOffsetMinutes: Int
    let kind: Kind
    /// The Training Day today trains, or (on a Rest Day) the next one.
    let trainingDay: TrainingDay?
    let minutes: Int
    let movements: [Movement]
}

// MARK: - Wire decoding

extension CoachMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, role, text, createdAt, proposals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = Date(syncMilliseconds: try container.decode(Double.self, forKey: .createdAt))
        // A proposal kind a later server adds is skipped rather than failing the whole message.
        proposals = (try container.decodeIfPresent([LossyProposal].self, forKey: .proposals) ?? []).compactMap(\.proposal)
    }
}

/// Decodes one proposal, or nothing for a kind this build does not know.
private struct LossyProposal: Decodable {
    let proposal: CoachProposal?

    private enum CodingKeys: String, CodingKey {
        case id, kind, status
        case activityType, minutes, distanceMeters, day
        case choice
        case exerciseId, exerciseName
        case areas
        case hour, minute, weekdays
        case workout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try? container.decode(String.self, forKey: .id),
              let kind = try? container.decode(String.self, forKey: .kind),
              let status = try? container.decode(CoachProposal.Status.self, forKey: .status) else {
            proposal = nil
            return
        }
        let action: CoachProposal.Action?
        switch kind {
        case "outsideActivity":
            if let type = try? container.decode(OutsideActivityType.self, forKey: .activityType),
               let minutes = try? container.decode(Int.self, forKey: .minutes),
               let day = try? container.decode(CoachProposal.Day.self, forKey: .day) {
                action = .outsideActivity(
                    type: type,
                    minutes: minutes,
                    distanceMeters: try? container.decodeIfPresent(Double.self, forKey: .distanceMeters),
                    day: day
                )
            } else {
                action = nil
            }
        case "restChoice":
            action = (try? container.decode(CoachProposal.RestChoice.self, forKey: .choice)).map { .restChoice($0) }
        case "todayLength":
            action = (try? container.decode(Int.self, forKey: .minutes)).map { .todayLength(minutes: $0) }
        case "swapMovement":
            if let exerciseId = try? container.decode(String.self, forKey: .exerciseId),
               let name = try? container.decode(String.self, forKey: .exerciseName) {
                action = .swapMovement(exerciseId: exerciseId, exerciseName: name)
            } else {
                action = nil
            }
        case "focusAreas":
            action = (try? container.decode([String].self, forKey: .areas))
                .map { .focusAreas($0.compactMap(FocusArea.init(rawValue:)).canonicallyOrdered) }
        case "reminder":
            if let hour = try? container.decode(Int.self, forKey: .hour),
               let minute = try? container.decode(Int.self, forKey: .minute),
               let weekdays = try? container.decode([Int].self, forKey: .weekdays) {
                action = .reminder(hour: hour, minute: minute, weekdays: weekdays)
            } else {
                action = nil
            }
        case "customWorkout":
            action = (try? container.decode(CustomWorkoutDraft.self, forKey: .workout)).map { .customWorkout($0) }
        default:
            action = nil
        }
        proposal = action.map { CoachProposal(id: id, status: status, action: $0) }
    }
}
