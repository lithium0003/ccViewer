# CryptCloudViewer
This repository is source code of iOS app "CryptCloudViewer"
https://itunes.apple.com/us/app/cryptcloudviewer/id1458528598

## description
This app is iOS cloud viewer with keeping encrypted. App supports device folders (external storage and samba are also supported in iOS13) and remote storages: Google Drive, Dropbox, OneDrive, pCloud, WebDAV. Available encryption: rclone, CarotDAV and Cryptomator. This app can play media files with keeping encrypted. In addition, this app can play non-native media files (ex. mpeg2) with software decoder. You can edit your cloud storages: upload, make folder, rename, move, delete items.

In version 1.4.0, Chromecast support added. Please keep the app foreground and not lock the device while casting to Chromecast.

## how to compile
if you did not set up, run these commands.

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer/
brew install nasm
brew install yasm
```

### prepare depencency

```bash
./chromecast.sh
cd work
./clone.sh
./build.sh
```

### open with Xcode and compile
1. open workspace "ccViewer.xcworkspace"
2. select scheme "CryptCloudViewer" and build

If you want to use, fix a file "RemoteCloud/RemoteCloud/Secret.swift" for your own client_id and secret.
