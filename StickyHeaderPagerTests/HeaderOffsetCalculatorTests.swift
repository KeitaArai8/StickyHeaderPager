import CoreGraphics
@testable import StickyHeaderPager
import Testing

@Suite("HeaderOffsetCalculator")
@MainActor
struct HeaderOffsetCalculatorTests {
    struct Case: CustomTestStringConvertible {
        let label: String
        let previous: CGFloat
        let new: CGFloat
        let current: CGFloat
        let headerHeight: CGFloat
        let expected: CGFloat?

        var testDescription: String { label }
    }

    @Test(
        "スクロール方向・位置ごとの headerOffset（nil は変更なし）",
        arguments: [
            // 下方向でヘッダー高以下 → newOffset = 100
            Case(label: "下方向: ヘッダー高以下は newOffset", previous: 50, new: 100, current: 50, headerHeight: 200, expected: 100),
            // 180 + (230 - 210) = 200（headerHeight で上限）
            Case(label: "下方向: ヘッダー高超過はデルタ加算し上限で止まる", previous: 210, new: 230, current: 180, headerHeight: 200, expected: 200),
            // 190 + 100 = 290 → headerHeight 200 で上限クランプ
            Case(label: "下方向: 大きなデルタでも headerHeight を超えない", previous: 300, new: 400, current: 190, headerHeight: 200, expected: 200),
            // 0 でクランプされ current = 0 と同じ → nil
            Case(label: "下方向: バウンス戻り相（負のオフセット）は維持され変更なし", previous: -139.33, new: -137.33, current: 0, headerHeight: 303.33, expected: nil),
            // 負から正へ跨ぐので newOffset = 3
            Case(label: "下方向: 負から正の小さい値へ跨ぐと newOffset", previous: -5, new: 3, current: 0, headerHeight: 303.33, expected: 3),
            // current 150 未満まで戻ったので newOffset = 100
            Case(label: "上方向: currentHeaderOffset 未満まで戻ると newOffset", previous: 160, new: 100, current: 150, headerHeight: 200, expected: 100),
            // max(-10, 0) = 0（下限クランプ）
            Case(label: "上方向: 負の領域でも 0 で下限クランプ", previous: 5, new: -10, current: 5, headerHeight: 200, expected: 0),
            // newOffset 180 が current 100 以上 → nil
            Case(label: "上方向: currentHeaderOffset 以上なら変更なし", previous: 200, new: 180, current: 100, headerHeight: 200, expected: nil),
            // delta 0.05 は 0.1 以下 → nil
            Case(label: "微小なデルタ（0.1以下）は無視", previous: 100, new: 100.05, current: 100, headerHeight: 200, expected: nil),
            // delta 0 → nil
            Case(label: "デルタ 0 は無視", previous: 100, new: 100, current: 50, headerHeight: 200, expected: nil),
            // 初期状態から newOffset = 30
            Case(label: "初期状態からのスクロール開始は newOffset", previous: 0, new: 30, current: 0, headerHeight: 200, expected: 30),
            // 完全折りたたみ（current = headerHeight）から展開開始 → newOffset = 180
            Case(label: "完全折りたたみからの上方向スクロールで展開開始", previous: 250, new: 180, current: 200, headerHeight: 200, expected: 180),
            // min(0 + 50, 0) = 0 = current → nil
            Case(label: "ヘッダー高 0 は下方向でも上限 0 で変更なし", previous: 0, new: 50, current: 0, headerHeight: 0, expected: nil),
        ],
    )
    func calculatesHeaderOffset(_ testCase: Case) {
        // Arrange: 表の行ごとに前回/今回のスクロール位置・現在の headerOffset・ヘッダー高を与える

        // Act: headerOffset を計算する
        let result = HeaderOffsetCalculator.calculateHeaderOffset(
            previousOffset: testCase.previous,
            newOffset: testCase.new,
            currentHeaderOffset: testCase.current,
            headerHeight: testCase.headerHeight,
        )

        // Assert: 行の期待値（nil は変更なし）と一致する
        #expect(result == testCase.expected)
    }
}

// MARK: - Tab Switch Adjustment

@Suite("HeaderOffsetCalculator - TabSwitchAdjustment")
@MainActor
struct TabSwitchAdjustmentTests {
    struct Case: CustomTestStringConvertible {
        let label: String
        let destinationScrollOffset: CGFloat
        let destinationSavedHeaderOffset: CGFloat
        let currentHeaderOffset: CGFloat
        /// 補正後のスクロール位置。nil は補正不要
        let expectedScroll: CGFloat?

        var testDescription: String { label }
    }

    @Test(
        "タブ切り替え時のスクロール補正（nil は補正不要）",
        arguments: [
            // adjusted = 30 は current 100 未満 → ヘッダー境界 100 まで引き上げ
            Case(label: "スクロール位置がヘッダーより上ならヘッダー境界まで引き上げる", destinationScrollOffset: 30, destinationSavedHeaderOffset: 100, currentHeaderOffset: 100, expectedScroll: 100),
            // delta = 150 - 100 = 50、adjusted = 300 - 50 = 250（100 以上なのでデルタ補正）
            Case(label: "headerDelta が有意ならデルタ補正", destinationScrollOffset: 300, destinationSavedHeaderOffset: 150, currentHeaderOffset: 100, expectedScroll: 250),
            // delta = 50 - 150 = -100、adjusted = 200 + 100 = 300（150 以上なのでデルタ補正）
            Case(label: "headerDelta が負でもデルタ補正", destinationScrollOffset: 200, destinationSavedHeaderOffset: 50, currentHeaderOffset: 150, expectedScroll: 300),
            // adjusted = max(0, 10 - 200) = 0 は current 50 未満 → ヘッダー境界 50 まで引き上げ
            Case(label: "補正後が負になるときはヘッダー境界へ引き上げ", destinationScrollOffset: 10, destinationSavedHeaderOffset: 250, currentHeaderOffset: 50, expectedScroll: 50),
            // delta = 0.05 は微小、scroll 200 は current 100 以上 → 補正なし
            Case(label: "headerDelta が微小かつヘッダー以上なら補正なし", destinationScrollOffset: 200, destinationSavedHeaderOffset: 100.05, currentHeaderOffset: 100, expectedScroll: nil),
            // delta 0、scroll 300 は current 100 以上 → 補正なし
            Case(label: "headerDelta 0 かつヘッダー以上なら補正なし", destinationScrollOffset: 300, destinationSavedHeaderOffset: 100, currentHeaderOffset: 100, expectedScroll: nil),
            // 全て 0 → 補正なし
            Case(label: "初期状態（全て 0）は補正なし", destinationScrollOffset: 0, destinationSavedHeaderOffset: 0, currentHeaderOffset: 0, expectedScroll: nil),
        ],
    )
    func calculatesTabSwitchAdjustment(_ testCase: Case) {
        // Arrange: 表の行ごとに遷移先のスクロール位置・保存済み headerOffset・現在の headerOffset を与える

        // Act: タブ切り替え時の補正を計算する
        let result = HeaderOffsetCalculator.calculateTabSwitchAdjustment(
            destinationScrollOffset: testCase.destinationScrollOffset,
            destinationSavedHeaderOffset: testCase.destinationSavedHeaderOffset,
            currentHeaderOffset: testCase.currentHeaderOffset,
        )

        // Assert: 補正ありなら scrollOffset と scrollToTarget がともに期待値、補正なしなら nil
        let expected = testCase.expectedScroll.map { TabSwitchAdjustment(scrollOffset: $0, scrollToTarget: $0) }
        #expect(result == expected)
    }
}
