import SwiftUI

/// 上部タブ。選択はタップで `model.select` を呼ぶだけで、ページの移動は `PagingView` が `model.selection` を見て行う。
public struct TopTabBar: View {
    private let model: PagingModel
    @Namespace private var underline

    public init(model: PagingModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(model.items) { item in
                let isSelected = item.id == model.selection
                Button {
                    model.select(item.id, trigger: .tabTapped)
                } label: {
                    VStack(spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        ZStack {
                            Color.clear.frame(height: 3)
                            if isSelected {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(height: 3)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .animation(.easeInOut(duration: 0.25), value: model.selection)
        .background(.background)
        .overlay(alignment: .bottom) { Divider() }
    }
}
