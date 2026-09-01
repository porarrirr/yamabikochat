import Combine
import SwiftUI
import UIKit

struct ChatTimelineCollectionView: UIViewControllerRepresentable {
    @ObservedObject var store: ChatTimelineStore
    @Binding var isFollowingTail: Bool
    @Binding var unreadCount: Int
    let scrollToLatestRequest: Int
    let regeneratableMessageID: Int64?
    let mathRenderingEnabled: Bool
    let fusionDebugModeEnabled: Bool
    let dualSplitLayout: String
    let dualSplitRatio: Double
    let fusionTraceForMessage: (ChatMessage) -> FusionTrace?
    let onRoute: (ChatWorkspaceRoute) -> Void
    let onPreviousVariant: (Int64) -> Void
    let onNextVariant: (Int64) -> Void
    let onBranch: (Int64) -> Void
    let onRegenerate: () -> Void
    let onAskChatWithSelection: (String) -> Void

    func makeUIViewController(context: Context) -> ChatTimelineViewController {
        let controller = ChatTimelineViewController()
        controller.onFollowStateChanged = { following, unread in
            DispatchQueue.main.async {
                isFollowingTail = following
                unreadCount = unread
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: ChatTimelineViewController, context: Context) {
        controller.configure(
            store: store,
            scrollToLatestRequest: scrollToLatestRequest,
            regeneratableMessageID: regeneratableMessageID,
            mathRenderingEnabled: mathRenderingEnabled,
            fusionDebugModeEnabled: fusionDebugModeEnabled,
            dualSplitLayout: dualSplitLayout,
            dualSplitRatio: dualSplitRatio,
            fusionTraceForMessage: fusionTraceForMessage,
            onRoute: onRoute,
            onPreviousVariant: onPreviousVariant,
            onNextVariant: onNextVariant,
            onBranch: onBranch,
            onRegenerate: onRegenerate,
            onAskChatWithSelection: onAskChatWithSelection
        )
    }
}

final class ChatTimelineViewController: UIViewController, UICollectionViewDelegate {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private weak var store: ChatTimelineStore?
    private var followState: TailFollowState = .followingTail
    private var lastScrollRequest = -1
    private var configuredIDs: [String] = []
    private var unreadCount = 0
    private var lastViewportSize = CGSize.zero
    private var pendingContentAnchor: (id: String, offset: CGFloat)?
    private var pendingViewportOffsetY: CGFloat?
    private var pendingChangedRowIDs: Set<String> = []
    private var pendingReconfiguredRowIDs: Set<String> = []
    private var pendingMeasuredCellHeights: [String: CGFloat] = [:]
    private var pendingContentChangeUserScrollGeneration: Int?
    private var parsedRowsRemeasured: Set<String> = []
    private var pendingLocksViewport = false
    private var viewportCompensationBottom: CGFloat = 0
    private var viewportLockTargetY: CGFloat?
    private var isContentUpdateScheduled = false
    private var isCompletingRowMeasurement = false
    private var isUserScrollInProgress = false
    private var userScrollGeneration = 0
    private var lastUserDrivenOffsetY: CGFloat?
    private var previousRegeneratableMessageID: Int64?
    private var previousMathRenderingEnabled = true
    private var previousFusionDebugModeEnabled = false
    private var previousDualSplitLayout = "VERTICAL"
    private var previousDualSplitRatio = 0.5
    private var isTimelineVisible = true

    var regeneratableMessageID: Int64?
    var mathRenderingEnabled = true
    var fusionDebugModeEnabled = false
    var dualSplitLayout = "VERTICAL"
    var dualSplitRatio = 0.5
    var fusionTraceForMessage: (ChatMessage) -> FusionTrace? = { _ in nil }
    var onRoute: (ChatWorkspaceRoute) -> Void = { _ in }
    var onPreviousVariant: (Int64) -> Void = { _ in }
    var onNextVariant: (Int64) -> Void = { _ in }
    var onBranch: (Int64) -> Void = { _ in }
    var onRegenerate: () -> Void = {}
    var onAskChatWithSelection: (String) -> Void = { _ in }
    var onFollowStateChanged: (Bool, Int) -> Void = { _, _ in }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let layout = ChatTimelineLayout()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.accessibilityIdentifier = "chat-timeline"
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self
        // Streaming rows are measured explicitly in completePendingRowMeasurement().
        // Leaving this enabled makes invalidateIntrinsicContentSize() start a second,
        // UIKit-owned resize before our custom layout commits the measured height.
        collectionView.selfSizingInvalidation = .disabled
        collectionView.register(ChatTimelineCollectionCell.self, forCellWithReuseIdentifier: "message")
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            guard let self,
                  let row = self.store?.row(id: id)
            else { return nil }
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: "message",
                for: indexPath
            ) as? ChatTimelineCollectionCell else { return nil }
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            cell.onMeasuredContentHeightChange = { [weak self] height in
                self?.applyMeasuredCellHeight(height, rowID: id)
            }
            cell.contentConfiguration = UIHostingConfiguration {
                ChatTimelineRowView(
                    store: row,
                    regeneratableMessageID: self.regeneratableMessageID,
                    mathRenderingEnabled: self.mathRenderingEnabled,
                    fusionDebugModeEnabled: self.fusionDebugModeEnabled,
                    dualSplitLayout: self.dualSplitLayout,
                    dualSplitRatio: self.dualSplitRatio,
                    fusionTraceForMessage: self.fusionTraceForMessage,
                    onRoute: self.onRoute,
                    onPreviousVariant: self.onPreviousVariant,
                    onNextVariant: self.onNextVariant,
                    onBranch: self.onBranch,
                    onRegenerate: self.onRegenerate,
                    onAskChatWithSelection: self.onAskChatWithSelection,
                    onIntrinsicHeightChange: { [weak self] height in
                        self?.applyIntrinsicHeight(height, rowID: id)
                    },
                    onContentLayoutChange: { [weak self] in
                        self?.remeasureRow(rowID: id)
                    }
                )
            }
            .margins(.all, 0)
            cell.requestContentHeightMeasurement()
            return cell
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        maintainViewportLockIfNeeded()
        let viewportSize = collectionView.bounds.size
        guard viewportSize != lastViewportSize else { return }
        let widthChanged = abs(viewportSize.width - lastViewportSize.width)
            > TailFollowPolicy.offsetTolerance
        lastViewportSize = viewportSize
        if widthChanged,
           let layout = collectionView.collectionViewLayout as? ChatTimelineLayout {
            let horizontal: CGFloat = viewportSize.width >= 700 ? 28 : 18
            layout.contentInsets = UIEdgeInsets(top: 20, left: horizontal, bottom: 24, right: horizontal)
            layout.resetMeasuredHeights()
            layout.invalidateLayout()
        }
        guard !isUserScrolling, case .followingTail = followState else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.isUserScrolling,
                  case .followingTail = self.followState
            else { return }
            self.collectionView.layoutIfNeeded()
            self.pinToTail()
            self.publishFollowState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isTimelineVisible = true
        // Viewport compensation is only valid for the exact visible streaming
        // frame that created it. A cached conversation can otherwise restore a
        // temporary bottom inset after navigating back to it.
        cancelPendingViewportRestoreForNavigation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isTimelineVisible = false
        cancelPendingViewportRestoreForNavigation()
    }

