# CryptCloudViewer
iOSアプリ"CryptCloudViewer"のソースコードのレポジトリです。

アプリはこちらからダウンロードできます。
https://itunes.apple.com/jp/app/cryptcloudviewer/id1458528598

## 説明
暗号化したまま閲覧できるクラウドビューワです。端末のフォルダに加えて、クラウドストレージ: Google Drive, Dropbox, OneDrive, pCloud, Filen.io, S3, WebDAV, Samba、暗号化: rclone, CarotDAV, Cryptomator, gocryptfs に対応しています。iPhoneで再生できるメディアファイルの他、ソフトウエアデコードによりmpeg2等の動画も再生できます。クラウドストレージのファイルを編集することも可能です(アップロード、フォルダ作成、リネーム、移動、削除)。また、端末で自動的にエンコードを行い、Chromecastでデバイスに送信することが可能です。

Ver 1.4.0より、Chromecastをサポートしました。ただしキャスト中は、アプリを切り替えたり画面ロックを行うことができません。

Ver 2.0.0より、サポートOSをiOS26以降にしました。

## video
[![YouTube](https://img.youtube.com/vi/sCPPcoqAR3g/maxresdefault.jpg)](https://www.youtube.com/watch?v=sCPPcoqAR3g)


## コンパイル方法
これまでにセットアップしていない場合は、次のコマンドで実行環境を準備します。

### submoduleの準備
cloneする際に、`git clone --recursive`しなかった場合は、次の手順でsubmodleを準備します。
```bash
cd ccViewer
git submodule update --init --recursive
```

### 依存パッケージの準備

```bash
./chromecast.sh
cd work
./clone.sh
./apply_patch.sh
./build.sh
```

### Xcodeでのコンパイル
1. workspace "ccViewer.xcworkspace" を開きます。
2. scheme "CryptCloudViewer" を選択し build します。

実際に使用したい場合は、以下のファイルを修正し、
- RemoteCloud/RemoteCloud/Secret.swift
- CryptCloudViewer/CryptCloudViewer/Secret.xcconfig
- CryptCloudViewer/CryptCloudViewer/Secret.swift
あなた自身で取得した、それぞれのサービスでの client_id と secret に置き換えてください。

## ヘルプ
https://lithium03.info/ios/ccViewer.ja.html (日本語)
