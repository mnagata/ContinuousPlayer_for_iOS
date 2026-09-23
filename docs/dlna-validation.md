# DLNA実装・検証記録

検証日: 2026-09-23

## 実装範囲

- IPv4 SSDP M-SEARCHによるMediaServer検出。約5秒、2回送信、キャンセル時にソケットを閉じる。
- デバイス記述の取得、ContentDirectoryサービスとURLBase／相対URLの解決。
- SOAP BrowseとDIDL-Lite解析。ページ取得、フォルダー階層、タイトル、配信URL、ファイルサイズ。
- MP4／M4VのHTTP配信をAVPlayerに渡し、既存の再生・シーク・連続再生を使用。
- NASのタイトルによるOP／ED整列。拡張子なし・ピリオド入りタイトルにも対応。
- ローカルネットワーク用途説明、LANのHTTP許可、承認後に選択できるMulticast Networkingの署名設定。
- SynologyのIPアドレス／ホスト名から直接HTTP接続。任意のDLNAデバイス記述URLも入力可能。成功した接続先を1件保存して再接続。通常の実機ビルドは未承認の自動検索を実行しない。

## 自動検証

- シミュレーター向けDebugビルド: 成功（コード署名なし）。
- 実機向けDebugビルド: 通常の `App.entitlements` に分離後、既存プロファイルでコード署名まで成功（`generic/platform=iOS`）。初回は未承認のMulticast Networking権限を必須にしていたため署名エラーを再現し、修正。実機へのインストールは行っていません。
- `scripts/test-dlna.sh validation/fixtures/09_h264.mp4`: 成功。
  - IP・ホスト名・ポート・IPv6・完全なURLからの接続URL生成、不正なアドレスの拒否。
  - デバイス記述、名前空間、XMLエスケープ、URLBase、相対URL、SSDP応答。
  - MIMEタイプ・複数リソース・拡張子なしURL、OP／ED整列。
  - 接続失敗・タイムアウト・DNS・ネットワーク・TLSのエラー分類と対処案内。模擬サーバーのHTML、HTTP 403／404／503も確認。
  - HTTPの一覧分割取得、対象外ファイルを含む開始位置、空フォルダー。
  - SOAP Fault、HTTPエラー、不正XML、重複ページ、更新中の一覧、キャンセル。
  - HTTP動画の読み込み、表示名とサイズ、前後移動、シーク、自然な連続再生、アクセス失敗。
- `scripts/test-dlna.sh validation/fixtures/11_h264.m4v`: 成功。M4VのHTTP再生と、拡張子なし・ピリオド入りタイトルの並べ替えも確認。
- 既存の `test-enumeration.sh`、`test-playback.sh`、`test-playback-integration.sh`: 成功。
- `scripts/test-dlna-ui.sh`: iPhone 18 Pro / iOS 27.0 Simulatorで成功。
  - ホームからDLNA画面へ移動。
  - 実機の通常ビルドと同じ自動検索なしのモードで、模擬NASのアドレス `127.0.0.1:18765` だけを入力し、サーバー一覧から選択。
  - 自動検索の再検索ボタンを表示しないこと、IP入力の案内があることを確認。
  - Web管理画面を模したHTML応答で、DLNAの情報がない旨・対処方法・実際の接続先を表示。入力消去後に正しいアドレスで接続し直せることを確認。
  - OP → EDの動画連続再生、末尾停止。
  - 同じDLNA一覧への復帰、再選択後にホームへ復帰。
  - アプリ再起動後に接続先を復元して再接続。保存した接続先の削除も確認。
  - 保存した一覧・再生画面のスクリーンショットを目視確認。

模擬サーバーは127.0.0.1のみで待ち受け、テスト終了時に停止します。UIテストはポート18765を使用します。テスト用サーバーへの接続はNASや外部サービスを使用しません。

## 実際のLAN／NASでの読み取り確認

macOS上で、アプリと同じDLNADiscovery・DLNAClient・PlaybackControllerをコンパイルして実行しました。

- SSDPの応答を4件受信。
- Synology `DS420j` のデバイス記述とルート3項目を取得。
- 自動検索を呼ばず、確認済みのNASのIPアドレスだけから `/desc/device.xml` へ直接HTTP接続し、ルート3項目を取得する経路も成功。IPアドレスはアプリへ固定値として組み込んでいません。
- 複数階層のBrowse成功。200件を超えるフォルダー一覧も取得。
- 動画カテゴリ配下で対応リソースを2件取得。
- そのうち1件をAVPlayerへ渡し、メタデータ取得・preroll・readyToPlayまで成功。
- 映像情報: H.264（avc1）、704 × 480、29.97 fps。
- 再生準備のみ確認し、一時停止・ミュート状態を維持。NASのファイル・設定は変更していません。

NASのDSMバージョンはユーザー申告の7.4.1を前提としています。管理APIでバージョンを取得したものではありません。

## 残る実機確認と制約

- AppleのMulticast Networking承認、App ID・プロビジョニングへの反映は未実施。通常ビルドではこの権限を要求しません。承認後に `Configuration/DLNAMulticast.entitlements` と `DLNA_MULTICAST_ENABLED=YES` を併用する方式です。通常の実機ビルドではInfo.plistの `DLNAMulticastEnabled` が `NO` に展開されることも確認しました。設定ファイルの追加だけでは権限は付与されません。
- iPhone／iPad実機のローカルネットワーク許可、SSDP送受信、NASからの連続再生・シーク・Wi-Fi切断後の復帰は未確認。
- macOSでのNAS再生準備、Simulatorでの模擬HTTP再生の成功は、実機検証を代替しません。
- IPv6 SSDP、バックグラウンド検索、再生履歴保存、サーバー側変換、DTCP-IP／DRM、外部レンダラー制御は対象外です。
- ツール環境の `xcode-select` はCommandLineToolsを指していたため、Xcodeパスを `DEVELOPER_DIR` で明示しました。システム全体のXcode選択は変更していません。UIテストの後処理で診断収集の警告がありましたが、テスト自体は成功しています。
