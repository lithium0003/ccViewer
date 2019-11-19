# CryptCloudViewer
iOSアプリ"CryptCloudViewer"のソースコードのレポジトリです。

アプリはこちらからダウンロードできます。
https://itunes.apple.com/jp/app/cryptcloudviewer/id1458528598?mt=8

## 説明
暗号化したまま閲覧できるクラウドビューワです。
クラウドストレージ: Google Drive, Dropbox, OneDrive, pCloud,ドキュメントフォルダ、
暗号化: rclone, CarotDAV, Cryptomatorに対応しています。
iOSで再生できるメディアファイルの他、ソフトウエアデコードによりmpeg2等の動画も再生できます。
クラウドストレージのファイルを編集することも可能です(アップロード、フォルダ作成、リネーム、移動、削除)

Ver 1.4.0より、Chromecastをサポートしました。ただしキャスト中は、アプリを切り替えたり画面ロックを行うことができません。

## コンパイル方法
これまでにセットアップしていない場合は、次のコマンドで実行環境を準備します。

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer/
brew install nasm
brew install yasm
```

### 依存パッケージの準備

```bash
./chromecast.sh
cd work
./clone.sh
./build.sh
```

### Xcodeでのコンパイル
1. workspace "ccViewer.xcworkspace" を開きます。
2. scheme "CryptCloudViewer" を選択し build します。

実際に使用したい場合は、"RemoteCloud/RemoteCloud/Secret.swift" のファイルを修正し、
あなた自身で取得した、それぞれのサービスでの client_id と secret に置き換えてください。
