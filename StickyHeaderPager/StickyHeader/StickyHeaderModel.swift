import SwiftUI

/// ページごとに縦 `ScrollView` を持つ横ページングで、ヘッダーが隠れている量だけをページ間で共有する。
///
/// ヘッダーを横ページングの外に 1 枚だけ置く画面で使う。ヘッダーはこのヘッダーが隠れている量ぶん上へ流し、ページ側は
/// 同じ高さの余白を空けておく。**縦位置そのものはページごとに保つ**（各ページの `ScrollView` が自分の
/// 位置を持ち続ける）ため、片方のタブのスクロールがもう片方へ伝播しない。
///
/// ヘッダーが隠れている量はスクロールの**デルタ**で増減させる（`HeaderOffsetCalculator`）。ページを切り替えるときは、
/// 遷移先が前回表示されていたときのヘッダーが隠れている量との差分だけを遷移先ページへワンショットで当て、上端に見えているコンテンツの
/// 位置を保つ（`StickyHeaderState.adjustForTabSwitch`）。ヘッダーが隠れている量を動かすのは、ページがユーザー操作か
/// アニメーションで動いている間の報告だけ（位置合わせやレイアウト確定で縦位置が変わっても動かさない）。
///
/// - Important: `headerOffset` はスクロール中毎フレーム更新される。読むのは追従させる末端の View（ヘッダーの
///   `offset` 等）だけに閉じ、ページ本体の body から読まない（読むとスクロール中毎フレーム一覧が再評価される）。
@Observable @MainActor
public final class StickyHeaderModel {
    /// ヘッダーが隠れている量（0 = 完全展開 〜 `headerHeight` = 完全折りたたみ）。
    public private(set) var headerOffset: CGFloat = 0

    /// ヘッダー領域のドラッグを選択ページのスクロールへ転送する要求。
    private(set) var scrollRequest: ScrollRequest?

    struct ScrollRequest: Equatable, Sendable {
        let offsetY: CGFloat
        let animated: Bool
        /// 同じ位置への再要求も区別するための連番（`onChange` で拾うため）。
        let sequence: Int
    }

    /// タブごとの縦位置とヘッダーが隠れている量。View の再評価に載せないため観測対象から外す（描画に使うのは
    /// ここから publish した `headerOffset` だけ）。
    @ObservationIgnored private var state = StickyHeaderState()
    /// ヘッダーの全高（= ヘッダーが隠れている量の上限）。ヘッダー側が実測して渡す。
    @ObservationIgnored private var headerHeight: CGFloat = 0
    /// 合わせ直し済みのタブと、そのときのヘッダーが隠れている量。同じヘッダーが隠れている量で二重に補正しないための控え
    /// （二重に当てると補正量が二重に効いてページが飛ぶ）。
    @ObservationIgnored private var alignedTabs: [String: CGFloat] = [:]
    @ObservationIgnored private var requestSequence = 0

    public init() {}

    /// ヘッダーの実測高さを渡す。ヘッダーが隠れている量の上限になる。
    public func updateHeaderHeight(_ height: CGFloat) {
        headerHeight = height
    }

    /// ヘッダー領域のドラッグの基準に使う、選択ページの現在の縦位置。
    public var selectedPageOffsetY: CGFloat {
        guard let tabID = state.selectedTabID else { return 0 }
        return state.tabStates[tabID]?.previousScrollOffset ?? 0
    }

    /// ページの現在位置を控え、デルタぶんヘッダーを折りたたむ／展開する。選択ページ以外の報告ではヘッダーが隠れている量は動かない。
    ///
    /// - Parameters:
    ///   - isScrolling: ページがユーザー操作かアニメーションで動いている最中か。false の報告はヘッダーが隠れている量を動かさない。
    func reportScroll(tabID: String, offsetY: CGFloat, isScrolling: Bool) {
        state.handleScrollOffsetChange(
            tabID: tabID,
            newOffset: offsetY,
            headerHeight: headerHeight,
            isScrolling: isScrolling,
        )
        publishHeaderOffset()
    }

