# ContinuousPlayer for iOS

TVアニメのOP/EDを中心に、フォルダー内の動画・音声を連続再生するアプリです。iPhone / iPad、Mac Catalyst、Apple TVに対応し、SwiftUIとAVFoundationで実装しています。

## 主な機能

- 選択したファイルから、同じフォルダー直下のメディアを連続再生
- ファイル名に応じたOP/EDの並べ替え
- 端末・USBストレージのフォルダー登録とアクセス許可の保存（iPhone / iPad / Mac）
- DLNAメディアサーバーのフォルダー閲覧とMP4／M4Vの連続再生
- タッチ・外部キーボード・Siri Remoteによる再生操作
- ファイル情報・映像／音声形式・音声出力情報の表示
- iPhone / iPadの縦画面・横画面に対応

詳細な挙動、制約、プラットフォームごとの差異は [アプリケーション仕様](docs/spec.md) を参照してください。

## 動作環境

| 版 | 対応OS | メディアの取得元 |
|---|---|---|
| iPhone / iPad | iOS / iPadOS 26.0以上 | 端末・USBストレージなどのフォルダー、DLNA |
| Mac Catalyst | macOS 26.0以上 | Mac上のフォルダー・外部ストレージ、DLNA |
| Apple TV | tvOS 26.0以上 | DLNA |

端末・Mac上の対象拡張子は `.mp4` / `.m4v` / `.mp3` / `.flac` / `.m4a` / `.aac` / `.wav` / `.ogg` / `.opus` です。DLNAではMP4／M4Vを対象とします。実際に再生できる形式はOSと端末に依存します。

USB再生には、端末がストレージを認識し、標準のファイル画面から対象フォルダーを選択できる必要があります。DLNA再生には、NASなどのメディアサーバーと同じLANへの接続、ローカルネットワークへのアクセス許可が必要です。

## 使い方

### 端末・USB・Macのファイルを再生する

1. ホームの「OP / EDを選ぶ」→「フォルダーを追加」→「端末のフォルダー」を選びます。
2. 標準のファイル画面で対象フォルダーを選択し、アクセスを許可します。登録だけでは再生は始まりません。
3. 保存済み一覧で登録したフォルダーを開き、再生を開始する動画・音声ファイルを選びます。

選択したファイルから、同じフォルダー直下のメディアをOP／ED順に連続再生します。サブフォルダーは一覧から開けます。フォルダーの登録は次回起動後も保持され、長押し、またはiPhone / iPad / Macの左スワイプで解除できます。

iPhone / iPadでは、ホーム右上の歯車から「設定」を開き、「標準ファイルダイアログを使う」で選択画面を切り替えられます。初期設定はアプリ内一覧です。

### DLNAサーバーから再生する

1. NASのメディアサーバーを起動し、対象フォルダーをメディアインデックスに登録します。
2. 「OP / EDを選ぶ」→「フォルダーを追加」→「DLNAサーバー」を選びます。Apple TVでは「フォルダーを追加」から接続画面を開きます。
3. NASのIPアドレスまたはホスト名を入力し、「接続」を選びます。初回のローカルネットワークアクセスを許可してください。
4. 対象フォルダーを開き、「このフォルダーを登録」を選びます。保存済み一覧に戻り、登録したフォルダーから動画を選びます。

Synologyでは通常、一覧取得にポート50001を使います。DSM管理画面のURLや共有フォルダーのパスでは接続できません。通常のiPhone / iPad実機ビルドとApple TVではアドレスを指定して接続します。接続設定やエラーの詳細は [DLNA仕様](docs/spec.md#dlna再生synologyメディアサーバー) を参照してください。

### 再生を操作する

| 環境 | 再生／一時停止 | 前／次のファイル | 10秒巻き戻し／早送り |
|---|---|---|---|
| iPhone / iPad | 映像中央をタップ | 右／左スワイプ | 映像の左／右をタップ |
| Mac | 映像中央をクリック、またはSpace | ←／→ | 映像の左／右をクリック、またはShift＋←／→ |
| Apple TV | Siri Remoteの再生／停止ボタン | 映像表示中に左／右スワイプ | 操作ボタンから実行 |

iPhone / iPad / Macでは、一時停止すると「ホームに戻る」「OP / EDを選び直す」「メディア情報」などの操作ボタンが表示されます。「OP / EDを選び直す」で一覧を開き、「キャンセル」で元の動画へ戻れます。Apple TVでは、リモコンの戻る操作で直前のDLNA一覧へ戻れます。

最後のファイルで再生は終了します。リピートや再生位置の永続保存はありません。

## ビルドと検証

macOSと、本プロジェクトのSwift構文・各OSのSDKに対応するXcodeが必要です。一部のテストと合成素材の生成にはPython 3、動画素材の生成にはFFmpegを使用します。

`ContinuousPlayer_for_iOS.xcodeproj` をXcodeで開き、次のスキームと実行先を選んでRunします。実機では開発チーム・署名の設定が必要です。

| 版 | スキーム | 実行先 |
|---|---|---|
| iPhone / iPad | `ContinuousPlayer_for_iOS` | 実機またはiOS Simulator |
| Mac Catalyst | `ContinuousPlayer_for_iOS` | My Mac (Mac Catalyst) |
| Apple TV | `ContinuousPlayer_for_tvOS` | 実機またはtvOS Simulator |

コマンドラインでのiOSシミュレーター向けビルド：

```sh
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj \
  -scheme ContinuousPlayer_for_iOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ContinuousPlayer-build \
  build CODE_SIGNING_ALLOWED=NO
```

Mac Catalystのローカル開発用ビルドと起動：

```sh
./script/build_and_run.sh
```

macOS上での基本テスト：

```sh
sh scripts/test-enumeration.sh
sh scripts/test-playback.sh
sh scripts/test-playback-integration.sh
sh scripts/test-dlna.sh
```

UIテスト、合成素材の生成、追加のビルド・署名設定は [アプリケーション仕様](docs/spec.md) を参照してください。ビルドだけでは実機のアプリは更新されません。端末への反映にはXcodeのRun、または別途インストールが必要です。

## ドキュメント

- [アプリケーション仕様](docs/spec.md)：ファイル選択、並べ替え、再生制御、DLNA、Mac／tvOSの詳細
- [ファイル・形式の実機検証](docs/device-validation.md) ／ [実機仕上げ・UIテスト](docs/device-finishing.md)
- [DLNA検証記録](docs/dlna-validation.md)
- [Mac Catalyst検証記録](docs/catalyst-validation.md)
- [tvOS検証記録](docs/tvos-validation.md)

検証記録は各OS・端末・サンプルでの結果です。すべての環境での動作を保証するものではありません。
