# ContinuousPlayer for iOS

TVアニメのOP/EDを中心に、フォルダー内の動画・音声を連続再生するiPhone / iPadアプリです。SwiftUIとAVFoundationで実装しています。

## 主な機能

- 選択したファイルから、同じフォルダー直下のメディアを連続再生
- DLNAメディアサーバーの検索・フォルダー閲覧・MP4／M4Vの連続再生
- ファイル名に応じたOP/EDの並び替え
- USBストレージなどのフォルダーへのアクセス許可を保存・復元
- サブフォルダーを移動できるアプリ内一覧と、標準ファイルダイアログの切り替え
- タップ・スワイプ・外部キーボードによる再生操作
- ファイル情報・映像／音声形式・現在の音声出力設定の表示
- iPhone / iPadの縦画面・横画面に対応

## 動作環境

- iOS / iPadOS 26.0以上
- 対象端末：iPhone / iPad
- USB再生には、端末が外部ストレージを認識し、標準の「ファイル」画面から対象フォルダーを選択できる必要があります。
- 再生できるコンテナー・コーデックはOSと端末に依存します。対象拡張子でも、すべてのファイルの再生を保証するものではありません。

## 起動とファイル選択

初期画面は濃紺・シアン・紫を基調とし、ロゴ、アプリ名、「ANIME OPENINGS / ENDINGS」、アクセス許可とファイル選択のボタンを表示します。

1. 「USBストレージへのアクセスを許可」を押します。
2. 標準のファイル画面で対象フォルダーを開き、右上の「開く」を押します。この操作では許可の保存だけを行い、再生は開始しません。
3. 「OP / EDを選ぶ」を押します。
4. 再生を開始する動画・音声ファイルを選択します。
5. 同じフォルダー直下の対象ファイルを並べ替え、選択位置から再生します。

保存したアクセス許可は次回起動時にも使用します。別の許可範囲のファイルを再生する場合や、保存した許可を使用できない場合は、ホームで対象フォルダーを許可し直してください。

### ファイル選択画面

ホーム右上の歯車から「設定」を開き、「標準ファイルダイアログを使う」で切り替えます。設定は次回起動時にも保持します。

- **オフ（初期設定）**：検索窓のないアプリ内一覧。許可したフォルダー内でサブフォルダーを開き、「上のフォルダー」で親へ戻れます。許可したルートより上には移動できません。
- **オン**：標準ファイルダイアログ。許可したフォルダー、またはその配下のファイルを選択します。

アプリ内一覧では、親へ戻ったときに直前の子フォルダーへスクロールします。同じ起動中にファイルを選び直す場合は、直前に再生したフォルダー・ファイルの位置を使用します。アプリ再起動後は保存したアクセス許可のフォルダーから始まり、再生履歴や再生位置は復元しません。

## DLNA再生（Synologyメディアサーバー）

ホーム右上の歯車から「設定」を開き、「DLNA機能を使う」でON／OFFを切り替えられます。初期設定はONです。OFFにすると「DLNAサーバーから選ぶ」ボタンが非表示になり、DLNAへの接続は行いません。設定は次回起動時も保持されます。保存済みのNAS接続先は削除しません。

DSM 7.4.1のSynology「メディアサーバー」を接続対象として、標準UPnP AVのクライアント機能を実装しています。同じLAN内のDS420jで、macOS上のクライアントによるサーバー検出・階層一覧取得・H.264動画の再生準備を確認しました。iPhone／iPad実機でのNAS再生確認は残っています。詳細は [DLNA検証記録](docs/dlna-validation.md) を参照してください。

1. NASとiPhone／iPadを同じLANに接続します。
2. NASのメディアサーバーを起動し、対象フォルダーをメディアインデックスに登録します。DMAのデバイス一覧で、新しい端末へのアクセスが制限されていないか確認してください。
3. アプリのホームで「DLNAサーバーから選ぶ」を押します。「Synology NASに接続」にNASのIPアドレスまたはホスト名を入力し、「接続」を押します。初回のローカルネットワークアクセスを許可してください。
4. 表示されたNAS → 公開フォルダー → 動画を選びます。選択した動画から同じ階層のMP4／M4VをOP／ED順に連続再生します。
5. 「OP / EDを選び直す」で直前のDLNAフォルダーに戻ります。「ホームに戻る」でDLNA画面を閉じます。

