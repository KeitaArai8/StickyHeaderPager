import CoreGraphics

/// ヘッダーのデルタ追従オフセットを計算する純粋関数群
///
/// スクロール連動ヘッダーの折りたたみロジックを View から分離し、
/// テスト可能にするためのユーティリティ。
///
/// ## 動作原理
/// - スクロール下方向（delta > 0）: ヘッダーを折りたたむ（headerOffset を増加）
/// - スクロール上方向（delta < 0）: ヘッダーを展開（headerOffset を減少）
/// - headerOffset の範囲: 0（完全展開）〜 headerHeight（完全折りたたみ）
enum HeaderOffsetCalculator {
    /// デルタ追従に基づくヘッダーオフセットを計算する
    ///
    /// - Parameters:
    ///   - previousOffset: 前回のスクロールオフセット
    ///   - newOffset: 新しいスクロールオフセット
    ///   - currentHeaderOffset: 現在のヘッダーオフセット
    ///   - headerHeight: ヘッダーの全高
    /// - Returns: 新しいヘッダーオフセット。変更がない場合は nil
    static func calculateHeaderOffset(
        previousOffset: CGFloat,
        newOffset: CGFloat,
        currentHeaderOffset: CGFloat,
        headerHeight: CGFloat,
    ) -> CGFloat? {
        let delta = newOffset - previousOffset
        guard abs(delta) > 0.1 else { return nil }

        let newHeaderOffset: CGFloat

        if delta > 0 {
            // スクロール下方向: ヘッダーを折りたたむ
            if newOffset < headerHeight {
                // バウンス戻り相では newOffset が一瞬負値へ振れる（先頭を追い越した後のラバーバンド）。
                // 0 未満を素通しすると headerOffset も一瞬負値になり、ヘッダーが隠れている量を符号反転して
                // 位置に使う描画側（ヘッダー等）が 1 フレームだけ逆方向へ跳ねる。
                newHeaderOffset = max(0, newOffset)
            } else {
                newHeaderOffset = min(currentHeaderOffset + delta, headerHeight)
            }
        } else {
            // スクロール上方向: ヘッダーを展開
            if newOffset < currentHeaderOffset {
                newHeaderOffset = max(0, newOffset)
            } else {
                return nil
            }
        }

        guard abs(newHeaderOffset - currentHeaderOffset) > 0.001 else { return nil }
        return newHeaderOffset
    }

    // MARK: - Tab Switch

    /// タブ切替時のスクロール位置補正を計算する
    ///
    /// 遷移先タブが最後に表示されていた時の headerOffset と現在の headerOffset の差分から
    /// スクロール位置を補正し、上端に見えているコンテンツの位置を維持する。
    ///
    /// - Parameters:
    ///   - destinationScrollOffset: 遷移先タブの保存済みスクロール位置
    ///   - destinationSavedHeaderOffset: 遷移先タブが離脱時に保存した headerOffset
    ///   - currentHeaderOffset: 現在の共有 headerOffset
    /// - Returns: 補正後のスクロール位置。補正不要の場合は nil
    static func calculateTabSwitchAdjustment(
        destinationScrollOffset: CGFloat,
        destinationSavedHeaderOffset: CGFloat,
        currentHeaderOffset: CGFloat,
    ) -> TabSwitchAdjustment? {
        let headerDelta = destinationSavedHeaderOffset - currentHeaderOffset
        let adjustedScroll = max(0, destinationScrollOffset - headerDelta)

        if adjustedScroll < currentHeaderOffset {
            // スクロール位置がヘッダーより上の場合、ヘッダー境界まで引き上げる
            return TabSwitchAdjustment(
                scrollOffset: currentHeaderOffset,
                scrollToTarget: currentHeaderOffset,
            )
        } else if abs(headerDelta) > 0.1 {
            // headerOffset の差分が有意な場合、デルタ補正を適用する
            return TabSwitchAdjustment(
                scrollOffset: adjustedScroll,
                scrollToTarget: adjustedScroll,
            )
        }

        return nil
    }
}

/// タブ切替時のスクロール位置補正結果
struct TabSwitchAdjustment: Equatable {
    /// 補正後の previousScrollOffset として記録する値
    let scrollOffset: CGFloat
    /// ScrollView に適用するスクロール先
    let scrollToTarget: CGFloat
}