    func configure(
        store: ChatTimelineStore,
        scrollToLatestRequest: Int,
        regeneratableMessageID: Int64?,
        mathRenderingEnabled: Bool,
        fusionDebugModeEnabled: Bool,
        dualSplitLayout: String,
        dualSplitRatio: Double,
        fusionTraceForMessage: @escaping (ChatMessage) -> FusionTrace?,
        onRoute: @escaping (ChatWorkspaceRoute) -> Void,
        onPreviousVariant: @escaping (Int64) -> Void,
        onNextVariant: @escaping (Int64) -> Void,
        onBranch: @escaping (Int64) -> Void,
        onRegenerate: @escaping () -> Void,
        onAskChatWithSelection: @escaping (String) -> Void
    ) {
        let storeChanged = self.store !== store
        if storeChanged {
            self.store?.onRowContentWillChange = nil
            self.store?.onRowContentDidChange = nil
            followState = .followingTail
            unreadCount = 0
            pendingContentAnchor = nil
            pendingViewportOffsetY = nil
            pendingChangedRowIDs.removeAll()
            pendingReconfiguredRowIDs.removeAll()
            pendingMeasuredCellHeights.removeAll()
            pendingContentChangeUserScrollGeneration = nil
            parsedRowsRemeasured.removeAll()
            pendingLocksViewport = false
            isUserScrollInProgress = false
            lastUserDrivenOffsetY = nil
            clearViewportCompensation()
            store.onRowContentWillChange = { [weak self] rowID, kind in
                self?.prepareForRowContentChange(rowID: rowID, kind: kind)
            }
            store.onRowContentDidChange = { [weak self] rowID, kind in
                self?.finishRowContentChange(rowID: rowID, kind: kind)
            }
            // A newly selected conversation renders from its persisted rows.
            // Presentation-only stream frames belong to the previous attachment
            // of this controller and must not keep their provisional cell height.
            store.clearTransientStreamingSnapshots()
        }
        self.store = store
        let regeneratableMessageChanged = previousRegeneratableMessageID != regeneratableMessageID
        let mathRenderingChanged = previousMathRenderingEnabled != mathRenderingEnabled
        let fusionDebugModeChanged = previousFusionDebugModeEnabled != fusionDebugModeEnabled
        let dualLayoutChanged = previousDualSplitLayout != dualSplitLayout
            || previousDualSplitRatio != dualSplitRatio
        previousRegeneratableMessageID = regeneratableMessageID
        previousMathRenderingEnabled = mathRenderingEnabled
        previousFusionDebugModeEnabled = fusionDebugModeEnabled
        previousDualSplitLayout = dualSplitLayout
        previousDualSplitRatio = dualSplitRatio
        self.regeneratableMessageID = regeneratableMessageID
        self.mathRenderingEnabled = mathRenderingEnabled
        self.fusionDebugModeEnabled = fusionDebugModeEnabled
        self.dualSplitLayout = dualSplitLayout
        self.dualSplitRatio = dualSplitRatio
        self.fusionTraceForMessage = fusionTraceForMessage
        self.onRoute = onRoute
        self.onPreviousVariant = onPreviousVariant
        self.onNextVariant = onNextVariant
        self.onBranch = onBranch
        self.onRegenerate = onRegenerate
        self.onAskChatWithSelection = onAskChatWithSelection

        let scrollToLatest = storeChanged || scrollToLatestRequest != lastScrollRequest
        if scrollToLatest {
            lastScrollRequest = scrollToLatestRequest
            followState = .followingTail
            unreadCount = 0
        }

        let shouldReconfigure = regeneratableMessageChanged
            || mathRenderingChanged
            || fusionDebugModeChanged
            || dualLayoutChanged
        apply(
            ids: store.orderedIDs,
            reconfigureAll: shouldReconfigure,
            completion: scrollToLatest ? { [weak self] in self?.moveToLatestOnce() } : nil
        )
    }

    private func prepareForRowContentChange(rowID: String, kind: ChatTimelineRowChangeKind) {
        pendingChangedRowIDs.insert(rowID)
        guard !isUserScrolling else {
            cancelPendingViewportRestoreForUserScroll()
            return
        }
        if pendingContentAnchor == nil {
            pendingContentAnchor = captureVisibleAnchor()
            pendingViewportOffsetY = collectionView.contentOffset.y
            pendingContentChangeUserScrollGeneration = userScrollGeneration
        }
        switch kind {
        case .streamUpdate:
            if isTimelineVisible, case .detached = followState {
                pendingLocksViewport = true
            }
        case .completion:
            // A stream frame may need temporary bottom inset to hold a detached
            // reader's viewport while the row is remeasured. Completion is the
            // terminal measurement pass, so it must remove that compensation
            // instead of turning it into permanent scrollable whitespace.
            pendingLocksViewport = false
        case .normalUpdate:
            break
        }
    }

    private func finishRowContentChange(rowID: String, kind: ChatTimelineRowChangeKind) {
        pendingChangedRowIDs.insert(rowID)
        pendingReconfiguredRowIDs.insert(rowID)
        guard !isContentUpdateScheduled else { return }
        isContentUpdateScheduled = true
        applyPendingRowReconfigurationsIfNeeded()
    }

