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
    @State var showInitAlert = false
    
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

        if UserDefaults.standard.bool(forKey: "tutorial"), UserDefaults.standard.integer(forKey: "previousBuildNo") < 99 {
            showInitAlert = true
        }
    }
    
    func deletePreviousData() async {
        await CloudFactory.shared.removeAllAuth()
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        await CloudFactory.shared.cache.deleteAllCache()
        await CloudFactory.shared.initializeDatabase()

        let buildNum = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
        UserDefaults.standard.set(buildNum, forKey: "previousBuildNo")
        
        initParams()
    }
    
    func cancelDelete() {
        let buildNum = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
        UserDefaults.standard.set(buildNum, forKey: "previousBuildNo")
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
                .alert("Break changed version", isPresented: $showInitAlert) {
                    Button(role: .destructive) {
                        Task {
                            await deletePreviousData()
                        }
                    }
                    
                    Button(role: .cancel) {
                        cancelDelete()
                    }
                } message: {
                    Text("This version is not compatible with the previous version. We recommend to delete all previos data and re-login all storages. Do you want to erease all app data?")
                }
        }
    }
}