    /// ページが進める縦位置の上限を控える。ヘッダー領域のドラッグの転送先をこの範囲に収めるのに使う。
    func reportMaxScrollOffset(tabID: String, maxOffsetY: CGFloat) {
        state.tabStates[tabID, default: TabScrollState()].maxScrollOffset = maxOffsetY
    }

    /// 選択タブを切り替える。離脱タブのヘッダーが隠れている量を控え、遷移先には差分ぶんの補正を当てる。
    ///
    /// - Returns: 遷移先ページの合わせる位置。補正不要なら nil。
    @discardableResult
    func selectTab(_ tabID: String) -> CGFloat? {
        guard tabID != state.selectedTabID else { return nil }
        // 離脱タブのヘッダーが隠れている量を控える。古い値が残ると、戻ったときにその差ぶん一覧が動く。
        if let currentTabID = state.selectedTabID {
            state.tabStates[currentTabID, default: TabScrollState()].headerOffset = headerOffset
        }
        let target = align(tabID: tabID)
        state.selectedTabID = tabID
        return target
    }

    /// 対象ページの縦位置を現在のヘッダーが隠れている量へ合わせる位置を求める。横スワイプで隣のページが現れる前に
    /// 当てることで、ヘッダーと中身の境目が合った状態でページが入ってくる。
    ///
    /// - Returns: 合わせる位置。合わせ済み・補正不要なら nil。
    @discardableResult
    func align(tabID: String) -> CGFloat? {
        // 最初の選択が済むまでは合わせ先が無い（ヘッダーは展開しきった状態で、離脱タブも補正する差分も無い）。
        guard let selectedTabID = state.selectedTabID, tabID != selectedTabID else { return nil }
        // 同じヘッダーが隠れている量に対しては 1 度だけ。スワイプ開始時に当てた補正を着地時にもう一度当てない。
        guard alignedTabs[tabID] != headerOffset else { return nil }
        alignedTabs[tabID] = headerOffset

        return consumeAlignTarget(for: tabID)
    }

    /// `StickyHeaderState.adjustForTabSwitch` を呼んだあと、選択を伴わない場合の事後条件（遷移先のヘッダーが隠れている量）を
    /// 補い、ワンショットの合わせる位置を消費して返す。
    private func consumeAlignTarget(for tabID: String) -> CGFloat? {
        state.adjustForTabSwitch(to: tabID)
        // 補正で書き換えた縦位置が「どのヘッダーが隠れている量に対するものか」を遷移先にも控える。`adjustForTabSwitch` は
        // 離脱タブのヘッダーが隠れている量しか保存しない（切替と対でしか呼ばれない前提）ため、ここのように選択されない
        // ページへ合わせ直しだけを当てると、縦位置だけ新しくヘッダーが隠れている量が古いままの組になり、次の補正量が
        // その差ぶんずれて蓄積する（横スワイプを途中で戻す・隣でないページが先に寄せられる、で起きる）。
        state.tabStates[tabID]?.headerOffset = headerOffset
        guard let target = state.tabStates[tabID]?.scrollToTarget else { return nil }
        state.tabStates[tabID]?.scrollToTarget = nil
        return target
    }

    /// ヘッダー領域のドラッグを選択ページのスクロールへ転送する。ヘッダー自身は先頭より上へは動かさない
    /// （引っぱりの遊びは持たない）。
    public func requestScroll(toOffsetY offsetY: CGFloat, animated: Bool) {
        // ページが進める上限でも止める。越えた位置でヘッダーだけ先に畳むと、ページは届かず位置の報告も来ないので、
        // 畳んだヘッダーと一覧の間に空白が残る（一覧が短いページで起きる）。上限が届く前のページは先頭でだけ止める。
        let maxOffsetY = state.selectedTabID.flatMap { state.tabStates[$0]?.maxScrollOffset } ?? .infinity
        let target = min(max(offsetY, 0), maxOffsetY)
        requestSequence += 1
        scrollRequest = ScrollRequest(offsetY: target, animated: animated, sequence: requestSequence)
        // 指追従（ドラッグ中）はページからの報告が次フレームになるため、同じ経路をここで先に通して遅延を消す。
        // アニメーション付き（指を離した後の流れ）では進めない。進めるとヘッダーだけが着地位置へ一瞬先回りし、
        // ページの報告（アニメーション中の中間値）で引き戻される。
        guard !animated, let tabID = state.selectedTabID else { return }
        reportScroll(tabID: tabID, offsetY: target, isScrolling: true)
    }

