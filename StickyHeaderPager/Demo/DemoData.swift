import Foundation

/// デモ用のダミーデータ。ページごとの行数だけが違う。
struct DemoPageData: Identifiable {
    let id: String
    let title: String
    let rowCount: Int
    let pageNumber: Int

    /// 一覧の行ラベル。ページと行が見分けられるようにする。
    func rowLabel(_ row: Int) -> String {
        "Page \(pageNumber) - Row \(row)"
    }

    static let all: [DemoPageData] = [
        DemoPageData(id: "long", title: "長いリスト", rowCount: 80, pageNumber: 1),
        // 画面より短い一覧。ヘッダーを畳み切れるかの確認用。
        DemoPageData(id: "short", title: "短いリスト", rowCount: 3, pageNumber: 2),
        DemoPageData(id: "other", title: "もうひとつ", rowCount: 40, pageNumber: 3),
    ]
}