    private func finishExistingRowMeasurement(rowID: String) {
        pendingChangedRowIDs.insert(rowID)
        guard !isContentUpdateScheduled else { return }
        isContentUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingRowReconfigurationsIfNeeded()
        }
    }

    private func applyPendingRowReconfigurationsIfNeeded() {
        var snapshot = dataSource.snapshot()
        let availableIDs = Set(snapshot.itemIdentifiers)
        let reconfiguredIDs = pendingReconfiguredRowIDs.filter(availableIDs.contains)
        if !reconfiguredIDs.isEmpty {
            // Rebuild only the changed hosting configuration. The diffable-data
            // source completion runs after the configuration provider has read
            // the latest row snapshot, so manual sizing cannot measure the
            // previous SwiftUI streaming frame.
            snapshot.reconfigureItems(Array(reconfiguredIDs))
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                self?.completePendingRowMeasurement()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.completePendingRowMeasurement()
            }
        }
    }

    private func applyIntrinsicHeight(_ height: CGFloat, rowID: String) {
        guard height.isFinite, height > 0, configuredIDs.contains(rowID) else { return }
        // The SwiftUI preference is a layout-completion signal, not the
        // authoritative collection-cell height. A delayed preference from an
        // older streaming frame can otherwise overwrite a newer full-cell
        // measurement with the inner Markdown height. Measure the hosting cell
        // at consumption time so the layout always commits current content.
        prepareForRowContentChange(rowID: rowID, kind: .normalUpdate)
        finishPresentationMeasurement(rowID: rowID)
    }

    private func applyMeasuredCellHeight(_ height: CGFloat, rowID: String) {
        guard height.isFinite, height > 0, configuredIDs.contains(rowID) else { return }
        pendingMeasuredCellHeights[rowID] = ceil(height)
        prepareForRowContentChange(rowID: rowID, kind: .normalUpdate)
        finishPresentationMeasurement(rowID: rowID)
    }

    private func remeasureRow(rowID: String) {
        guard configuredIDs.contains(rowID) else { return }
        if store?.row(id: rowID)?.streamingSnapshot?.isFinal == false {
            guard parsedRowsRemeasured.insert(rowID).inserted,
                  !isCompletingRowMeasurement
            else { return }
        }
        prepareForRowContentChange(rowID: rowID, kind: .normalUpdate)
        finishPresentationMeasurement(rowID: rowID)
    }

    private func finishPresentationMeasurement(rowID: String) {
        if store?.row(id: rowID)?.streamingSnapshot?.isFinal == false {
            // Streaming frames must keep content replacement and height
            // measurement in the same run-loop turn. Deferring only the height
            // pass makes the rendered token frame and its cell bounds alternate.
            finishRowContentChange(rowID: rowID, kind: .normalUpdate)
        } else {
            // A completed Markdown view already owns its parsed presentation.
            // Measure that existing hosting cell without rebuilding it and
            // restarting the final parse.
            finishExistingRowMeasurement(rowID: rowID)
        }
    }

    private func completePendingRowMeasurement() {
        // Consume one immutable batch. A Mermaid/attachment callback can arrive
        // synchronously while layoutIfNeeded() below is measuring this batch.
        // Clearing the queue up front lets that callback enqueue a second pass;
        // clearing it at the end would silently discard the newer height.
        let changedRowIDs = pendingChangedRowIDs
        let measuredCellHeights = pendingMeasuredCellHeights
        let contentAnchor = pendingContentAnchor
        let viewportOffsetY = pendingViewportOffsetY
        let contentChangeUserScrollGeneration = pendingContentChangeUserScrollGeneration
        let locksViewport = pendingLocksViewport
        let measurementOffsetY = collectionView.contentOffset.y
        pendingContentAnchor = nil
        pendingViewportOffsetY = nil
        pendingChangedRowIDs.removeAll()
        pendingReconfiguredRowIDs.removeAll()
        pendingMeasuredCellHeights.removeAll()
        pendingContentChangeUserScrollGeneration = nil
        pendingLocksViewport = false
        isContentUpdateScheduled = false

        isCompletingRowMeasurement = true
        UIView.performWithoutAnimation {
            let context = ChatTimelineLayoutInvalidationContext()
            let indexPaths = changedRowIDs.compactMap { id -> IndexPath? in
                guard let index = configuredIDs.firstIndex(of: id) else { return nil }
                return IndexPath(item: index, section: 0)
            }
            for indexPath in indexPaths {
                guard let id = dataSource.itemIdentifier(for: indexPath) else { continue }
                if let measuredHeight = measuredCellHeights[id] {
                    context.preferredHeights[indexPath] = measuredHeight
                    continue
                }
                guard let cell = collectionView.cellForItem(at: indexPath),
                      let originalAttributes = collectionView.layoutAttributesForItem(at: indexPath)
                else { continue }
                cell.contentView.invalidateIntrinsicContentSize()
                cell.setNeedsLayout()
                cell.layoutIfNeeded()
                let fittedAttributes = cell.preferredLayoutAttributesFitting(originalAttributes)
                context.preferredHeights[indexPath] = fittedAttributes.size.height
            }
            if !context.preferredHeights.isEmpty {
                context.invalidateItems(at: Array(context.preferredHeights.keys))
                collectionView.collectionViewLayout.invalidateLayout(with: context)
                // Item-only invalidation updates the attributes but UIKit does
                // not ask this custom layout for a new collection content size.
                // Fully invalidate after preserving the measured heights so the
                // scrollable range grows with the streamed cell.
                collectionView.collectionViewLayout.invalidateLayout()
            }
            collectionView.layoutIfNeeded()
            if isUserScrolling || contentChangeUserScrollGeneration != userScrollGeneration {
                cancelPendingViewportRestoreForUserScroll()
                // UIKit may adjust contentOffset as soon as invalidation starts,
                // before this pass reaches layoutIfNeeded(). Preserve the last
                // offset delivered by the scroll delegate, which is the actual
                // finger/deceleration position, rather than that adjusted value.
                let preservedOffsetY = clampedOffset(lastUserDrivenOffsetY ?? measurementOffsetY)
                if TailFollowPolicy.shouldAdjustOffset(
                    current: collectionView.contentOffset.y,
                    target: preservedOffsetY
                ) {
                    collectionView.setContentOffset(
                        CGPoint(x: 0, y: preservedOffsetY),
                        animated: false
                    )
                }
            } else {
                restorePosition(
                    anchor: contentAnchor,
                    clampsToContentBounds: !locksViewport,
                    lockedOffsetY: viewportOffsetY
                )
            }
        }
        isCompletingRowMeasurement = false
    }

    private func apply(
        ids: [String],
        reconfigureAll: Bool,
        completion: (() -> Void)? = nil
    ) {
        let previousIDs = Set(configuredIDs)
        let idsChanged = configuredIDs != ids
        let anchor = captureVisibleAnchor()
        let capturedUserScrollGeneration = userScrollGeneration

        if idsChanged {
            (collectionView.collectionViewLayout as? ChatTimelineLayout)?.remapMeasuredHeights(
                from: configuredIDs,
                to: ids
            )
            configuredIDs = ids
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids)
            if reconfigureAll {
                let retainedIDs = ids.filter(previousIDs.contains)
                if !retainedIDs.isEmpty {
                    snapshot.reconfigureItems(retainedIDs)
                }
            }
            if case .detached = followState {
                unreadCount += ids.lazy.filter { !previousIDs.contains($0) }.count
            }
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                if self.userScrollGeneration == capturedUserScrollGeneration,
                   !self.isUserScrolling {
                    self.restorePosition(anchor: anchor)
                }
                completion?()
            }
        } else if reconfigureAll, !configuredIDs.isEmpty {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(configuredIDs)
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self else { return }
                if self.userScrollGeneration == capturedUserScrollGeneration,
                   !self.isUserScrolling {
                    self.restorePosition(anchor: anchor)
                }
                completion?()
            }
        } else {
            completion?()
        }
    }

    private func captureVisibleAnchor() -> (id: String, offset: CGFloat)? {
        guard let first = collectionView.indexPathsForVisibleItems.sorted().first,
              let id = dataSource.itemIdentifier(for: first),
              let attributes = collectionView.layoutAttributesForItem(at: first)
        else { return nil }
        return (id, attributes.frame.minY - collectionView.contentOffset.y)
    }

    private func restorePosition(
        anchor: (id: String, offset: CGFloat)?,
        clampsToContentBounds: Bool = true,
        lockedOffsetY: CGFloat? = nil
    ) {
        collectionView.layoutIfNeeded()
        switch followState {
        case .followingTail:
            pinToTail()
        case .detached:
            guard let anchor,
                  let index = configuredIDs.firstIndex(of: anchor.id),
                  let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
            else { return }
            let targetY = attributes.frame.minY - anchor.offset
            if !clampsToContentBounds {
                viewportLockTargetY = lockedOffsetY ?? targetY
                maintainViewportLockIfNeeded()
                publishFollowState()
                return
            }
            clearViewportCompensation()
            let restoredY = clampedOffset(targetY)
            if TailFollowPolicy.shouldAdjustOffset(current: collectionView.contentOffset.y, target: restoredY) {
                collectionView.setContentOffset(CGPoint(x: 0, y: restoredY), animated: false)
            }
        }
        publishFollowState()
    }

    private func moveToLatestOnce() {
        guard !isUserScrolling, case .followingTail = followState else {
            publishFollowState()
            return
        }
        clearViewportCompensation()
        UIView.performWithoutAnimation {
            collectionView.layoutIfNeeded()
            pinToTail()
        }
        unreadCount = 0
        publishFollowState()
    }

    private func pinToTail() {
        let inset = collectionView.adjustedContentInset
        let y = max(-inset.top, collectionView.contentSize.height - collectionView.bounds.height + inset.bottom)
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        let inset = collectionView.adjustedContentInset
        let lower = -inset.top
        let upper = max(lower, collectionView.contentSize.height - collectionView.bounds.height + inset.bottom)
        return TailFollowPolicy.restoredOffset(
            anchorMinY: value,
            offsetWithinViewport: 0,
            lowerBound: lower,
            upperBound: upper
        )
    }

    private var isNearTail: Bool {
        let inset = collectionView.adjustedContentInset
        let visibleBottom = collectionView.contentOffset.y + collectionView.bounds.height - inset.bottom
        return TailFollowPolicy.isNearTail(distance: collectionView.contentSize.height - visibleBottom)
    }

    private var isUserScrolling: Bool {
        isUserScrollInProgress
            || collectionView?.isTracking == true
            || collectionView?.isDragging == true
            || collectionView?.isDecelerating == true
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userScrollGeneration &+= 1
        isUserScrollInProgress = true
        lastUserDrivenOffsetY = scrollView.contentOffset.y
        cancelPendingViewportRestoreForUserScroll()
        detachAtVisibleAnchor()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isUserScrolling else { return }
        lastUserDrivenOffsetY = scrollView.contentOffset.y
        if isNearTail {
            followState = .followingTail
            unreadCount = 0
        } else {
            detachAtVisibleAnchor()
        }
        publishFollowState()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        isUserScrollInProgress = false
        settleFollowState()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isUserScrollInProgress = false
        settleFollowState()
    }

    private func settleFollowState() {
        if isNearTail {
            followState = .followingTail
            unreadCount = 0
        } else {
            detachAtVisibleAnchor()
        }
        publishFollowState()
    }

    private func detachAtVisibleAnchor() {
        detach(using: captureVisibleAnchor())
    }

    private func detach(using anchor: (id: String, offset: CGFloat)?) {
        guard let anchor else { return }
        followState = .detached(
            anchorMessageID: numericMessageID(for: anchor.id),
            offset: anchor.offset
        )
    }

    private func numericMessageID(for rowID: String) -> Int64 {
        Int64(rowID.dropFirst(2)) ?? 0
    }

    private func publishFollowState() {
        onFollowStateChanged(isNearTail, unreadCount)
    }

    private func maintainViewportLockIfNeeded() {
        guard !isUserScrolling, let targetY = viewportLockTargetY else { return }
        let inset = collectionView.adjustedContentInset
        let lower = -inset.top
        let naturalUpper = max(
            lower,
            collectionView.contentSize.height - collectionView.bounds.height
                + inset.bottom - viewportCompensationBottom
        )
        let requiredCompensation = max(0, targetY - naturalUpper)
        if abs(requiredCompensation - viewportCompensationBottom) > TailFollowPolicy.offsetTolerance {
            collectionView.contentInset.bottom += requiredCompensation - viewportCompensationBottom
            viewportCompensationBottom = requiredCompensation
        }
        if TailFollowPolicy.shouldAdjustOffset(current: collectionView.contentOffset.y, target: targetY) {
            collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
        }
    }

    private func clearViewportCompensation() {
        viewportLockTargetY = nil
        guard viewportCompensationBottom > 0 else { return }
        collectionView.contentInset.bottom -= viewportCompensationBottom
        viewportCompensationBottom = 0
    }

    private func cancelPendingViewportRestoreForUserScroll() {
        pendingContentAnchor = nil
        pendingViewportOffsetY = nil
        pendingLocksViewport = false
        pendingContentChangeUserScrollGeneration = nil
        clearViewportCompensation()
    }

    private func cancelPendingViewportRestoreForNavigation() {
        pendingContentAnchor = nil
        pendingViewportOffsetY = nil
        pendingChangedRowIDs.removeAll()
        pendingReconfiguredRowIDs.removeAll()
        pendingMeasuredCellHeights.removeAll()
        pendingContentChangeUserScrollGeneration = nil
        pendingLocksViewport = false
        clearViewportCompensation()
        collectionView.layoutIfNeeded()
        let boundedOffsetY = clampedOffset(collectionView.contentOffset.y)
        if TailFollowPolicy.shouldAdjustOffset(
            current: collectionView.contentOffset.y,
            target: boundedOffsetY
        ) {
            collectionView.setContentOffset(CGPoint(x: 0, y: boundedOffsetY), animated: false)
        }
    }
}

