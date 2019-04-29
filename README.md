# ccViewer

## description
This app is iOS cloud viewer with keeping encrypted. Supported storages: Google Drive, Dropbox, OneDrive, pCloud and Document folder. Available encryption: rclone, CarotDAV. This app can play media files with keeping encrypted. In addition, this app can play non-native media files (ex. mpeg2) with software decoder. You can edit your cloud storages: upload, make folder, rename, move, delete items.

## how to compile
if you did not set up, run these commands.

```bash
brew install mercurial
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer/
brew install nasm
brew install yasm
```

### prepare depencency

```bash
cd work
./clone.sh
./ffmpeg_compile.sh
```

### open with Xcode and compile
1. open workspace "ccViewer.xcodeproj"
2. select scheme "libSDL-iOS" and build
3. select scheme "libSDL_image-iOS" and build
4. select scheme "libSDL_ttf-iOS" and build
5. select scheme "ccViewer" and build

If you want to use, fix a file "RemoteCloud/RemoteCloud/Secret.swift" for your own client_id and secret.
