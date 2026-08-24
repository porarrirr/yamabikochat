import Foundation

/// Keeps layout-only changes (for example disclosure expansion) from hijacking
/// the user's scroll position. Content producers explicitly ask this policy
/// whether the timeline should remain pinned to the bottom.
enum ChatScrollPolicy {
    /// Timeline height is independent of the current scroll offset. This must
    /// not use the bottom anchor's viewport coordinate: scrolling changes that
    /// coordinate and would feed the resulting preference update back into
    /// another programmatic scroll.
    static func shouldFollowTimelineLayoutChange(
        isAutoFollowing: Bool,
        isUserInteracting: Bool,
        previousHeight: CGFloat,
        currentHeight: CGFloat
    ) -> Bool {
        guard isAutoFollowing,
              !isUserInteracting,
              previousHeight > 0,
              previousHeight.isFinite,
              currentHeight.isFinite
        else { return false }
        return abs(currentHeight - previousHeight) > 1
    }
}