private final class ChatTimelineLayoutInvalidationContext: UICollectionViewLayoutInvalidationContext {
    var preferredHeights: [IndexPath: CGFloat] = [:]
}

private final class ChatTimelineLayout: UICollectionViewLayout {
    var contentInsets = UIEdgeInsets(top: 20, left: 18, bottom: 24, right: 18)

    private let estimatedHeight: CGFloat = 120
    private let itemSpacing: CGFloat = 22
    private var measuredHeights: [IndexPath: CGFloat] = [:]
    private var attributesByIndexPath: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var calculatedContentSize = CGSize.zero

    override class var invalidationContextClass: AnyClass {
        ChatTimelineLayoutInvalidationContext.self
    }

    func resetMeasuredHeights() {
        measuredHeights.removeAll()
    }

    func remapMeasuredHeights(from previousIDs: [String], to nextIDs: [String]) {
        guard !measuredHeights.isEmpty else { return }
        var heightsByID: [String: CGFloat] = [:]
        for (indexPath, height) in measuredHeights where previousIDs.indices.contains(indexPath.item) {
            heightsByID[previousIDs[indexPath.item]] = height
        }
        var remapped: [IndexPath: CGFloat] = [:]
        for (index, id) in nextIDs.enumerated() {
            if let height = heightsByID[id] {
                remapped[IndexPath(item: index, section: 0)] = height
            }
        }
        measuredHeights = remapped
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let itemCount = collectionView.numberOfSections > 0
            ? collectionView.numberOfItems(inSection: 0)
            : 0
        let itemWidth = max(
            1,
            collectionView.bounds.width - contentInsets.left - contentInsets.right
        )
        var nextAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
        var y = contentInsets.top
        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let height = measuredHeights[indexPath] ?? estimatedHeight
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = CGRect(x: contentInsets.left, y: y, width: itemWidth, height: height)
            nextAttributes[indexPath] = attributes
            y += height + itemSpacing
        }
        if itemCount > 0 {
            y -= itemSpacing
        }
        y += contentInsets.bottom
        attributesByIndexPath = nextAttributes
        calculatedContentSize = CGSize(width: collectionView.bounds.width, height: max(0, y))
    }

    override var collectionViewContentSize: CGSize {
        calculatedContentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributesByIndexPath.values
            .filter { $0.frame.intersects(rect) }
            .sorted { $0.indexPath < $1.indexPath }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributesByIndexPath[indexPath]
    }

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> Bool {
        abs(preferredAttributes.size.height - originalAttributes.size.height)
            > TailFollowPolicy.offsetTolerance
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(
            forPreferredLayoutAttributes: preferredAttributes,
            withOriginalAttributes: originalAttributes
        ) as! ChatTimelineLayoutInvalidationContext
        context.preferredHeights[preferredAttributes.indexPath] = preferredAttributes.size.height
        return context
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        if let context = context as? ChatTimelineLayoutInvalidationContext {
            measuredHeights.merge(context.preferredHeights) { _, new in new }
        }
        super.invalidateLayout(with: context)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return abs(newBounds.width - collectionView.bounds.width) > TailFollowPolicy.offsetTolerance
    }
}

