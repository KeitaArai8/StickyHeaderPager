import SwiftUI

/// ヘッダー・上部タブ・横ページングを組み合わせたサンプル画面。
///
/// 構造:
/// - ヘッダーと上部タブは**横ページングの外に 1 枚だけ**置き、ヘッダーが隠れている量（`headerOffset`）ぶん上へ流す。
///   上部タブはヘッダーの下端に置き、ヘッダーが畳み切ると safe area の下で止まる（ピン留め）。
/// - 各ページは「ヘッダー + 上部タブ」と同じ高さの余白を先頭に空け、その下に一覧を置く。
/// - ヘッダーの上のドラッグは選択中のページのスクロールへ転送する（ヘッダーは横ページングより上のレイヤーなので、
///   そのままでは下の `ScrollView` に届かない）。
/// - 横ページングは safe area を無視して画面いっぱいに広げ、上下の safe area は余白として自前で配る。
///   横 `ScrollView` の中の縦 `ScrollView` に safe area を任せると、ページの位置と高さが安定しない
///   （ページが safe area ぶん下へずれ、高さが画面全体になる）。
struct DemoView: View {
    /// ヘッダーのうち折りたたまれる部分の高さ（safe area を除く）。ヘッダーが隠れている量の上限になる。
    private static let headerHeight: CGFloat = 240

    @State private var pagingModel = PagingModel(
        items: DemoPageData.all.map { PagingModel.Item(id: $0.id, title: $0.title) },
    )
    @State private var collapse = StickyHeaderModel()
    @State private var tabBarHeight: CGFloat = 40
    /// ドラッグ開始時の選択ページの縦位置。転送量の基準。
    @State private var dragBaseOffsetY: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            // ヘッダー全体の高さ。上端の safe area ぶんを含める（色を敷くため）。
            let headerFullHeight = Self.headerHeight + safeArea.top
            ZStack(alignment: .top) {
                PagingView(model: pagingModel) { item in
                    if let page = DemoPageData.all.first(where: { $0.id == item.id }) {
                        DemoPageView(
                            page: page,
                            collapse: collapse,
                            pagingModel: pagingModel,
                            isSelected: pagingModel.selection == page.id,
                            reservedTopHeight: headerFullHeight + tabBarHeight,
                            collapseRange: Self.headerHeight,
                            bottomInset: safeArea.bottom,
                        )
                    }
                }
                DemoHeaderView(topInset: safeArea.top, contentHeight: Self.headerHeight)
                    .modifier(HeaderFollower(collapse: collapse, baseY: 0))
                    .gesture(scrollForwardingDrag)
                TopTabBar(model: pagingModel)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
                    // ヘッダーの下端から始まり、ヘッダーが隠れている量ぶん上へ動く。畳み切ると safe area の下で止まる（ピン留め）。
                    .modifier(HeaderFollower(collapse: collapse, baseY: headerFullHeight))
            }
            .ignoresSafeArea()
        }
        .onAppear {
            // ヘッダーが隠れている量の上限を共有側へ渡す。
            collapse.updateHeaderHeight(Self.headerHeight)
        }
    }

    /// ヘッダー上のドラッグを選択ページのスクロールへ転送する。
    private var scrollForwardingDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let base = dragBaseOffsetY ?? collapse.selectedPageOffsetY
                dragBaseOffsetY = base
                collapse.requestScroll(toOffsetY: base - value.translation.height, animated: false)
            }
            .onEnded { value in
                let base = dragBaseOffsetY ?? collapse.selectedPageOffsetY
                dragBaseOffsetY = nil
                // 指を離した後は投げた勢いのぶんだけ流す（`UIScrollView` の慣性の代わり）。
                collapse.requestScroll(toOffsetY: base - value.predictedEndTranslation.height, animated: true)
            }
    }
}

// `StickyHeaderModel.headerOffset` はスクロール中毎フレーム更新されるため、読むのを末端の modifier に
// 閉じてヘッダー・上部タブ・ページ本体の body を再評価させない。
private struct HeaderFollower: ViewModifier {
    let collapse: StickyHeaderModel
    /// 展開しきった状態での y 位置。
    let baseY: CGFloat

    func body(content: Content) -> some View {
        content.offset(y: baseY - collapse.headerOffset)
    }
}

private struct DemoHeaderView: View {
    let topInset: CGFloat
    let contentHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()
            Text("Header")
                .font(.largeTitle.bold())
            Text("一覧と一緒に上へ隠れる。上部タブはピン留めされる")
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentHeight + topInset)
        .background {
            LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct DemoPageView: View {
    let page: DemoPageData
    let collapse: StickyHeaderModel
    let pagingModel: PagingModel
    let isSelected: Bool
    /// ヘッダー + 上部タブの高さ。先頭に同じ高さの余白を空ける。
    let reservedTopHeight: CGFloat
    /// ヘッダーが畳める量。
    let collapseRange: CGFloat
    let bottomInset: CGFloat

    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: reservedTopHeight)
                ForEach(1 ... page.rowCount, id: \.self) { row in
                    Text(page.rowLabel(row))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                    Divider()
                }
                Color.clear.frame(height: bottomInset)
            }
            // 短い一覧でもヘッダーの高さぶん縦に動けるようにする。ヘッダーを畳み切れず空白が残るのを防ぐ。
            .frame(minHeight: viewportHeight + collapseRange, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .stickyHeaderPage(collapse, tabID: page.id, pagingModel: pagingModel, isSelected: isSelected)
    }
}