    private func publishHeaderOffset() {
        guard headerOffset != state.headerOffset else { return }
        headerOffset = state.headerOffset
        // ヘッダーが隠れている量が動いた＝控えた合わせ先が古くなる。次に現れるページは合わせ直す。
        alignedTabs.removeAll()
    }
}

public extension View {
    /// 横ページングのページが持つ縦 `ScrollView` を、共有するヘッダーが隠れている量とつなぐ。
    ///
    /// 縦位置はページごとに保たれる（この modifier はページを他ページの位置へ寄せない）。選択ページは自分の
    /// 位置を報告してヘッダーを駆動し、ヘッダー領域からのドラッグ（`requestScroll(toOffsetY:animated:)`）を
    /// 受ける。裏ページは横ページングに現れるタイミングでヘッダーが隠れている量へ合わせ直す。
    ///
    /// プログラムからスクロール位置を動かす `ScrollPosition`・位置の報告に使う `onScrollGeometryChange`・
    /// 指で動かしているかの判定に使う `onScrollPhaseChange` はいずれも iOS 18+。
    ///
    /// - Important: ヘッダーが追従するのは、ユーザーの操作とアニメーション付きのスクロールだけ。アニメーション
    ///   なしで縦位置をコードから動かすとヘッダーは動かないので、先頭へ戻す等は `withAnimation` 付きで動かす。
    ///
    /// - Parameters:
    ///   - shared: 画面のライフタイム中に変わらない値を渡す。
    ///   - tabID: このページのタブ ID。ヘッダーが隠れている量の控え先のキーになる。
    ///   - pagingModel: 横スワイプ中かの判定に使う（`isUserScrolling`）。
    ///   - isSelected: このページが選択中か。
    func stickyHeaderPage(
        _ shared: StickyHeaderModel,
        tabID: String,
        pagingModel: PagingModel,
        isSelected: Bool,
    ) -> some View {
        modifier(
            StickyHeaderPageSync(
                shared: shared,
                tabID: tabID,
                pagingModel: pagingModel,
                isSelected: isSelected,
            ),
        )
    }
}

/// ページ位置の報告、現れるページの合わせ直し、ヘッダーからの転送の受け取り。ヘッダーが隠れている量（毎フレーム更新）を
/// 読むのをこの modifier のクロージャに閉じ、ページ本体の body を再評価させない。
private struct StickyHeaderPageSync: ViewModifier {
    let shared: StickyHeaderModel
    let tabID: String
    let pagingModel: PagingModel
    let isSelected: Bool

