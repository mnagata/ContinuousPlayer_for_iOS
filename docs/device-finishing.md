# 実機での仕上げ（2026-09-20）

## 環境と変更

iPad Pro 12.9インチ（第5世代）、iPadOS 27.0、開発署名付きDebugアプリで検証。対応下限は既存のiOS 27.0を維持。

- Filesの「このiPad内 → ContinuousPlayer」からアプリのDocumentsを扱えるよう、ファイル共有とインプレースアクセスを有効化した。`Configuration/App-Info.plist`をDebug/Release共通で使用。UIFileSharingEnabledは生成ビルド設定だけでは出力されなかったため、生成後のInfo.plistでも確認する。
- 端末に表示するアプリ名をContinuousPlayerへ設定。
- 通常アプリ用スキームと、実機UIテスト用のDeviceValidationスキームを共有化。
- XCTestでピッカー、回転、ジェスチャー、連続再生、復帰を再現できるようにした。
- Debugの`--ui-real-samples`は転送済みのDocuments/RealSamplesを通常プレイヤーに読み込む。`--ui-fixtures`と同様、通常のブックマークを上書きしない。
- 復元テストの`--ui-bookmark-tests`は別のUserDefaultsキーを使う。実際のシステムピッカー、URLブックマーク作成／解決、スコープ開始、通常の列挙・再生を通す。テスト用の起動処理・キーはReleaseに含めない。

## 実機で確認した項目

| 項目 | 確認内容 |
|---|---|
| 再生・一時停止 | 開始ファイルの選択、中央シングル／ダブルタップ、一時停止ツールバー |
| 前後移動 | 停止中の次ボタンと左スワイプ。移動後も停止を維持 |
| シーク境界 | 短い項目で+10秒→次へ。最後の項目では+10秒で終了に変わらない。-10秒操作 |
| 自然終了 | 2秒のOP2→ED2→末尾停止。最後の次ボタン無効 |
| バックグラウンド | 再生中にHome→再アクティブ化。自動再生せず停止表示 |
| 回転 | 再生画面、停止操作、情報画面、ホームの縦横配置 |
| 最大文字サイズ | アプリ起動時の最大アクセシビリティ文字サイズ指定で縦横の操作表示を確認 |
| ローカル選択・復元 | Filesの「このiPad内 → ContinuousPlayer → UIFixtures」を選択し、アプリ終了・再起動後に保存ブックマークから列挙・再生 |
| ピッカーキャンセル | 選択をキャンセルして既存の一覧を維持 |
| 実動画4本 | 各数秒を通常画面で再生し、停止フレームと情報表示を記録。2本は縦、2本は横で撮影 |
| アイコン | 実機から生成済みアイコンを取得。プレースホルダーではないことを確認 |

画面は `validation/finishing/`。`ipad-real-video-1...4.png` と `ipad-real-info-1...4.png` は前工程と同じ4素材。1920×1080と1440×1080/SAR 4:3の両方が16:9で表示されることを確認した。情報画面の解像度はAVFoundationが返す表示サイズで、エンコード時の画素数とは異なる場合がある。

UIテストの合成WAVは無音。スクリーンショットによる画角の確認は、全編再生・音質・A/V同期の聴取確認を意味しない。XCUIScreenで全画面を撮影する（app.screenshotでは実機横画面の切り出しが不正確だった）。

## 最終結果

- 実機UIテスト6件（合成素材5件＋実動画1件）成功: `/tmp/ContinuousPlayerFinishing-run2.xcresult`。
- ローカルピッカー選択・再起動復元テスト1件成功: `/tmp/ContinuousPlayerFinishing-run5.xcresult`。
- 既存の状態・列挙・AVFoundation統合テスト成功。
- Debug開発署名付き実機ビルド／インストール／起動成功。Release署名なしビルド成功。
- `UIFileSharingEnabled`と`LSSupportsOpeningDocumentsInPlace`が生成されたアプリに含まれることを確認。
- テスト後は通常のホーム画面へ戻した。普段の保存済みフォルダーは変更していない。

ログは `validation/finishing/device-ui-tests.log` と `device-folder-tests.log`。Xcode付随の診断収集にはdevicectl探索警告があるが、テスト本体の結果・画面添付は取得できている。

## 再現

```sh
DEVICE_ID=00008103-001914DC1179001E sh scripts/test-device.sh
```

スクリプトは署名付きビルド、アプリ更新、独立したDocuments/UIFixturesへの4本の無音WAV転送、UIテストを実行する。端末は接続・ロック解除・開発者モード有効にする。初回のテストランナー署名はXcodeでチーム設定、または署名用アカウントがある環境で`-allowProvisioningUpdates`を指定する。

RealMediaUITestsにはDocuments/RealSamplesに既存の4素材が必要。未転送ならスキップし、検証済みとは扱わない。元素材を自動で探索・アップロードする処理はない。

## 端末での手動確認が残る項目

- iCloud Driveの取得済み／未取得素材の選択・取得待ち・再試行。
- 外部USBストレージの選択・再起動後の復元・取り外し・再選択。
- イヤホン／USB音声機器の切断、実際の通話などの音声割り込み。
- VoiceOverの実際の読み上げ順とダブルタップ操作。
- iPadのウィンドウサイズ変更、iPhone実機での小画面表示。
- 自動ロック時間を超えたスリープ抑止と、ホーム復帰後の解除。
- コールド起動時の起動画面、全編の音声・映像同期。
- プロバイダー由来の権限失効、実際の30秒停滞と復旧。

割り込み・切断・アクセス失効・停滞の状態遷移は既存のMac上のAVFoundation統合テストで成功しているが、物理機器での発生確認とは区別する。既存のiOS 27非推奨API警告は残る。