DLNAのフォルダー構成・タイトルはNASが公開する一覧に従います。DSMの共有フォルダー一覧そのものとは異なる場合があります。並べ替えと再生中の名前表示にはNASのタイトルを使います。フォルダー名が「2025冬」「2025年春」などの年＋季節で終わる場合は、USBの一覧と同じく、同じ名前の接頭辞ごとに年の昇順・冬→春→夏→秋の順に並びます。URLに拡張子がない場合も、配信リソースのMIMEタイプからMP4／M4Vを判定します。対応リソースがないファイルは表示しません。DLNAサーバー側でインデックス対象外となるファイルも表示されません。

再生可能なコーデックはAVPlayer・OS・端末に依存します。DSM 7.2.2以降のメディアサーバーでは動画変換が廃止されているため、NASの変換には依存しません。シークの可否はNASのHTTP Range対応などにも依存します。

- 検索はIPv4 SSDP（UDP 239.255.255.250:1900、約5秒）。バックグラウンド検索・IPv6 SSDP・インターネット越しの探索には対応していません。
- 一覧はContentDirectoryのBrowseを200件ずつ要求し、NASが返す件数に従って全ページを取得します。取得中の一覧変更、無限に同じページを返す応答などはエラーとして再読み込みを案内します。
- HTTPエラー・読み込み待ち・再生停滞を表示します。再生失敗時は従来と同様に次へ進み、3件連続または末尾の失敗で停止します。接続を復旧した後は再生ボタン、または一覧の再読み込みからやり直せます。
- 直接接続に成功したアドレスを1件保存し、次回DLNA画面を開いた際に再接続します。「保存した接続先を削除」で消せます。閲覧位置・再生履歴はアプリ再起動後には保存しません。
- SynologyのIPアドレス／ホスト名を入力すると、`http://<NAS>:50001/desc/device.xml` へ直接接続します。`NAS:ポート` も指定できます。SSDPのマルチキャスト権限は不要ですが、ローカルネットワークへのアクセス許可は必要です。
- 同じ入力欄に、ほかのDLNAサーバーのデバイス記述XMLのHTTP(S) URLも入力できます。DSMの管理画面URLや共有フォルダーのパスは使用できません。
- 通常の実機ビルドでは自動検索を実行せず、アドレス入力を案内します。自動検出の権限を含むビルドやシミュレーターでは、検索結果と「再検索」も表示します。

### DLNA接続エラーの表示

接続前に、入力から決まる接続先とポート番号を表示します。Synologyの通常の一覧取得ポートは50001です。5000／5001は通常DSM管理画面用なので、入力した場合はその違いを案内します。独自のポート設定は妨げず、指定したポートへ接続します。

接続失敗時は、ポートへの接続失敗、応答タイムアウト、名前解決失敗、ネットワーク接続不可、HTTPSの問題、HTTPステータス、DLNA情報を含まない応答を区別し、確認すべき内容を日本語で表示します。ネットワーク接続不可だけでは、Wi-Fi切断とローカルネットワーク権限の拒否は断定しません。「接続エラーの詳細」を開くと、実際に試した接続先とエラー情報を選択・コピーできます。

Xcodeコンソールの `TUIPredictionViewCell` / `TUICandidateGradientContentLabel` に関する制約警告は、キーボードの予測候補欄に関するものです。そのログだけではDLNAの接続失敗原因は分かりません。接続の診断には、アプリ画面のエラーと接続先を使用してください。

