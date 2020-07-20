#!/bin/bash

curl -OL https://dl.google.com/dl/chromecast/sdk/ios/GoogleCastSDK-ios-no-bluetooth-4.4.7_dynamic.zip
unzip GoogleCastSDK-ios-no-bluetooth-4.4.7_dynamic.zip
ln -s GoogleCastSDK-ios-4.4.7_dynamic GoogleCastSDK
patch -p0 <strip.diff
