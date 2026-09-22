# ContinuousPlayer_for_iOS

iPhone / iPad 向けの動画・音声連続再生アプリ。SwiftUI と AVFoundation で実装し、iOS / iPadOS 26.0 以降に対応しています。

## 主な機能

- USB ストレージなどのフォルダーへのアクセス許可を保存し、選択したファイルから同じフォルダー内を連続再生。
- ファイル名を基に、同じ作品の `OP → ED → OP2 → ED2` の順に整列。
- サブフォルダーを移動できるファイル一覧と、標準ファイルダイアログの切り替え。
- タップ・スワイプ・キーボードによる再生操作、±10 秒シーク、メディア情報表示。

対象拡張子: `mp4` / `m4v` / `mp3` / `flac` / `m4a` / `aac` / `wav` / `ogg` / `opus`。再生可否はファイル内のコーデックと OS に依存します。バックグラウンドでは一時停止します。

## 使い方

1. 「USBストレージへのアクセスを許可」で対象フォルダーを選択。
2. 「OP / EDを選ぶ」で再生を開始するファイルを選択。
3. 映像中央のタップで再生・一時停止、左右のタップで±10 秒、水平スワイプで前後のファイルへ移動。

## 開発・テスト

Xcode で `ContinuousPlayer_for_iOS.xcodeproj` を開き、`ContinuousPlayer_for_iOS` スキームを実行します。実機では署名設定が必要です。

macOS と Xcode の開発環境で実行:

```sh
sh scripts/test-enumeration.sh
sh scripts/test-playback.sh
sh scripts/test-playback-integration.sh
```

実機 UI テストは `DEVICE_ID=<端末UDID> sh scripts/test-device.sh` で実行できます。仕様・検証記録は [docs](docs/) を参照してください。
