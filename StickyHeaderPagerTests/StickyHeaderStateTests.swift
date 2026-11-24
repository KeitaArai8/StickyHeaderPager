import CoreGraphics
@testable import StickyHeaderPager
import Testing

// MARK: - handleScrollOffsetChange

@Suite("StickyHeaderState - handleScrollOffsetChange")
@MainActor
struct HandleScrollOffsetChangeTests {
    private static let headerHeight: CGFloat = 200

    @Test
    func 非選択タブのスクロールイベントは無視される() {
        // Arrange: タブAが選択中、タブBからイベント発火
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 50

        // Act: タブB（非選択）のスクロールイベント
        state.handleScrollOffsetChange(
            tabID: "tabB",
            newOffset: 200,
            headerHeight: Self.headerHeight,
            isScrolling: true,
        )

        // Assert: headerOffset は変化しない
        #expect(state.headerOffset == 50)
    }

    @Test
    func 非選択タブの報告で前回の位置は着地した位置に揃い選択後の最初のスクロールはそこから差分を取る() {
        // Arrange: タブAが選択中、タブBの基準は合わせる位置の 500 のまま
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 50
        state.tabStates["tabB"] = TabScrollState(previousScrollOffset: 500)

        // Act: タブB（非選択）が合わせる位置に届かず 300 に着地した報告を受け、選択後に 320 までスクロールする
        state.handleScrollOffsetChange(
            tabID: "tabB",
            newOffset: 300,
            headerHeight: Self.headerHeight,
            isScrolling: false,
        )
        let headerOffsetAfterNonSelectedReport = state.headerOffset
        state.selectedTabID = "tabB"
        state.handleScrollOffsetChange(
            tabID: "tabB",
            newOffset: 320,
            headerHeight: Self.headerHeight,
            isScrolling: true,
        )

        // Assert: 非選択の報告ではヘッダーが隠れている量は動かず、選択後の差分は 300→320 の 20 だけ入る
        #expect(headerOffsetAfterNonSelectedReport == 50)
        #expect(state.headerOffset == 70)
    }

    @Test
    func スクロール中の報告はデルタ追従でヘッダーが隠れている量を動かす() {
        // Arrange: タブAが選択中、headerOffset=100、previousOffset=200
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100
        state.tabStates["tabA"] = TabScrollState(previousScrollOffset: 200)

        // Act: isScrolling: true の報告（200→250）
        state.handleScrollOffsetChange(
            tabID: "tabA",
            newOffset: 250,
            headerHeight: Self.headerHeight,
            isScrolling: true,
        )

        // Assert: デルタ追従で headerOffset が更新される（100 + 50 = 150）
        #expect(state.headerOffset == 150)
    }

    @Test
    func スクロール中でない報告は値が大きく変わってもヘッダーが隠れている量を動かさず縦位置だけ控える() {
        // Arrange: タブAが選択中、headerOffset=100
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100

        // Act: isScrolling: false で 0 → 37 → 500（大きなジャンプ）→ 120 を順に報告する
        for offset: CGFloat in [0, 37, 500, 120] {
            state.handleScrollOffsetChange(
                tabID: "tabA",
                newOffset: offset,
                headerHeight: Self.headerHeight,
                isScrolling: false,
            )

            // Assert: 各報告のあとも headerOffset は 100 のまま、previousScrollOffset は直近の報告値
            #expect(state.headerOffset == 100)
            #expect(state.tabStates["tabA"]?.previousScrollOffset == offset)
        }
    }

    @Test
    func スクロール中でない報告のあとの最初のスクロール中の報告は直近の報告値からデルタを取る() {
        // Arrange: タブ切替の合わせる位置 300 を控えた状態で、headerOffset=100
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100
        state.tabStates["tabA"] = TabScrollState(previousScrollOffset: 300)

        // Act: isScrolling: false で 0 → 500 → 350 と着地の報告が続き、そのあと isScrolling: true で 370 を報告する
        for offset: CGFloat in [0, 500, 350] {
            state.handleScrollOffsetChange(
                tabID: "tabA",
                newOffset: offset,
                headerHeight: Self.headerHeight,
                isScrolling: false,
            )
        }
        state.handleScrollOffsetChange(
            tabID: "tabA",
            newOffset: 370,
            headerHeight: Self.headerHeight,
            isScrolling: true,
        )

        // Assert: 基準は最後の false 報告 350 なので、デルタ +20 ぶん 120 になる（合わせる位置 300 からのデルタなら上限の 200）
        #expect(state.headerOffset == 120)
        #expect(state.tabStates["tabA"]?.previousScrollOffset == 370)
    }

