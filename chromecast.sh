#!/bin/bash

curl -OL https://dl.google.com/dl/chromecast/sdk/ios/GoogleCastSDK-ios-4.8.4_dynamic.zip
unzip GoogleCastSDK-ios-4.8.4_dynamic.zip
ln -s GoogleCastSDK-ios-4.8.4_dynamic_xcframework/GoogleCast.xcframework .
