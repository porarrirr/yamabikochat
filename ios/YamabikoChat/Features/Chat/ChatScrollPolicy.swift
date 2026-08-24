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

    /// Streaming text changes its rendered height asynchronously. Follow the
    /// measured layout change instead of the earlier token notification so the
    /// scroll target always reflects the web view's current size.
    static func shouldFollowStreamingLayoutGrowth(
        wasNearBottom: Bool,
        isUserInteracting: Bool,
        isStreaming: Bool,
        previousBottomMaxY: CGFloat,
        currentBottomMaxY: CGFloat
    ) -> Bool {
        wasNearBottom &&
            !isUserInteracting &&
            isStreaming &&
            previousBottomMaxY.isFinite &&
            currentBottomMaxY > previousBottomMaxY + 1
    }
}