    @Test
    func `selectedTabID が nil の場合、全てのイベントが無視される`() {
        // Arrange: タブ未選択
        var state = StickyHeaderState()
        state.selectedTabID = nil

        // Act: スクロールイベント
        state.handleScrollOffsetChange(
            tabID: "tabA",
            newOffset: 100,
            headerHeight: Self.headerHeight,
            isScrolling: true,
        )

        // Assert: headerOffset は変化しない
        #expect(state.headerOffset == 0)
    }

    @Test
    func `tabStates に未登録のタブでも正しく初期化される`() {
        // Arrange: tabStates にタブAが未登録
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"

        // Act: 未登録タブのスクロールイベント（previousOffset=0として扱われる）
        state.handleScrollOffsetChange(
            tabID: "tabA",
            newOffset: 50,
            headerHeight: Self.headerHeight,
            isScrolling: true,
        )

        // Assert: タブが初期化され、headerOffset が更新される
        #expect(state.tabStates["tabA"] != nil)
        #expect(state.headerOffset == 50)
        #expect(state.tabStates["tabA"]?.previousScrollOffset == 50)
    }
}

// MARK: - adjustForTabSwitch

@Suite("StickyHeaderState - adjustForTabSwitch")
@MainActor
struct AdjustForTabSwitchTests {
    @Test
    func `離脱タブの headerOffset が保存される`() {
        // Arrange: タブAが選択中、headerOffset=150
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 150
        state.tabStates["tabA"] = TabScrollState(previousScrollOffset: 300)

        // Act: タブBに切替
        state.adjustForTabSwitch(to: "tabB")

        // Assert: タブAの headerOffset が保存される
        #expect(state.tabStates["tabA"]?.headerOffset == 150)
    }

    @Test
    func 遷移先タブを合わせる位置が縦位置とスクロール先の両方に控えられる() {
        // Arrange: タブAからタブBへ切替。headerOffset=100、タブBは未訪問
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100

        // Act: タブBに切替
        state.adjustForTabSwitch(to: "tabB")

        // Assert: タブBはヘッダーの下端（100）へ寄せる。その値が控えた縦位置（previousScrollOffset）とスクロール先（scrollToTarget）になる
        #expect(state.tabStates["tabB"]?.previousScrollOffset == 100)
        #expect(state.tabStates["tabB"]?.scrollToTarget == 100)
    }

    @Test
    func `遷移先タブのスクロール位置が補正される（headerDelta あり）`() {
        // Arrange: タブBは headerOffset=150 で scrollOffset=300 の時に離脱
        //          現在の headerOffset=100 → headerDelta=50
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100
        state.tabStates["tabB"] = TabScrollState(
            previousScrollOffset: 300,
            headerOffset: 150,
        )

        // Act: タブBに切替
        state.adjustForTabSwitch(to: "tabB")

        // Assert: デルタ補正が適用される（300 - 50 = 250）
        #expect(state.tabStates["tabB"]?.previousScrollOffset == 250)
        #expect(state.tabStates["tabB"]?.scrollToTarget == 250)
    }

    @Test
    func `遷移先タブの headerOffset が 0 の場合、現在の headerOffset がフォールバックとして使用される`() {
        // Arrange: タブBは未訪問（headerOffset=0）
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100
        state.tabStates["tabB"] = TabScrollState(previousScrollOffset: 0)

        // Act: タブBに切替
        state.adjustForTabSwitch(to: "tabB")

        // Assert: headerDelta=0（currentHeaderOffset=100 がフォールバック）→ 補正なし
        // ただし scrollOffset(0) < currentHeaderOffset(100) なので引き上げ
        #expect(state.tabStates["tabB"]?.scrollToTarget == 100)
    }

    @Test
    func `selectedTabID が nil の場合でも遷移先の処理は正常に実行される`() {
        // Arrange: 初回タブ選択（selectedTabID=nil）
        var state = StickyHeaderState()
        state.selectedTabID = nil
        state.headerOffset = 0

        // Act: タブAに切替
        state.adjustForTabSwitch(to: "tabA")

        // Assert: 遷移先タブが登録され、補正は要らない
        #expect(state.tabStates["tabA"] != nil)
        #expect(state.tabStates["tabA"]?.scrollToTarget == nil)
    }
}

