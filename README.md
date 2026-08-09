# CryptCloudViewer
This repository is source code of iOS app "CryptCloudViewer"
https://itunes.apple.com/us/app/cryptcloudviewer/id1458528598

## description
This app is iOS cloud viewer with keeping encrypted. App supports device folders and remote storages: Google Drive, Dropbox, OneDrive, pCloud, Filen.io, S3, WebDAV and Samba. Available encryption: rclone, CarotDAV, Cryptomator and gocryptfs. This app can play media files with keeping encrypted. In addition, this app can play non-native media files (ex. mpeg2) with software decoder. You can edit your cloud storages: upload, make folder, rename, move, delete items.

In version 1.4.0, Chromecast support added. Please keep the app foreground and not lock the device while casting to Chromecast.

In version 2.0.0, rewrite for iOS26 and broken features fix. Support OS is swiched to >=iOS26. Background upload, download and cast play is available in setting menu.

## video
[![YouTube](https://img.youtube.com/vi/BelQr_-3t7c/maxresdefault.jpg)](https://www.youtube.com/watch?v=BelQr_-3t7c)

## how to compile
if you did not set up, run these commands.

### prepare submodules
```bash
cd ccViewer
git submodule update --init --recursive
```
```bash
cd library
./build.sh
```

### prepare depencency

```bash
./chromecast.sh
cd work
./clone.sh
./apply_patch.sh
./build.sh
```

### open with Xcode and compile
1. open workspace "CryptCloudViewer.xcworkspace"
2. select scheme "CryptCloudViewer" and build

If you want to use, fix these files for your own client_id and secret.
- RemoteCloud/RemoteCloud/Secret.swift
- CryptCloudViewer/CryptCloudViewer/Secret.xcconfig
- CryptCloudViewer/CryptCloudViewer/Secret.swift

## Help
https://lithium03.info/ios/ccViewer.en.html (English)