    @State private var position = ScrollPosition()
    /// `ScrollView` が現れたか。現れる前の `scrollTo` は効かないため、合わせる位置を持ち越すのに使う。
    @State private var hasAppeared = false
    /// 現れる前に求まった合わせる位置。appear 時に当て直す。
    @State private var pendingAlignOffsetY: CGFloat?
    /// ユーザー操作か `scrollTo` のアニメーションでページが動いている最中か。
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            // 裏ページの報告は前回の位置を控えるだけで、ヘッダーが隠れている量は動かさない。
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                Self.offsetY(of: geometry)
            } action: { _, offsetY in
                shared.reportScroll(
                    tabID: tabID,
                    offsetY: offsetY,
                    isScrolling: isScrolling,
                )
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                Self.maxOffsetY(of: geometry)
            } action: { _, maxOffsetY in
                shared.reportMaxScrollOffset(tabID: tabID, maxOffsetY: maxOffsetY)
            }
            .onScrollPhaseChange { oldPhase, newPhase, context in
                // 指を動かしたまま離すと、`.idle` への変化が同じフレームの最後の位置報告より先に届き、その報告が
                // 止まっている間のものとして扱われて最後の移動ぶんがヘッダーが隠れている量に入らない。止まった位置をここで
                // 動いている間の報告として先に渡す（iOS 26.5 シミュレータで再現）。
                // ページの生成時にも `.idle` → `.idle` が届く。そこで渡すと位置合わせ前の 0 でヘッダーが隠れている量が開くので除く。
                if oldPhase.isScrolling, !newPhase.isScrolling {
                    shared.reportScroll(
                        tabID: tabID,
                        offsetY: Self.offsetY(of: context.geometry),
                            isScrolling: true,
                    )
                }
                isScrolling = newPhase.isScrolling
            }
            // タブタップでの選択切替（横スワイプを経由しない）に対応する。`initial: true` は「appear 時点で
            // 既に選択済み」（例: 離れたタブへのタップで初めて生成されるページ）も同じ経路でカバーするため
            // （この場合 isSelected は false→true を経ず最初から true なので、initial 無しでは発火しない）。
            .onChange(of: isSelected, initial: true) { _, newValue in
                guard newValue else { return }
                align(to: shared.selectTab(tabID))
            }
            // 横スワイプ中に生成されたページ（`LazyHStack` は表示直前に作る）もここで合わせる。
            .onAppear {
                hasAppeared = true
                // 生成と同時に選択された場合、合わせる位置は `ScrollView` が現れる前に求まっている。
                if let pending = pendingAlignOffsetY {
                    pendingAlignOffsetY = nil
                    scroll(to: pending)
                }
                align(to: shared.align(tabID: tabID))
            }
            .onChange(of: pagingModel.isUserScrolling) { _, isSwiping in
                guard isSwiping else { return }
                align(to: shared.align(tabID: tabID))
            }
            .onChange(of: shared.scrollRequest) { _, request in
                guard let request, isSelected else { return }
                guard request.animated else {
                    position.scrollTo(y: request.offsetY)
                    return
                }
                // 指を離した瞬間、指追従の最後の request（非アニメーション）とこの request が
                // 同一フレーム内で連続して届く。ここで即座に easeOut を開始すると、直前の request がまだ
                // 描画に反映されておらず、最後に描画済みの位置から補間が始まるため、指追従で先に進めたヘッダーが
                // 一度引き戻されてから着地点へ向かう。1 メインアクターターン遅らせて直前の position 更新を
                // コミットさせてから開始する。
                let sequence = request.sequence
                Task { @MainActor in
                    guard shared.scrollRequest?.sequence == sequence else { return }
                    // 指を離した後の流れ。`UIScrollView` の減速に寄せて短い easeOut で寄せる。
                    withAnimation(.easeOut(duration: 0.35)) {
                        position.scrollTo(y: request.offsetY)
                    }
                }
            }
    }

    /// 求まった合わせる位置へ合わせる。`ScrollView` が現れる前は持ち越す。
    private func align(to offsetY: CGFloat?) {
        guard let offsetY else { return }
        guard hasAppeared else {
            pendingAlignOffsetY = offsetY
            return
        }
        scroll(to: offsetY)
    }

    /// 合わせ直しは見せない（ページが現れる前・切替と同時に済ませる位置合わせのため）。
    private func scroll(to offsetY: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.scrollTo(y: offsetY)
        }
    }

    /// 内容の先頭が上端にある状態を 0 とした縦位置。safe area ぶんの上 inset が入るため、素の contentOffset は
    /// 先頭で負になる。`.idle` に変わった瞬間の値と直後の報告の差分を取るので、どちらもここで求める。
    private static func offsetY(of geometry: ScrollGeometry) -> CGFloat {
        geometry.contentOffset.y + geometry.contentInsets.top
    }

    /// `offsetY(of:)` と同じ原点で測った、ページが進める縦位置の上限。中身が枠に収まるなら 0。
    /// `containerSize` は上下の inset を除いた高さで届くので、inset を足すと二重に数える。
    private static func maxOffsetY(of geometry: ScrollGeometry) -> CGFloat {
        max(geometry.contentSize.height - geometry.containerSize.height, 0)
    }
}