final class ChatTimelineCollectionCell: UICollectionViewCell {
    var onMeasuredContentHeightChange: ((CGFloat) -> Void)?
    private var lastReportedContentHeight: CGFloat?
    private var lastMeasuredWidth: CGFloat?
    private var needsContentHeightMeasurement = true

    #if DEBUG
    private(set) var contentHeightMeasurementCount = 0
    #endif

    override func prepareForReuse() {
        super.prepareForReuse()
        onMeasuredContentHeightChange = nil
        lastReportedContentHeight = nil
        lastMeasuredWidth = nil
        needsContentHeightMeasurement = true
        #if DEBUG
        contentHeightMeasurementCount = 0
        #endif
    }

    func requestContentHeightMeasurement() {
        needsContentHeightMeasurement = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let widthChanged = lastMeasuredWidth.map {
            abs($0 - bounds.width) > TailFollowPolicy.offsetTolerance
        } ?? true
        // UICollectionView can lay out a visible cell repeatedly while its
        // scroll position changes. Measuring an unchanged hosting tree here is
        // proportional to the complete message length, so a very long answer
        // would block each scroll frame on a synchronous full-cell fitting pass.
        guard needsContentHeightMeasurement || widthChanged else { return }
        needsContentHeightMeasurement = false
        let height = measuredContentHeight(for: bounds.width)
        guard height.isFinite,
              height > 0,
              abs(height - bounds.height) > TailFollowPolicy.offsetTolerance,
              lastReportedContentHeight.map({
                  abs($0 - height) > TailFollowPolicy.offsetTolerance
              }) ?? true
        else { return }
        lastReportedContentHeight = height
        onMeasuredContentHeightChange?(height)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        needsContentHeightMeasurement = false
        let height = measuredContentHeight(for: layoutAttributes.size.width)
        attributes.frame = CGRect(
            x: layoutAttributes.frame.minX,
            y: layoutAttributes.frame.minY,
            width: layoutAttributes.frame.width,
            height: height
        )
        return attributes
    }

