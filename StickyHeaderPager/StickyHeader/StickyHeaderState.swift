import CoreGraphics

/// タブごとのスクロール関連状態
struct TabScrollState {
    var previousScrollOffset: CGFloat = 0
    var scrollToTarget: CGFloat?
    var headerOffset: CGFloat = 0
    /// ページが進める縦位置の上限（`previousScrollOffset` と同じ原点）。ページから届くまでは nil。
    var maxScrollOffset: CGFloat?
}

/// スクロール連動ヘッダーの状態と遷移ロジックを一元管理する。
///
/// View から状態遷移の判定ロジックを分離し、ユニットテストで検証可能にするための型。
/// `StickyHeaderModel` が保持し、スクロールとタブ切替の報告ごとに mutating メソッドを呼び出す。
struct StickyHeaderState {
    /// タブごとの状態（縦位置・離脱時のヘッダーが隠れている量など）
    var tabStates: [String: TabScrollState] = [:]
    /// 共有ヘッダーオフセット: 0=完全展開, headerHeight=完全折りたたみ
    var headerOffset: CGFloat = 0
    /// 現在選択中のタブID
    var selectedTabID: String?

    // MARK: - Scroll Offset Change

    /// スクロールオフセット変化を処理し、デルタ追従でヘッダーオフセットを更新する。
    ///
    /// - Parameters:
    ///   - tabID: スクロールイベントの発生元タブID
    ///   - newOffset: 新しいスクロールオフセット
    ///   - headerHeight: ヘッダーの全高（View のレイアウト計測値）
    ///   - isScrolling: ユーザー操作か `scrollTo` のアニメーションでページが動いている最中か。false の報告
    ///     （レイアウト確定・位置合わせの着地）は縦位置を控えるだけで、ヘッダーが隠れている量を動かさない。
    mutating func handleScrollOffsetChange(
        tabID: String,
        newOffset: CGFloat,
        headerHeight: CGFloat,
        isScrolling: Bool,
    ) {
        let previousOffset = tabStates[tabID]?.previousScrollOffset ?? 0
        // 選択前のページの報告（横スワイプ中の位置合わせの着地など）でも前回の位置だけは実際の位置に揃える。
        // 揃えないと、合わせる位置に届かなかったときに選択後の最初のスクロールで合わせる位置との差が一度に入る
        tabStates[tabID, default: TabScrollState()].previousScrollOffset = newOffset
        guard tabID == selectedTabID, isScrolling else { return }

        if let newHeaderOffset = HeaderOffsetCalculator.calculateHeaderOffset(
            previousOffset: previousOffset,
            newOffset: newOffset,
            currentHeaderOffset: headerOffset,
            headerHeight: headerHeight,
        ) {
            headerOffset = newHeaderOffset
        }
    }

    // MARK: - Tab Switch

    /// タブ切替時のスクロール位置補正を適用する。
    ///
    /// 離脱タブの headerOffset を保存し、遷移先タブとの差分に基づいて
    /// スクロール位置を補正する。計算ロジックは HeaderOffsetCalculator に委譲。
    mutating func adjustForTabSwitch(to newID: String) {
        // 離脱タブの現在の headerOffset を保存（復帰時のデルタ補正に使用）
        if let currentTab = selectedTabID {
            tabStates[currentTab, default: TabScrollState()].headerOffset = headerOffset
        }

        let destState = tabStates[newID, default: TabScrollState()]
        // 下の補正と `StickyHeaderModel.consumeAlignTarget` は optional chaining で書き込むので、未登録のタブも先に登録しておく。
        tabStates[newID] = destState

        if let adjustment = HeaderOffsetCalculator.calculateTabSwitchAdjustment(
            destinationScrollOffset: destState.previousScrollOffset,
            destinationSavedHeaderOffset: destState.headerOffset > 0
                ? destState.headerOffset
                : headerOffset,
            currentHeaderOffset: headerOffset,
        ) {
            tabStates[newID]?.previousScrollOffset = adjustment.scrollOffset
            tabStates[newID]?.scrollToTarget = adjustment.scrollToTarget
        }
    }
}
