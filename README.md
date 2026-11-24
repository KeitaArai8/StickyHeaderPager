# StickyHeaderPager

ヘッダーが畳まれ、上部タブが画面上端にピン留め（sticky）され、複数ページを横ページングで切り替える UI の SwiftUI サンプルです。各ページはそれぞれ縦の `ScrollView` を持ちます。

再利用ライブラリではなく、設計と実装上の落とし穴を残すための知見リポジトリです。コードは読んで持ち帰る前提で、外部依存はありません。

## 概要

- ヘッダー（畳まれる部分）と上部タブを、横ページングの外に 1 枚だけ置く
- 各ページは先頭にヘッダー + 上部タブと同じ高さの余白を空け、その下に一覧を置く
- ヘッダーの畳まれ具合（`headerOffset`）は、選択中のページの縦スクロールの差分（デルタ）で増減させる
- 縦のスクロール位置は、ページごとに保つ

iOS 18+ が必要です。`ScrollPosition`（プログラムからのスクロール）、`onScrollGeometryChange`（縦位置の報告）、`onScrollPhaseChange`（指で動かしているかの判定）に依存するためです。

## 再現する UX

| No | 挙動 | 録画 |
|---|---|---|
| U1 | 下へスクロールするとヘッダーが一覧と一緒に上へ隠れ、上部タブは画面上端にピン留めされて残る | [U1-collapse-and-pin.mp4](Docs/U1-collapse-and-pin.mp4) |
| U2 | 上へ戻すときは、一覧の先頭が近づいたときにだけヘッダーが出てくる（途中で少し戻しただけでは出てこない） | [U2-header-returns-near-top.mp4](Docs/U2-header-returns-near-top.mp4) |
| U3 | ページごとに縦のスクロール位置が保たれる | [U3-per-page-position.mp4](Docs/U3-per-page-position.mp4) |
| U4 | タブを切り替えてもヘッダーの隠れ具合は変わらず、遷移先の一覧を差の分だけずらしてヘッダーと一覧の境目を合わせる。遷移先が先頭付近なら境目まで引き上げる | [U4-tab-switch-alignment.mp4](Docs/U4-tab-switch-alignment.mp4) |
| U5 | 横ページングのスワイプ途中で見えてくる隣のページも、現れた時点で境目が合っている | [U5-swipe-alignment.mp4](Docs/U5-swipe-alignment.mp4) |
| U6 | ヘッダーの上で縦にドラッグすると選択中のページの一覧がスクロールする。指を離すと短い easeOut で流れ、短い一覧ではその下端で止まる | [U6-header-drag.mp4](Docs/U6-header-drag.mp4) |

## 仕組み

```
ZStack
├─ PagingView            横ページング。各ページが縦 ScrollView（先頭に余白 = ヘッダー + 上部タブの高さ）
├─ ヘッダー              offset(y: -headerOffset)。ドラッグを選択ページへ転送する
└─ TopTabBar             offset(y: ヘッダー高 - headerOffset)。畳み切ると上端で止まる = ピン留め
```

- **ヘッダーの追従**: ページの縦位置が変わるたびに、前回との差分（デルタ）で `headerOffset` を増減する（`HeaderOffsetCalculator`）。下へ行くときは位置にそのまま追従し、上へ戻るときは「縦位置が `headerOffset` を下回ったとき」だけ追従するので、一覧の先頭が近づくまでヘッダーは出てこない（U1・U2）
- **縦位置はページごと**: 各ページの `ScrollView` が自分の位置を持つ。`StickyHeaderState` がページごとの縦位置と、離脱時の `headerOffset` を控える（U3）
- **タブ切替**: 遷移先ページを「離脱時と今の `headerOffset` の差」ぶんずらして、ヘッダーと一覧の境目を合わせる。ずらすと先頭より上になるときは、境目まで引き上げる（U4、`calculateTabSwitchAdjustment`）
- **スワイプ中の合わせ直し**: 隣のページはスワイプが始まった時点と、ページが生成された時点で合わせておく。見え始めたときに境目が合っている（U5、`StickyHeaderModel.align`）
- **ヘッダーのドラッグ**: ヘッダーは横ページングより上のレイヤーなので、ドラッグは下の `ScrollView` に届かない。ドラッグ量を選択ページの縦位置の要求（`requestScroll`）へ変換して転送する。指を離すときは `predictedEndTranslation` までを短い easeOut で流す。行き先はそのページの下端で止める（U6）

型の役割:

| 型 | 役割 |
|---|---|
| `HeaderOffsetCalculator` | デルタ追従・タブ切替補正の純粋関数 |
| `StickyHeaderState` | ページごとの縦位置・`headerOffset` の状態遷移（View から分離してテスト可能にしたもの） |
| `StickyHeaderModel` | `@Observable`。View との橋渡し。`stickyHeaderPage(...)` modifier がページの `ScrollView` とつなぐ |
| `PagingModel` / `PagingView` | 最小の横ページングと選択状態 |
| `TopTabBar` | 上部タブ |

## 実装上の注意点

実際に踏んだ不具合です。コード中のコメントにも同じ内容があります。

### 1. 先頭バウンスの戻りでヘッダーが 1 フレーム逆に跳ねる

- 症状: 一覧の先頭でラバーバンドが戻るとき、ヘッダーが一瞬逆方向へ跳ねる
- 原因: 戻りの途中で縦位置が一瞬負になり、負の `headerOffset` がそのまま描画の位置に使われる
- 対処: `newOffset` が 0 未満のときは 0 で止める
- 該当コード: `HeaderOffsetCalculator.swift`（テスト: `先頭でのバウンス往復シーケンス`）

### 2. 指を動かしたまま離すと最後の移動分が抜ける

