//
//  ccViewerApp.swift
//  ccViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import UIKit
import GoogleSignIn
import GoogleCast

import RemoteCloud

class OrientationManager {
    static var mask = UIInterfaceOrientationMask.all
    
    @MainActor
    class func lock() {
        switch UIDevice.current.orientation {
        case .unknown:
            mask = .all
        case .portrait:
            mask = .portrait
        case .portraitUpsideDown:
            mask = .portraitUpsideDown
        case .landscapeLeft:
            mask = .landscapeRight
        case .landscapeRight:
            mask = .landscapeLeft
        case .faceUp:
            mask = .all
        case .faceDown:
            mask = .all
        @unknown default:
            mask = .all
        }
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        windowScene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    
    @MainActor
    class func unlock() {
        mask = .all
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        windowScene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationManager.mask
    }
}

@main
struct CryptCloudViewerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    func initParams() {
        if UserDefaults.standard.integer(forKey: "playSkipForwardSec") == 0 {
            UserDefaults.standard.set(15, forKey: "playSkipForwardSec")
        }
        if UserDefaults.standard.integer(forKey: "playSkipBackwardSec") == 0 {
            UserDefaults.standard.set(15, forKey: "playSkipBackwardSec")
        }

        if UserDefaults.standard.integer(forKey: "paramInit") == 0 {
            UserDefaults.standard.set(1, forKey: "paramInit")
            UserDefaults.standard.set(true, forKey: "ImageViewer")
            UserDefaults.standard.set(true, forKey: "PDFViewer")
            UserDefaults.standard.set(true, forKey: "MediaViewer")
            UserDefaults.standard.set(true, forKey: "FFplayer")
            UserDefaults.standard.set(true, forKey: "savePlaypos")
            UserDefaults.standard.set(true, forKey: "resumePlaypos")
            UserDefaults.standard.set(true, forKey: "cloudPlaypos")
            UserDefaults.standard.set(true, forKey: "cloudPlaylist")
            UserDefaults.standard.set(true, forKey: "PDF_continuous")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
#if DEBUG
                    GIDSignIn.sharedInstance.configureDebugProvider(withAPIKey: SecretItems.GIDSigninDebugKey) { error in
                        if let error {
                            print("configure: \(error)")
                        }
                    }
#else
                    GIDSignIn.sharedInstance.configure() {
                        error in
                        if let error {
                            print("configure: \(error)")
                        }
                    }
#endif
                    GIDSignIn.sharedInstance.restorePreviousSignIn{ user,error in
                        if let error {
                            print("restorePreviousSignIn: \(error)")
                        }
                    }

                    let criteria = GCKDiscoveryCriteria(applicationID: SecretItems.kReceiverAppID)
                    let options = GCKCastOptions(discoveryCriteria: criteria)
                    options.physicalVolumeButtonsWillControlDeviceVolume = true
                    options.suspendSessionsWhenBackgrounded = false
                    GCKCastContext.setSharedInstanceWith(options)
                    // Enable logger.
                    //GCKLogger.sharedInstance().delegate = self
                    //let filter = GCKLoggerFilter()
                    //filter.minimumLevel = .debug
                    //GCKLogger.sharedInstance().filter = filter
                    
                    GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true

                    initParams()
                }
                .onOpenURL{ url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                }
        }
    }
}