    private func measuredContentHeight(for width: CGFloat) -> CGFloat {
        lastMeasuredWidth = width
        #if DEBUG
        contentHeightMeasurementCount += 1
        #endif
        let measuredSize = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return ceil(measuredSize.height)
    }
}

private struct ChatTimelineRowView: View {
    @ObservedObject var store: ChatTimelineRowStore
    let regeneratableMessageID: Int64?
    let mathRenderingEnabled: Bool
    let fusionDebugModeEnabled: Bool
    let dualSplitLayout: String
    let dualSplitRatio: Double
    let fusionTraceForMessage: (ChatMessage) -> FusionTrace?
    let onRoute: (ChatWorkspaceRoute) -> Void
    let onPreviousVariant: (Int64) -> Void
    let onNextVariant: (Int64) -> Void
    let onBranch: (Int64) -> Void
    let onRegenerate: () -> Void
    let onAskChatWithSelection: (String) -> Void
    let onIntrinsicHeightChange: (CGFloat) -> Void
    let onContentLayoutChange: () -> Void

    private var shouldReportIntrinsicHeight: Bool {
        guard case let .message(message) = store.item else { return false }
        let hasAttachments = (
            try? JSONDecoder().decode(
                [String].self,
                from: Data(message.displayAttachmentsJSON.utf8)
            )
        )?.isEmpty == false
        // Attachment previews and parsed multi-block assistant Markdown can
        // expand after their initial estimate. Plain rows stay on the existing
        // fitted-size path so unrelated late hosting layouts cannot perturb an
        // active scroll position.
        let presentedText = store.streamingSnapshot?.text.trimmedNonEmpty
            ?? message.displayText
        return hasAttachments
            || (message.message.role != "user" && presentedText.contains("\n\n"))
    }

