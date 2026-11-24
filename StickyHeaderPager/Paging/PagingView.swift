import SwiftUI

/// 横ページングの最小実装。ページごとに縦 `ScrollView` を持つ中身は `content` が返す。
///
/// - 横 `ScrollView` + `.scrollTargetBehavior(.paging)` + `scrollPosition(id:)` でページ送りする。
/// - 指で動かしている間（`.interacting` / `.decelerating`）だけ `model.isUserScrolling` を true にする。
///   縦位置の合わせ直しの契機に使う（`StickyHeaderModel.align`）。
/// - 着地（`.idle`）で 1 回だけ `select(_:trigger: .pageSwiped)` する。`scrollPosition(id:)` は指を離した時点
///   （着地アニメーションの前）に新しいページを報せるため、止まってから反映する。
public struct PagingView<Page: View>: View {
    private let model: PagingModel
    private let content: (PagingModel.Item) -> Page

    /// `ScrollView` の現在ページ。`model.selection` に直結させず内部に持つのは、タブタップのときだけスライドで
    /// 移るため（スワイプ着地はすでにその位置にあるのでアニメーションしてはいけない）。
    @State private var currentID: String?
    /// 横スクロールの実際の位置にあるページの index。
    @State private var visibleIndex = 0

    public init(model: PagingModel, @ViewBuilder content: @escaping (PagingModel.Item) -> Page) {
        self.model = model
        self.content = content
        _currentID = State(initialValue: model.selection)
    }

    public var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.items) { item in
                    content(item)
                        // `.paging` はコンテナ幅単位でスナップするので、ページ幅をコンテナ幅に合わせる。
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID, anchor: .center)
        // 軸を横に絞り、各ページ自身の縦の指定を上書きしない。
        .scrollIndicators(.hidden, axes: .horizontal)
        .onScrollGeometryChange(for: Int.self) { geometry in
            let width = geometry.containerSize.width
            return width > 0 ? Int((geometry.contentOffset.x / width).rounded()) : 0
        } action: { _, index in
            visibleIndex = index
        }
        .onScrollPhaseChange { _, newPhase in
            model.setUserScrolling(newPhase == .interacting || newPhase == .decelerating)
            if newPhase == .idle { commitCurrentPage() }
        }
        .onChange(of: model.selection) { _, newValue in
            guard newValue != currentID else { return }
            guard model.lastTrigger == .tabTapped else {
                currentID = newValue
                return
            }
            // 2 ページ以上離れたタブへはアニメーションせず直接切り替える。スライドさせると間のページをすべて
            // スクロールで通過し、`LazyHStack` が 1 枚ずつ生成・描画してカクつく。
            if isDistantJump(to: newValue) {
                currentID = newValue
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                currentID = newValue
            }
        }
    }

    /// `id` のページが現在ページから 2 ページ以上離れているか。
    private func isDistantJump(to id: String) -> Bool {
        guard let currentIndex = model.items.firstIndex(where: { $0.id == currentID }),
              let targetIndex = model.items.firstIndex(where: { $0.id == id })
        else { return false }
        return abs(targetIndex - currentIndex) > 1
    }

    /// 止まった位置にあるページを選択へ反映する。
    ///
    /// タブタップのスライド中に画面へ触れるとスライドは途中で止まるが、`currentID` は行き先のまま残る。
    /// `currentID` でなく実際の位置から決めないと、上部タブの選択と見えているページが食い違う。
    private func commitCurrentPage() {
        guard model.items.indices.contains(visibleIndex) else { return }
        let visibleID = model.items[visibleIndex].id
        if currentID != visibleID { currentID = visibleID }
        guard visibleID != model.selection else { return }
        model.select(visibleID, trigger: .pageSwiped)
    }
}
