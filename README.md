# CryptCloudViewer
This repository is source code of iOS app "CryptCloudViewer"
https://itunes.apple.com/us/app/cryptcloudviewer/id1458528598

## description
This app is iOS cloud viewer with keeping encrypted. App supports device folders and remote storages: Google Drive, Dropbox, OneDrive, pCloud, WebDAV and Samba. Available encryption: rclone, CarotDAV and Cryptomator. This app can play media files with keeping encrypted. In addition, this app can play non-native media files (ex. mpeg2) with software decoder. You can edit your cloud storages: upload, make folder, rename, move, delete items.

In version 1.4.0, Chromecast support added. Please keep the app foreground and not lock the device while casting to Chromecast.

## how to compile
if you did not set up, run these commands.

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

