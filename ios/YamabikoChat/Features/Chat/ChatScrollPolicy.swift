import Foundation

/// Keeps layout-only changes (for example disclosure expansion) from hijacking
/// the user's scroll position. Content producers explicitly ask this policy
/// whether the timeline should remain pinned to the bottom.
enum ChatScrollPolicy {
    static func shouldFollowContentGrowth(
        isNearBottom: Bool,
        isUserInteracting: Bool
    ) -> Bool {
        isNearBottom && !isUserInteracting
    }
}
