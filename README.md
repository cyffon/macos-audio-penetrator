# Audio Penetrator

macOSの入力デバイスから受け取った音声を、選択した出力デバイスへそのまま流すアプリです。SwiftUI、Core Audio、AVFoundationで実装しています。

## 機能

- 入力・出力デバイスの一覧表示と選択
- 「起動する」「停止する」ボタンによる音声転送の開始・停止
- `Default (デバイス名)` によるmacOSのデフォルト入力・出力の使用
- デバイスの接続変更やデフォルト設定の変更に応じた一覧更新
- 転送中のデバイス切り替え

音声転送には`AVCaptureAudioPreviewOutput`を使用します。アプリ独自の音声加工や、音声のファイル保存は行いません。

## 開発環境

- macOS 15.8以降（プロジェクトのDeployment Target）
- Xcode（ビルド確認環境: 27.1）

外部ライブラリのインストールは不要です。

## ビルド・起動

1. `macos-audio-penetrator.xcodeproj`をXcodeで開きます。
2. Schemeに`macos-audio-penetrator`、実行先に`My Mac`を選択します。
3. `⌘R`でビルド・起動します。

ターミナルで署名なしのビルドを確認する場合は、リポジトリのルートで実行します。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project macos-audio-penetrator.xcodeproj \
  -scheme macos-audio-penetrator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/macos-audio-penetrator-build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Xcodeを別の場所にインストールしている場合は、`DEVELOPER_DIR`を変更してください。

## 使い方

1. 「入力先」で音声を受け取るデバイスを選択します。
2. 「出力先」で音声を流すデバイスを選択します。
3. 「起動する」をクリックします。初回はマイクへのアクセスを許可してください。
4. 終了するときは「停止する」をクリックします。ウィンドウを閉じたときも転送を停止します。

`Default (デバイス名)`を選ぶと、その方向のmacOSのデフォルトデバイスを使用します。デフォルト設定を変更すると表示名も更新され、転送中であれば接続を再構成します。選択したデバイスの接続が解除された場合は、選択を`Default`に戻します。

## ファイル構成

ソースコードは`macos-audio-penetrator/`にあります。

| ファイル | 役割 |
| --- | --- |
| `macos_audio_penetratorApp.swift` | アプリのエントリーポイント |
| `ContentView.swift` | ボタン・デバイス選択のUI |
| `AudioRoutingModel.swift` | 画面の状態、マイク権限、転送の起動・停止・切り替え |
| `AudioDeviceCatalog.swift` | Core Audioによるデバイス一覧・名前・UIDの取得と変更監視 |
| `AudioPassthrough.swift` | 専用actorでの音声転送セッションの構成・起動・停止 |

## 音声が出ない場合

- 「システム設定」→「プライバシーとセキュリティ」→「マイク」で、アプリのアクセスが許可されているか確認してください。
- 選択したデバイスの接続、入力・出力の音量、ミュート設定を確認してください。
- エラーや割り込みで停止した場合は、デバイスを確認して再度「起動する」をクリックしてください。

失敗理由はXcodeのデバッグコンソール、またはmacOSの「コンソール」アプリで確認できます。ログのsubsystemは`cyffon.macos-audio-penetrator`、categoryは`AudioRouting`です。

ビルド・実機での音声転送を確認済みです。
