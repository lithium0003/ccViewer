# ccViewer

## description
This app is iOS cloud viewer with keeping encrypted.

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
