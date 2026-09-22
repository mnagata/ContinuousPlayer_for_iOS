# ファイル・形式の実機検証

## 検証範囲

開発プランの第1段階。完成版プレイヤーではなく、Filesのフォルダー選択、直下列挙、ブックマーク保存・復元、AVFoundationによる形式判定、再生・シークを実測する検証画面を追加した。OP/ED整列や完成版のエラースキップは後続工程。

- 実機: iPad Pro 12.9インチ（第5世代）、iPadOS 27.0（24A437）。
- 現行の最低OS 27.0を維持。下位OSの互換性は未検証。
- 元素材: `/Volumes/V-Drive/Video/OPED集/アニメOPED 2026年春`。
- 全81本、合計5,278,665,132 bytes。全てMP4 / H.264 High / AAC LC / 48 kHz stereo。
- 1920×1080が40本、1440×1080（SAR 4:3、表示16:9）が41本。
- 各解像度のサイズ最小・最大、計4本を変換せず実機へコピー。元素材は読み取りのみ。
- 全ファイルのメタデータは `validation/source-codecs.json`、サイズ一覧は `validation/source-inventory.json`。

## 2026-09-19 実測結果

実機ログ: `validation/device-log.txt`。集計: `validation/summary.json`。素材のSHA-256: `validation/sample-manifest.json`。

| 素材 | 実測結果 |
|---|---|
| WAV PCM、M4A AAC、ADTS AAC、FLAC、M4A ALAC、Ogg Opus、Ogg Vorbis、MP3 | 全8サンプルで読み込み・再生時間進行・シーク成功 |
| MP4 H.264、MP4 HEVC、M4V H.264 | 全3サンプルで上記に加えデコード済み映像フレーム取得成功 |
| 大文字.WAV、通常の隠し.wav | 列挙・再生・シーク成功 |
| 壊れたMP4 | AVFoundation -11829を記録し、検証完了まで到達 |
| 実素材4本 | 全て読み込み・再生時間進行・映像フレーム取得・10秒シーク成功 |

正常素材17件の自動計測が成功。OGG／Opusの結果はこのiPadOS 27.0と当該サンプルに限定する。全81本の実機再生を確認したわけではない。

Debugの実機向け署名付きビルド・インストール・起動に成功。実機スクリーンショットで検証画面の表示も確認した（`validation/device-screen.png`）。iOS 27 SDKでAVPlayerItemVideoOutputの旧APIに非推奨警告が2件あり、ビルドエラーはない。

実素材4本: こめかみっ！Girls ED、ポンコツ風紀委員とスカート丈が不適切なJKの話 ED、リィンカーネーションの花弁 ED、黄泉のツガイ ED。

通常隠しファイルと大文字拡張子の列挙、非メディア／サブフォルダー内メディアの除外を確認した。`._`サンプルはディレクトリ転送時に転送されていない可能性があるため、その除外をこのログだけで実機確認済みとはしない。

## 計測の詳細

1. `AVURLAsset`のisPlayable、duration、トラックのFourCCを記録。
2. AVPlayerItemのreadyToPlayを待ち、2秒間の再生時間進行を測定。
3. 映像トラックありの場合、AVPlayerItemVideoOutputでデコード済みフレーム取得を試行。
4. 素材の中間または10秒の短い方へシークし、目標との誤差0.15秒以内を確認。
5. アプリのDocuments/validation-log.txtに日時付きで追記。画面から共有可能。

APIでの再生判定、再生時間の進行、フレーム取得は、目視・聴取による正常な映像・音声、全編の再生、A/V同期を保証しない。

## 再現手順

`FFMPEG=/path/to/ffmpeg python3 scripts/generate-fixtures.py`で6秒の合成サンプルを生成する。FFmpegのlibx264/libx265/libopus/libvorbis/libmp3lameが必要。

XcodeでContinuousPlayer_for_iOSを実機へRunする。コマンドの場合はDEVELOPER_DIRを`/Applications/Xcode.app/Contents/Developer`に設定し、既存の開発署名でビルドする。端末にデベロッパ信頼設定が必要な場合は、端末の設定画面で行う。

`devicectl device copy to`のappDataContainerドメインで、合成サンプルをDocuments/ValidationFixturesへ、実素材をDocuments/RealSamplesへ転送する。両フォルダーは独立している。起動引数`--validate-fixtures`または`--validate-real-samples`で各検証を開始できる。

## Files経由の手動検証

以下はMacからアプリ内へコピーした素材の再生とは別の検証である。コピー再生成功を外部ストレージやiCloudのアクセス成功として扱わない。

| ケース | 操作・合格条件 | 状態 |
|---|---|---|
| ローカルフォルダー | 「フォルダーを選択」から対象を選び、直下の対象メディアが列挙される | 未検証 |
| 再起動後のアクセス | フォルダー選択後にアプリ終了・再起動。「保存したフォルダーを復元」で再列挙・再生 | 未検証 |
| iCloud取得済み | Filesから選択し列挙・再生 | 未検証 |
| iCloud未取得 | 未ダウンロード素材の読み込み、待機／エラー表示、再試行 | 未検証 |
| 外部ストレージ | iPadに接続したドライブをFilesから選択し再生 | 未検証 |
| USB取り外し・権限失効 | 再生エラーを記録し、再選択で復帰 | 未検証 |
| 選択キャンセル | 現在の画面に戻り、既存フォルダーを失わない | 未検証 |
| 通話・音声割り込み | 再生中／停止中に割り込み。終了後も停止し、再生ボタンで再開 | 未検証 |
| イヤホン切断 | 切断時に停止し、スピーカーで自動再開しない | 未検証 |
| バックグラウンド復帰 | 非アクティブ時に停止。復帰・項目切替後も手動再開まで停止 | 未検証 |
| 再生停滞 | 読み込み後の停滞を表示し、30秒で次項目へ。連続3失敗で停止 | 未検証 |
| 自然終了→次項目 | 素材をタップして再生し、末尾で次ファイルへ遷移 | 未検証 |
| 映像・音声 | 実素材4本の画角、音声、同期を目視・聴取する | 未検証 |

## 実装上の注意

- 対象拡張子はmp4/m4v/mp3/flac/m4a/aac/wav/ogg/opus。大文字小文字を区別しない。
- `._`を除外し、一般の隠しファイルは対象。サブフォルダーは再帰走査しない。
- フォルダーを選択してからアクセスを開始し、別フォルダーへの切替時に終了する。選択中は再生用に保持する。
- iOSではminimalBookmarkを保存する。復元や読み取りに失敗したら再選択を案内する。
- 列挙はNSFileCoordinatorを用いUIスレッド外で実行。クラウドプロバイダーの列挙待ちにキャンセルUIは未実装。
- 検証ログに素材ファイル名が含まれる。実素材コピーと再生成可能な合成ファイルは.gitignore対象。

参考: [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories)、[AVPlayerItem status](https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.property)。

## 実機仕上げの追加結果（2026-09-20）

通常プレイヤーで実機UIテスト7件が成功。ローカルFiles選択・再起動復元、回転、最大文字サイズ、連続再生、ジェスチャー、復帰、実動画4本の画角を確認した。詳細と未確認項目は [実機仕上げ記録](device-finishing.md) を参照。上記の旧チェック表は当初の検証時点の記録。