// MARK: - Sequential Scenarios

@Suite("StickyHeaderState - シーケンシャルシナリオ")
@MainActor
struct StickyHeaderStateSequentialTests {
    private static let headerHeight: CGFloat = 200

    @Test
    func `タブ切替 → スクロール → タブ切替戻り: headerOffset が正しく復元される`() {
        // Arrange: タブAでスクロールし、ヘッダーが折りたたまれた状態
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"

        // Step 1: タブAで下方向にスクロール（0→200）
        state.handleScrollOffsetChange(
            tabID: "tabA", newOffset: 200, headerHeight: Self.headerHeight, isScrolling: true,
        )
        #expect(state.headerOffset == 200)

        // Step 2: タブBに切替
        state.adjustForTabSwitch(to: "tabB")
        state.selectedTabID = "tabB"

        // Assert: タブAの headerOffset が保存されている
        #expect(state.tabStates["tabA"]?.headerOffset == 200)
        #expect(state.tabStates["tabB"]?.scrollToTarget == 200)

        // Step 3: タブBが合わせる位置に着地したことを isScrolling: false で報告する
        state.handleScrollOffsetChange(
            tabID: "tabB", newOffset: 200, headerHeight: Self.headerHeight, isScrolling: false,
        )
        #expect(state.headerOffset == 200)

        // Step 4: タブBでスクロール（100→50: 上方向）
        state.handleScrollOffsetChange(
            tabID: "tabB", newOffset: 50, headerHeight: Self.headerHeight, isScrolling: true,
        )
        #expect(state.headerOffset == 50)

        // Step 5: タブAに戻る
        state.adjustForTabSwitch(to: "tabA")
        state.selectedTabID = "tabA"

        // Assert: タブBの headerOffset が保存されている
        #expect(state.tabStates["tabB"]?.headerOffset == 50)
        #expect(state.tabStates["tabA"]?.previousScrollOffset == 50)
    }

    @Test
    func `着地の報告のあと: 連続イベントで正しくデルタ追従する`() {
        // Arrange: タブ切替直後の状態
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        state.headerOffset = 100
        state.tabStates["tabA"] = TabScrollState(previousScrollOffset: 50)

        // Step 1: 合わせる位置 150 への着地を isScrolling: false で報告する
        state.handleScrollOffsetChange(
            tabID: "tabA", newOffset: 150, headerHeight: Self.headerHeight, isScrolling: false,
        )
        #expect(state.headerOffset == 100)
        #expect(state.tabStates["tabA"]?.previousScrollOffset == 150)

        // Step 2: 通常の下方向スクロール（150→180）
        state.handleScrollOffsetChange(
            tabID: "tabA", newOffset: 180, headerHeight: Self.headerHeight, isScrolling: true,
        )

        // Assert: newOffset(180) < headerHeight(200) → 直接追従で headerOffset=180
        #expect(state.headerOffset == 180)

        // Step 3: 上方向スクロール（180→80）
        state.handleScrollOffsetChange(
            tabID: "tabA", newOffset: 80, headerHeight: Self.headerHeight, isScrolling: true,
        )

        // Assert: newOffset(80) < currentHeaderOffset(180) → headerOffset=80
        #expect(state.headerOffset == 80)
    }

    @Test
    func `先頭でのバウンス往復シーケンス: headerOffset が一度も負にならず 0 へ戻る`() {
        // Arrange: 先頭付近でのラバーバンド往復（ヘッダーの 1 フレーム跳ねの再現シーケンス）
        var state = StickyHeaderState()
        state.selectedTabID = "tabA"
        let headerHeight: CGFloat = 303.33
        let reportedOffsets: [CGFloat] = [36.33, -30.67, -139.33, -137.33, -60, 0]

        // Act: 先頭バウンスで届く順に報告し、各ステップ後の headerOffset を記録
        var observedOffsets: [CGFloat] = []
        for offsetY in reportedOffsets {
            state.handleScrollOffsetChange(
                tabID: "tabA", newOffset: offsetY, headerHeight: headerHeight, isScrolling: true,
            )
            observedOffsets.append(state.headerOffset)
        }

        // Assert: 最初の下方向報告で 36.33 まで折りたたまれ、以降のバウンス往復（負のオフセット）では
        //         0 でクランプされ続ける（負値へ落ちるステップが 1 つも無い）
        #expect(observedOffsets == [36.33, 0, 0, 0, 0, 0])
    }
}