参考: [Synologyのネットワークポート一覧](https://kb.synology.com/en-eu/DSM/tutorial/What_network_ports_are_used_by_Synology_services)。

### 実機署名とネットワーク設定

Debug／Releaseの通常ビルドは、追加の制限付き権限を要求しない `Configuration/App.entitlements` を使います。既存の署名プロファイルでビルドでき、USB再生と、NASのアドレスを指定したDLNA接続を利用できます。実機のSSDP自動検出には、Apple DeveloperでMulticast Networkingの承認・App IDへの有効化と、その権限を含むプロビジョニングプロファイルが別途必要です。

承認後は、アプリターゲットのBuild SettingsでCode Signing Entitlementsを `Configuration/DLNAMulticast.entitlements`、ユーザー定義設定 `DLNA_MULTICAST_ENABLED` を `YES` に変更します。権限と画面上の自動検索を両方有効にする必要があります。コマンドラインでは `xcodebuild` に `-xcconfig Configuration/DLNAMulticast.xcconfig` を追加すると、これらをまとめて指定できます。設定変更だけではApple側の権限は付与されず、未承認のプロファイルでは署名エラーになります。

`Configuration/App-Info.plist` にローカルネットワークの用途説明と `NSAllowsLocalNetworking` を追加しています。LAN内のIPアドレス／ローカル名へのHTTPを許可し、アプリ全体のATSは無効化しません。一般のドメイン名によるHTTP配信には別途サーバーに合わせた設定が必要になる場合があります。

参考: [Appleのローカルネットワーク仕様](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[Synologyメディアサーバーのリリースノート](https://www.synology.com/en-us/releaseNote/MediaServer?os=DSM&version=7_x_series)。

## 対象ファイルと再生順

対象拡張子：

`.mp4` / `.m4v` / `.mp3` / `.flac` / `.m4a` / `.aac` / `.wav` / `.ogg` / `.opus`

- 大文字小文字を区別しません。
- プレイリストの対象は、選択したファイルと同じフォルダー直下の通常ファイルです。サブフォルダーの再帰スキャンは行いません。
- macOSが作る `._作品 OP.mp4` など、名前が `._` から始まるメタデータファイルは除外します。ファイル自体は削除しません。
- 通常の隠しファイルは、対象拡張子なら含めます。

基本は端末のロケールに従う名前順です。拡張子を除いた名前が「作品名＋空白＋OPまたはED＋任意の番号」に一致する場合、同じ作品の該当ファイルを次の順に並べ替えます。

```text
作品 OP → 作品 ED → 作品 OP2 → 作品 ED2 → 作品 OP3 → 作品 ED3
```

番号省略は1として扱います。該当ファイル同士の位置だけを入れ替え、それ以外のファイル位置は維持します。本編をOPとEDの間へ挿入する機能はありません。OS間で名前の照合順が完全に一致するとは限りません。

最終ファイルで再生が終了します。終了後に再生すると最終ファイルを先頭から再生し直します。リピート・クロスフェードは実装しておらず、ギャップレス再生も保証しません。

## タッチ操作

| ジェスチャー | 動作 |
|---|---|
| シングル / ダブルタップ：映像領域の左1/3 | 10秒巻き戻し |
| シングル / ダブルタップ：映像領域の中央1/3 | 再生 / 一時停止 |
| シングル / ダブルタップ：映像領域の右1/3 | 10秒早送り |
| 右スワイプ | 前のファイル |
| 左スワイプ | 次のファイル |

巻き戻しは先頭までです。早送りで末尾に達すると次のファイルへ進み、次がなければ何もしません。前後のファイルへ移動すると、そのファイルの先頭から始まります。一時停止中の前後移動では停止状態を維持します。

## キーボード操作

外部キーボードを接続した場合に使用できます。

| キー | 再生画面の操作 |
|---|---|
| ← / → | 前 / 次のファイル |
| Space | 再生 / 一時停止 |
| Shift＋← / → | 10秒巻き戻し / 早送り |
| ↑ / ↓ | アプリ内の再生音量を5ポイントずつ増減（0〜100%） |
| I | メディア情報を表示 |
| I / Esc（情報画面） | メディア情報を閉じる |

アプリ内の再生音量は端末のシステム音量とは別です。

## 再生画面と情報表示

再生画面は全画面表示で、AVPlayerLayerを使って映像を表示します。音声ファイルでは波形マークを表示します。再生準備中・バッファリング中は状態を画面に表示します。

縦画面では下部にファイル名・サイズ・映像形式・解像度・フレームレート・音声形式・出力情報を表示します。一時停止中は上部にファイル名と次のボタンを表示し、前後移動やシークのボタンも利用できます。

- **ホームに戻る** — 再生を終了して初期画面へ戻る
- **OP / EDを選び直す** — 再生を終了してファイル選択画面を開く
- **メディア情報** — ファイル・メディア形式・音声出力の詳細を表示
- **再生** — 再生を再開

再生終了時・エラー時・VoiceOver有効時にも操作ボタンを表示します。横画面では操作ボタンの表示に合わせて下部パネルを表示します。再生画面がアクティブな間は画面の自動スリープを抑止します。

### 中断と再開

アプリの非アクティブ化、バックグラウンドへの移行、通話などの割り込み、音声出力機器の切断時には一時停止します。復帰後は再生ボタンで手動再開します。バックグラウンド再生や、再生位置・履歴の永続保存はありません。

### 音声出力

情報画面に、AVAudioSessionが報告する現在の出力デバイス・サンプルレート・チャンネル数を表示します。ビットパーフェクト出力を指定する機能はなく、表示値も実出力のビット一致を保証するものではありません。

## 再生エラーとストレージアクセス

- 通常の読み込み・再生失敗は、次のファイルがあればスキップします。連続3件の失敗、または末尾の失敗で停止し、理由を表示します。
- 正常に再生時間が進むと、連続失敗のカウントをリセットします。
- 準備待ちと再生停滞は30秒で失敗処理へ進みます。再生中に2秒間進行しなければバッファリング表示になります。
- 権限拒否やデバイス不在として判定できるアクセスエラーでは、再生を停止してフォルダーの再選択を案内します。
- USB取り外し時の通知・エラーはファイルプロバイダーに依存します。バッファ済み部分が再生できる間の切断を即時検出するとは限りません。

## ビルドと検証

macOSと、本プロジェクトのSwift構文・iOS SDKに対応するXcodeが必要です。統合テストと合成素材の生成にはPython 3も使用します。

1. `ContinuousPlayer_for_iOS.xcodeproj` をXcodeで開きます。
2. `ContinuousPlayer_for_iOS` スキームと実行先のiPhone / iPad、またはシミュレーターを選択します。
3. 実機の場合はSigning & Capabilitiesで開発チーム・署名を設定し、Runします。

コマンドラインでのシミュレーター向けビルド：

```sh
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj \
  -scheme ContinuousPlayer_for_iOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ContinuousPlayer-build \
  build CODE_SIGNING_ALLOWED=NO
```

macOS上でのテスト：

```sh
# ファイル列挙・拡張子判定・OP/ED整列
sh scripts/test-enumeration.sh

# プレイリストと再生状態
sh scripts/test-playback.sh

# AVFoundationによる連続再生・シーク・中断・エラー処理
sh scripts/test-playback-integration.sh

# DLNAのXML・HTTP・ページ取得・エラー・キャンセル・HTTP連続再生
sh scripts/test-dlna.sh

# 生成済みのMP4でHTTP再生を検証
sh scripts/test-dlna.sh validation/fixtures/09_h264.mp4
```

DLNAのシミュレーターUIテスト（起動済み端末を指定、生成済みMP4が必要）：

```sh
SIMULATOR_ID=<起動済みシミュレーターUDID> sh scripts/test-dlna-ui.sh
```

テストはループバック上の模擬サーバーを使用し、NASへの変更は行いません。UIテストは専用ポート18765を使用します。SSDPマルチキャストの実機送受信、ローカルネットワーク許可、Synologyの公開形式・シークは別途実機確認が必要です。

接続した実機でのUIテスト：

```sh
DEVICE_ID=<端末UDID> sh scripts/test-device.sh
```

実機テストは `DeviceValidation` スキームを使用し、合成音声をアプリ内の `Documents/UIFixtures` へ転送します。既定のビルド先・結果バンドルは `/tmp` 内です。`BUILD_DIR` と `RESULT_BUNDLE` で変更できます。各テストスクリプトのXcodeパスは `DEVELOPER_DIR` で指定できます。

動画を含む合成素材を追加生成する場合：

```sh
# FFmpegが必要。PATHにない場合はFFMPEG=/path/to/ffmpegを指定
python3 scripts/generate-fixtures.py

# 生成した動画を使った追加の統合テスト
sh scripts/test-playback-integration.sh validation/fixtures/09_h264.mp4
```

素材生成にはFFmpegのlibx264 / libx265 / libopus / libvorbis / libmp3lameが必要です。生成先は `validation/fixtures/` です。

ビルドだけでは実機のアプリは更新されません。端末への反映にはXcodeのRun、または別途インストールが必要です。macOSでのテスト成功と、実機のUSBアクセス・デコード・音声出力の確認は別です。

### 検証記録

実機検証ではiPad Pro 12.9インチ（第5世代）・iPadOS 27.0を使用しています。OGG / Opusを含む形式の結果は、そのOSと検証サンプルに対する結果です。最低対応OSの26.0を含め、すべての環境での確認を意味しません。

- [ファイル・形式の実機検証](docs/device-validation.md)
- [実機仕上げ・UIテストの記録](docs/device-finishing.md)
- [UI仕様と追加検証](docs/ui.md)

各記録は作成時点の内容を含みます。開始直後のカクつき対策については、USB実機での改善確認が残っています。

## プロジェクト構成

```text
ContinuousPlayer_for_iOS/
├── ContinuousPlayer_for_iOSApp.swift  # アプリ起動、Debug検証モード
├── ContentView.swift                 # ホーム、アクセス許可、画面遷移
├── DLNADiscovery.swift               # SSDPによるサーバー探索
├── DLNAClient.swift                  # デバイス記述・SOAP・DIDL-Lite解析
├── DLNABrowser.swift                 # DLNAサーバー・フォルダー選択
├── MediaFileBrowser.swift            # 許可範囲内のファイル一覧
├── MediaLibrary.swift                # フォルダーアクセス、ブックマーク
├── MediaScanner.swift                # ファイル列挙・拡張子判定
├── PlaylistSorter.swift              # OP/ED整列
├── PlaybackState.swift               # プレイリストと再生意図
├── PlaybackController.swift          # AVPlayer、再生・シーク・中断制御
├── PlaybackSurface.swift             # 映像表示、キーボード入力
├── PlayerScreen.swift                # 再生画面、操作、情報表示
├── MediaInfo.swift                   # メディア情報取得
├── MediaValidationSession.swift      # Debug用の形式・再生検証
├── ValidationView.swift              # Debug用の検証画面
├── Assets.xcassets/                  # アイコン、ロゴ、配色
└── LaunchScreen.storyboard           # 起動画面
```

- `Configuration/`：アプリのInfo.plist設定
- `tests/`：macOS上で実行するSwiftテスト
- `DeviceUITests/`：実機UIテスト
- `scripts/`：テスト・合成素材生成・デザイン資産生成
- `docs/`：仕様と検証記録

### 技術スタック

- Swift、SwiftUI、Observation
- AVFoundation（AVPlayer / AVPlayerLayer）、AVAudioSession
- UIKit（UIDocumentPickerViewController、キーボード入力）
- Foundation（NSFileCoordinator、フォルダーブックマーク）
- Xcodeプロジェクト、XCTestによるUIテスト

詳細は [列挙と整列](docs/enumeration-and-sorting.md)、[連続再生](docs/continuous-playback.md)、[状態管理](docs/state-management.md) を参照してください。

## Apple TV / tvOS版

`ContinuousPlayer_for_tvOS` ターゲット／共有スキームで、tvOS 26.0以降のApple TVに対応しています。
再生処理、DLNA通信、OP／ED順と季節フォルダーの並べ替えはiOS版と共通です。
テレビ向けのホーム画面、再生画面、アプリアイコンとトップシェルフ画像を追加しています。

### 接続と再生

1. Apple TVとNASを同じネットワークに接続します。
2. 「DLNAサーバーから選ぶ」を開き、NASのIPアドレスを入力して「接続」を選びます。
3. サーバー → フォルダー → 動画の順に選択します。選んだ動画から同じ階層のMP4／M4VをOP／ED順に連続再生します。

接続に成功したNASのアドレスは保存され、次回一覧を開くと再接続します。
初期版はアドレス指定での接続のみです。SSDP自動検索、USBストレージ、標準ファイルダイアログには対応しません。
コーデックの対応範囲はApple TVとOSに依存し、NASでの変換には依存しません。

### Siri Remoteの操作

| 操作 | 動作 |
|---|---|
| 再生／停止ボタン | 再生／一時停止。一時停止時は操作ボタンを表示 |
| 映像表示中の左スワイプ | 前の動画（prev） |
| 映像表示中の右スワイプ | 次の動画（next） |
| 映像表示中の左右タップ／左右ボタン | 反応しない |
| 映像表示中の選択・上下 | 操作ボタンを表示 |
| 操作ボタン表示中の方向・選択 | ボタンを選んで実行。前後の動画、10秒シーク、情報表示など |
| 戻る（旧リモコンのMenu） | 映像表示中は操作表示、操作表示中は直前のDLNA一覧へ戻る |
| 「映像に戻る」 | 再生を続けたまま操作ボタンを閉じる |

リモコンの戻る操作で親フォルダーへ戻ると、直前に開いていたフォルダーが画面中央付近に表示され、その行に選択が戻ります。複数階層でも親フォルダーごとに位置を記憶します。再生画面から一覧へ戻った場合も、選択したファイルの位置を復元します。位置の記憶はブラウザーを開いている間のみで、アプリ再起動後には保存しません。

最後の動画で停止します。エラー時の次ファイルへの移動と連続失敗時の停止はiOS版と共通です。
非アクティブ化や音声の割り込み時は一時停止し、復帰後は手動で再開します。

### ビルドと検証

Xcodeで `ContinuousPlayer_for_tvOS` スキームとApple TVの実機またはシミュレーターを選択します。
実機ではtvOS用の署名設定が必要です。iOS版とは別のBundle IDを使用します。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ContinuousPlayer_for_iOS.xcodeproj \
  -scheme ContinuousPlayer_for_tvOS \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath /tmp/ContinuousPlayer-tvOS build CODE_SIGNING_ALLOWED=NO

# ローカル模擬NASと合成動画を使ったSiri Remote操作・連続再生テスト
SIMULATOR_ID=<Apple-TVシミュレーターUDID> sh scripts/test-tvos-ui.sh
```

実機のNAS接続、ローカルネットワーク許可、HDMI音声と実際のSiri Remoteの操作感は、Apple TV実機で別途確認してください。
アイコン画像は既存のベクター図形を使い、`scripts/generate-tv-brand-assets.swift` で再生成できます。
