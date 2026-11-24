import SwiftUI

/// 上部タブ（`TopTabBar`）と横ページング（`PagingView`）が共有する選択状態。
///
/// 選択の正（SSOT）はこの model。タブのタップでもスワイプの着地でも `select(_:trigger:)` を通る。
@Observable @MainActor
public final class PagingModel {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// 選択切替の発火元。横ページングは `.tabTapped` のときだけスライドで追従する
    /// （スワイプ着地の反映でアニメーションすると、すでに着地した位置から動いてしまう）。
    public enum SelectionTrigger: Equatable, Sendable {
        case tabTapped
        case pageSwiped
        case programmatic
    }

    public let items: [Item]
    public private(set) var selection: String
    @ObservationIgnored public private(set) var lastTrigger: SelectionTrigger = .programmatic

    /// 指で横ページングを動かしている間（ドラッグ・慣性）だけ true。
    /// タブタップ起因のスライド（`.animating`）は含めない。縦位置の合わせ直し（`StickyHeaderModel.align`）の
    /// 契機は「ユーザーが隣のページを見せ始めた」ことで、タップ起因は選択の切替側で合わせるため。
    public private(set) var isUserScrolling = false

    public init(items: [Item]) {
        precondition(!items.isEmpty)
        self.items = items
        selection = items[0].id
    }

    public func select(_ id: String, trigger: SelectionTrigger) {
        guard id != selection, items.contains(where: { $0.id == id }) else { return }
        lastTrigger = trigger
        selection = id
    }

    func setUserScrolling(_ value: Bool) {
        guard isUserScrolling != value else { return }
        isUserScrolling = value
    }
}