    var body: some View {
        ChatTimelineTopPinnedLayout(usesIntrinsicHeight: shouldReportIntrinsicHeight) {
            Group {
                switch store.item {
                case let .message(message):
                    ChatMessageRow(
                        message: message,
                        streamingSnapshot: store.streamingSnapshot,
                        streamingMarkdownBlocks: store.streamingMarkdownBlocks,
                        canRegenerate: regeneratableMessageID == message.id,
                        mathRenderingEnabled: mathRenderingEnabled,
                        fusionDebugModeEnabled: fusionDebugModeEnabled,
                        fusionTrace: fusionTraceForMessage(message.message),
                        onRoute: onRoute,
                        onPreviousVariant: onPreviousVariant,
                        onNextVariant: onNextVariant,
                        onBranch: onBranch,
                        onRegenerate: onRegenerate,
                        onMarkdownLayoutChange: shouldReportIntrinsicHeight
                            ? onContentLayoutChange
                            : {}
                    )
                case let .dual(message):
                    DualChatMessageRow(
                        message: message,
                        mathRenderingEnabled: mathRenderingEnabled,
                        splitLayout: dualSplitLayout,
                        splitRatio: dualSplitRatio,
                        onRoute: onRoute
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChatTimelineIntrinsicHeightPreference.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.onAskChatWithSelection, onAskChatWithSelection)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onPreferenceChange(ChatTimelineIntrinsicHeightPreference.self) { height in
            guard shouldReportIntrinsicHeight else { return }
            onIntrinsicHeightChange(height)
        }
    }
}

private struct ChatTimelineIntrinsicHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatTimelineTopPinnedLayout: Layout {
    let usesIntrinsicHeight: Bool

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let contentSize = subview.sizeThatFits(.init(width: proposal.width, height: nil))
        let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(
            width: proposal.width ?? contentSize.width,
            height: usesIntrinsicHeight ? contentSize.height : (proposedHeight ?? contentSize.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: .init(width: bounds.width, height: nil)
        )
    }
}

private struct ChatMessageRow: View {
    let message: FullChatMessage
    let streamingSnapshot: ChatStreamingSnapshot?
    let streamingMarkdownBlocks: [NativeMarkdownBlock]?
    let canRegenerate: Bool
    let mathRenderingEnabled: Bool
    let fusionDebugModeEnabled: Bool
    let fusionTrace: FusionTrace?
    let onRoute: (ChatWorkspaceRoute) -> Void
    let onPreviousVariant: (Int64) -> Void
    let onNextVariant: (Int64) -> Void
    let onBranch: (Int64) -> Void
    let onRegenerate: () -> Void
    let onMarkdownLayoutChange: () -> Void

    private var isUser: Bool { message.message.role == "user" }
    private var isStreaming: Bool { streamingSnapshot?.isFinal == false }
    private var responseText: String {
        if let text = streamingSnapshot?.text, !text.isEmpty { return text }
        return message.displayText
    }
    private var thinkingText: String? {
        let value = streamingSnapshot?.thinking.trimmedNonEmpty ?? message.displayThinkingStream?.trimmedNonEmpty
        return value
    }
    private var toolSteps: [ToolActivityStep] {
        streamingSnapshot?.toolActivity?.steps ?? message.displayToolActivity?.steps ?? []
    }
    private var rotationNotices: [ProviderRotationNotice] {
        streamingSnapshot?.toolActivity?.rotationNotices
            ?? message.displayToolActivity?.rotationNotices
            ?? []
    }
    private var artifacts: [ChatArtifactPresentationItem] {
        ChatArtifactPresentation.items(from: responseText, isStreaming: isStreaming)
    }
    private var responseSegments: [ChatResponseContentSegment] {
        ChatResponseContentPresentation.segments(from: responseText, artifacts: artifacts)
    }

    var body: some View {
        Group {
            if isUser {
                HStack(alignment: .top) {
                    Spacer(minLength: 48)
                    VStack(alignment: .trailing, spacing: 8) {
                        if !attachmentItems.isEmpty {
                            MessageAttachmentList(attachments: attachmentItems, isOutgoing: true)
                        }
                        if !responseText.isEmpty {
                            Text(responseText)
                                .font(.body)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 11)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                    .frame(maxWidth: 520, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rotationNotices) { notice in
                        ProviderRotationNoticeView(notice: notice)
                    }
                    if !toolSteps.isEmpty {
                        ChatRunSummaryButton(steps: toolSteps) {
                            onRoute(.runInspector(messageID: message.id, steps: toolSteps))
                        }
                    }
                    if let thinkingText {
                        Button {
                            onRoute(.thinkingInspector(messageID: message.id, text: thinkingText))
                        } label: {
                            Label(isStreaming ? L10n.text("思考中") : L10n.text("Thinking"), systemImage: "brain.head.profile")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                    }

                    if !attachmentItems.isEmpty {
                        MessageAttachmentList(attachments: attachmentItems, isOutgoing: false)
                    }

                    if UserFacingErrorFormatter.looksLikeChatError(responseText) {
                        Text(responseText)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    } else if artifacts.isEmpty, !responseText.isEmpty {
                        NativeMarkdownView(
                            markdownText: responseText,
                            isStreaming: isStreaming,
                            mathRenderingEnabled: mathRenderingEnabled,
                            preparsedBlocks: streamingMarkdownBlocks,
                            onFinalParse: onMarkdownLayoutChange,
                            onOpenMermaid: { blockID, source in
                                onRoute(.mermaidViewer(
                                    id: "\(message.id)-\(blockID)",
                                    source: source
                                ))
                            }
                        )
                    } else {
                        ForEach(responseSegments) { segment in
                            switch segment {
                            case let .markdown(segmentID, markdown):
                                NativeMarkdownView(
                                    markdownText: markdown,
                                    isStreaming: isStreaming,
                                    mathRenderingEnabled: mathRenderingEnabled,
                                    preparsedBlocks: nil,
                                    onFinalParse: onMarkdownLayoutChange,
                                    onOpenMermaid: { blockID, source in
                                        onRoute(.mermaidViewer(
                                            id: "\(message.id)-\(segmentID)-\(blockID)",
                                            source: source
                                        ))
                                    }
                                )
                            case let .artifact(artifact):
                                artifactView(artifact)
                            }
                        }
                    }

                    if let fusionTrace, !isStreaming {
                        FusionMessageSummary(trace: fusionTrace) {
                            showFusionDetails(fusionTrace)
                        }
                    }

                    if !isStreaming {
                        ChatMessageActions(
                            message: message,
                            copyText: responseText,
                            canRegenerate: canRegenerate,
                            onPreviousVariant: onPreviousVariant,
                            onNextVariant: onNextVariant,
                            onBranch: onBranch,
                            onRegenerate: onRegenerate
                        )
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
        // A message-wide context menu intercepts the long press before SwiftUI's
        // selectable Text can resolve the character under the user's finger.
        // Message commands remain available in ChatMessageActions below the body.
    }

    @ViewBuilder
    private func artifactView(_ artifact: ChatArtifactPresentationItem) -> some View {
        switch artifact.block {
        case let .svg(source):
            SvgDiagramView(
                source: source,
                onExpand: {
                    onRoute(.artifactViewer(id: artifact.id, block: artifact.block))
                },
                onLayoutChange: onMarkdownLayoutChange
            )
        case .html:
            Button {
                onRoute(.artifactViewer(id: artifact.id, block: artifact.block))
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: artifact.block.systemImage)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.block.title)
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.text("専用ビューアで開く"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(13)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func showFusionDetails(_ trace: FusionTrace) {
        onRoute(.fusionInspector(
            messageID: message.id,
            trace: trace,
            debugModeEnabled: fusionDebugModeEnabled
        ))
    }

    private var attachmentPaths: [String] {
        guard let data = message.displayAttachmentsJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return values
    }

    private var attachmentItems: [ChatAttachmentItem] {
        attachmentPaths.map(ChatAttachmentItem.init(rawValue:))
    }
}

private struct ProviderRotationNoticeView: View {
    let notice: ProviderRotationNotice

    private var title: String {
        if notice.changedModel && notice.changedKey {
            return L10n.text("GeminiのモデルとAPIキーを切り替えました")
        }
        if notice.changedModel {
            return L10n.text("Geminiのモデルを切り替えました")
        }
        return L10n.text("GeminiのAPIキーを切り替えました")
    }

    private var detail: String {
        var parts: [String] = []
        if notice.changedModel {
            parts.append("\(notice.fromModel) → \(notice.toModel)")
        }
        if notice.changedKey {
            parts.append("\(keyLabel(notice.fromKeyID)) → \(keyLabel(notice.toKeyID))")
        }
        parts.append(
            notice.reason == .authenticationFailed
                ? L10n.text("認証エラーのため")
                : L10n.text("利用制限のため")
        )
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)。\(detail)")
    }

    private func keyLabel(_ keyID: String) -> String {
        if keyID == "default" {
            return L10n.text("メインAPIキー")
        }
        let name = keyID.hasPrefix("slot:") ? String(keyID.dropFirst("slot:".count)) : keyID
        return L10n.format("APIキー「%@」", name)
    }
}

private struct ChatRunSummaryButton: View {
    let steps: [ToolActivityStep]
    let action: () -> Void

    private var isRunning: Bool { steps.contains { $0.status == .running } }
    private var hasFailure: Bool { steps.contains { $0.status == .failed } }
    private var webCount: Int { steps.filter(\.isWebActivity).count }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: hasFailure ? "exclamationmark.circle" : (webCount > 0 ? "globe" : "terminal"))
                }
                Text(isRunning ? L10n.text("ツールを実行中") : L10n.format("%d 件のツール実行", steps.count))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(hasFailure ? Color.red : Color.secondary)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

private struct ChatMessageActions: View {
    let message: FullChatMessage
    let copyText: String
    let canRegenerate: Bool
    let onPreviousVariant: (Int64) -> Void
    let onNextVariant: (Int64) -> Void
    let onBranch: (Int64) -> Void
    let onRegenerate: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            actionButton("doc.on.doc", label: L10n.text("コピー")) {
                UIPasteboard.general.string = copyText
            }
            actionButton("arrow.branch", label: L10n.text("分岐")) { onBranch(message.id) }
            if canRegenerate {
                actionButton("arrow.clockwise", label: L10n.text("再生成"), action: onRegenerate)
            }
            if message.variantCount > 1 {
                Spacer(minLength: 6)
                Button { onPreviousVariant(message.id) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                    .disabled(!message.canSelectPreviousVariant)
                Text("\(message.selectedVariantOrdinal)/\(message.variantCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { onNextVariant(message.id) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .disabled(!message.canSelectNextVariant)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

private struct DualChatMessageRow: View {
    let message: DualChatMessage
    let mathRenderingEnabled: Bool
    let splitLayout: String
    let splitRatio: Double
    let onRoute: (ChatWorkspaceRoute) -> Void

    var body: some View {
        switch message.parsedRole {
        case .user:
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 8) {
                    if !userAttachmentItems.isEmpty {
                        MessageAttachmentList(
                            attachments: userAttachmentItems,
                            isOutgoing: true
                        )
                    }
                    if !message.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message.userText)
                            .textSelection(.enabled)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .frame(maxWidth: 520, alignment: .trailing)
            }
        case .dualModel:
            responseColumns
        case .legacy:
            VStack(alignment: .leading, spacing: 12) {
                if !userAttachmentItems.isEmpty {
                    MessageAttachmentList(attachments: userAttachmentItems, isOutgoing: false)
                }
                if let userText = message.userText.trimmedNonEmpty {
                    Text(userText)
                        .font(.body)
                        .textSelection(.enabled)
                }
                Divider()
                responseColumns
            }
        }
    }

    private var resolvedSplitLayout: String {
        splitLayout.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "HORIZONTAL"
            ? "HORIZONTAL"
            : "VERTICAL"
    }

    private var resolvedSplitRatio: Double {
        guard splitRatio.isFinite else { return 0.5 }
        return min(max(splitRatio, 0.1), 0.9)
    }

    private var responseColumns: some View {
        DualSplitContainer(layout: resolvedSplitLayout, splitRatio: resolvedSplitRatio) {
            responseColumn(side: .a)
        } second: {
            responseColumn(side: .b)
        }
    }

    private var userAttachmentItems: [ChatAttachmentItem] {
        message.attachments.map(ChatAttachmentItem.init(rawValue:))
    }

    private func responseColumn(side: DualResponseSide) -> some View {
        let presentation = DualResponsePresentation(message: message, side: side)
        let title: String
        switch side {
        case .a:
            title = "A · \(ProviderCatalog.displayName(for: message.providerA)) · \(message.modelAName)"
        case .b:
            title = "B · \(ProviderCatalog.displayName(for: message.providerB)) · \(message.modelBName)"
        }
        return DualResponseColumn(
            title: title,
            presentation: presentation,
            messageID: message.id ?? message.createdAtMs,
            mathRenderingEnabled: mathRenderingEnabled,
            onRoute: onRoute
        )
    }
}

private struct DualSplitContainer<First: View, Second: View>: View {
    let layout: String
    let splitRatio: Double
    let first: () -> First
    let second: () -> Second

    init(
        layout: String,
        splitRatio: Double,
        @ViewBuilder first: @escaping () -> First,
        @ViewBuilder second: @escaping () -> Second
    ) {
        self.layout = layout
        self.splitRatio = splitRatio
        self.first = first
        self.second = second
    }

    var body: some View {
        if layout == "HORIZONTAL" {
            VStack(alignment: .leading, spacing: 12) {
                first()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                second()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            DualRatioLayout(ratio: splitRatio, spacing: 12) {
                first()
                second()
            }
        }
    }
}

private struct DualRatioLayout: Layout {
    let ratio: Double
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let intrinsicWidth = subviews.reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(.unspecified).width
        } + spacing
        let width = max(proposal.width ?? intrinsicWidth, 0)
        let paneWidths = resolvedPaneWidths(totalWidth: width)
        let firstSize = subviews[0].sizeThatFits(.init(width: paneWidths.0, height: proposal.height))
        let secondSize = subviews[1].sizeThatFits(.init(width: paneWidths.1, height: proposal.height))
        return CGSize(width: width, height: max(firstSize.height, secondSize.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        let paneWidths = resolvedPaneWidths(totalWidth: bounds.width)
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: .init(width: paneWidths.0, height: proposal.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + paneWidths.0 + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: .init(width: paneWidths.1, height: proposal.height)
        )
    }

    private func resolvedPaneWidths(totalWidth: CGFloat) -> (CGFloat, CGFloat) {
        DualSplitLayoutMetrics.paneWidths(
            totalWidth: totalWidth,
            spacing: spacing,
            ratio: ratio
        )
    }
}

enum DualSplitLayoutMetrics {
    static func paneWidths(
        totalWidth: CGFloat,
        spacing: CGFloat,
        ratio: Double
    ) -> (first: CGFloat, second: CGFloat) {
        let available = max(0, totalWidth - spacing)
        let clampedRatio = min(max(CGFloat(ratio), 0.1), 0.9)
        return (available * clampedRatio, available * (1 - clampedRatio))
    }
}

private struct DualResponseColumn: View {
    let title: String
    let presentation: DualResponsePresentation
    let messageID: Int64
    let mathRenderingEnabled: Bool
    let onRoute: (ChatWorkspaceRoute) -> Void

    private var thinkingText: String? {
        presentation.thinking?.trimmedNonEmpty
    }

    private var attachmentItems: [ChatAttachmentItem] {
        presentation.attachmentPaths.map(ChatAttachmentItem.init(rawValue:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !presentation.toolSteps.isEmpty {
                ChatRunSummaryButton(steps: presentation.toolSteps) {
                    onRoute(.runInspector(messageID: messageID, steps: presentation.toolSteps))
                }
            }
            if let thinkingText {
                Button {
                    onRoute(.thinkingInspector(messageID: messageID, text: thinkingText))
                } label: {
                    Label(L10n.text("Thinking"), systemImage: "brain.head.profile")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            if !attachmentItems.isEmpty {
                MessageAttachmentList(attachments: attachmentItems, isOutgoing: false)
            }
            responseContent
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var responseContent: some View {
        switch presentation.status {
        case .pending:
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.text("応答待ち"))
                    .foregroundStyle(.secondary)
            }
        case .failed:
            ChatErrorCard(text: presentation.error?.trimmedNonEmpty ?? L10n.text("応答の生成に失敗しました。"))
        case .canceled:
            Text(L10n.text("キャンセルしました"))
                .foregroundStyle(.secondary)
        case .completed:
            if UserFacingErrorFormatter.looksLikeChatError(presentation.text) {
                ChatErrorCard(text: presentation.text)
            } else {
                NativeMarkdownView(
                    markdownText: presentation.text.trimmedNonEmpty ?? L10n.text("応答がありません"),
                    mathRenderingEnabled: mathRenderingEnabled,
                    onOpenMermaid: { blockID, source in
                        onRoute(.mermaidViewer(
                            id: "\(messageID)-\(title)-\(blockID)",
                            source: source
                        ))
                    }
                )
            }
        }
    }
}
