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
    static func shouldFollowStreamingLayoutChange(
        wasNearBottom: Bool,
        isUserInteracting: Bool,
        isStreaming: Bool,
        isFinalizingStreamLayout: Bool,
        previousBottomMaxY: CGFloat,
        currentBottomMaxY: CGFloat
    ) -> Bool {
        guard wasNearBottom,
              !isUserInteracting,
              previousBottomMaxY.isFinite
        else { return false }

        let delta = currentBottomMaxY - previousBottomMaxY
        if isStreaming {
            return delta > 1
        }

        // Final Markdown typesetting and the stats row are committed after
        // `isSending` becomes false. Their height can grow or shrink, so keep
        // the formerly pinned viewport attached through that final change.
        return isFinalizingStreamLayout && abs(delta) > 1
    }
}