- 症状: 指を動かしたまま離すと、ヘッダーが最後の数 pt ぶん畳まれない / 出てこない
- 原因: `onScrollPhaseChange` の `.idle` への変化が、最後の位置報告より先に届く。その最後の報告が「止まっている間のもの」として扱われ、`headerOffset` に入らない（iOS 26.5 Simulator で再現）
- 対処: 動いている状態から止まる変化を受けたとき、止まった位置を「動いている間の報告」として先に渡す
- 該当コード: `StickyHeaderModel.swift` の `onScrollPhaseChange`

### 3. ScrollView が出る前の `scrollTo` は効かない

- 症状: 生成と同時に選択されたページへ位置合わせしても、位置が動かない
- 原因: `ScrollView` が画面に出る前の `ScrollPosition.scrollTo` は無視される
- 対処: 合わせる位置を控えておき、`onAppear` で当て直す
- 該当コード: `StickyHeaderModel.swift` の `pendingAlignOffsetY` / `hasAppeared`

### 4. 位置合わせを二重に当てるとページが飛ぶ

- 症状: タブ切替やスワイプのあと、ページが想定より大きくずれる
- 原因: 同じ `headerOffset` に対して補正を 2 回当てると、補正量が二重に効く。スワイプ開始時と着地時の両方で当てる経路がある
- 対処: どの `headerOffset` で合わせたかを控え、同じ値に対しては 1 回だけ当てる。`headerOffset` が動いたら控えを捨てる
- 該当コード: `StickyHeaderModel.swift` の `alignedTabs`

### 5. 指を離した直後にすぐアニメーションするとヘッダーが引き戻される

- 症状: ヘッダーのドラッグを離した瞬間、ヘッダーが一度戻ってから目的の位置へ向かう
- 原因: 指追従の最後のスクロール要求とアニメーション付きの要求が同じフレームに届き、アニメーションが「最後に描画された位置」から始まる
- 対処: アニメーション付きの要求は 1 メインアクターターン遅らせて開始する
- 該当コード: `StickyHeaderModel.swift` の `onChange(of: shared.scrollRequest)`

### 6. `ScrollGeometry.containerSize` は上下の inset を除いた高さ

- 症状: 一覧が進める縦位置の上限が、inset ぶん大きく（または小さく）計算される
- 原因: `containerSize` は inset を除いた高さで届く。そこへ inset を足すと二重に数える
- 対処: 上限は `contentSize.height - containerSize.height` で求め、inset は足さない
- 該当コード: `StickyHeaderModel.swift` の `maxOffsetY(of:)`

### 7. 短い一覧でヘッダーだけ先に畳むと空白が残る

- 症状: 短い一覧でヘッダーを上へドラッグすると、畳んだヘッダーと一覧の間に空白が残る
- 原因: 一覧が進める位置を越えてヘッダーだけが畳まれる。ページは動かないので位置の報告も来ず、辻褄が合わない
- 対処: ドラッグの行き先を、そのページの下端（注意点 6 の上限）で止める
- 該当コード: `StickyHeaderModel.swift` の `requestScroll`

### 8. 離れたタブへのタップで間のページを通過する

- 症状: 2 ページ以上離れたタブをタップすると、間のページを通過してカクつく
- 原因: アニメーション付きの `scrollPosition(id:)` で離れたページへスライドさせると、`LazyHStack` が間のページを 1 枚ずつ生成・描画する
- 対処: 2 ページ以上離れたタブへは、アニメーションせずに直接切り替える。隣のタブへのタップだけスライドさせる
- 該当コード: `Paging/PagingView.swift`

### 9. スライド中に画面へ触れると、選択とページが食い違う

- 症状: タブをタップした直後に一覧へ触れると、上部タブの選択は変わったのに元のページが見えたままになる（iOS 26.5 Simulator で再現）
- 原因: スライドは触れた時点で止まるが、`scrollPosition(id:)` の binding は行き先の ID のまま残る
- 対処: 止まったとき（`.idle`）の選択を、binding でなく横スクロールの実際の位置から決める
- 該当コード: `Paging/PagingView.swift` の `commitCurrentPage`

### 補足: 横ページングと safe area

横 `ScrollView` の中に縦 `ScrollView` を置いて safe area の中に収めると、ページが safe area ぶん下へずれ、高さが画面全体になりました。このサンプルでは横ページングごと safe area を無視し、上下の余白を自前で配っています（`Demo/DemoView.swift`）。

## 性能の注意

`headerOffset` はスクロール中に毎フレーム変わります。読むのは、ヘッダーと上部タブの `offset` を当てる末端の `ViewModifier`（`HeaderFollower`）だけに閉じてください。画面やページの `body` から読むと、スクロール中に毎フレーム一覧が再評価されます。

## 動かし方

Xcode 16 以降で `StickyHeaderPager.xcodeproj` を開き、iOS 18 以降のシミュレータで実行します。

```sh
xcodebuild -scheme StickyHeaderPager -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## 公開手順

このフォルダには git の履歴も作者情報も含まれていません。コミットの作者・`LICENSE` の名前・リポジトリの持ち主は、すべて実行する Mac の設定から決まります。

1. 実行する Mac の設定が、公開に使いたいものになっているか確かめる

   ```sh
   git config --global user.name
   git config --global user.email
   gh auth status
   ```

2. `LICENSE` の `<YOUR NAME>` を `git config user.name` の値で埋める

   ```sh
   sed -i '' "s/<YOUR NAME>/$(git config --global user.name)/" LICENSE
   ```

3. コミットしてリポジトリを作る（作者は手順 1 の設定、リポジトリの持ち主は `gh` でログインしているアカウントになる）

   ```sh
   git init
   git add .
   git commit -m "Add sticky header pager sample"
   gh repo create StickyHeaderPager --public --source=. --push
   ```
