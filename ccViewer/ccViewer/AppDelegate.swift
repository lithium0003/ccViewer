//
//  AppDelegate.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import StoreKit
import UserNotifications
import AVFoundation

import RemoteCloud
import ffplayer

import GoogleCast

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, PurchaseManagerDelegate {
    let kReceiverAppID = "5171613F"
    //let kReceiverAppID = "AA0DBCA4"
    let kDebugLoggingEnabled = false
    
    var window: UIWindow?

    var completionHandlers = [String: ()->Void]()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for fileURL in fileURLs {
                print("delete ", fileURL)
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch  { print(error) }
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
        // google chromecast
        #if !targetEnvironment(macCatalyst)
        let criteria = GCKDiscoveryCriteria(applicationID: kReceiverAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        // Enable logger.
        GCKLogger.sharedInstance().delegate = self
        //let filter = GCKLoggerFilter()
        //filter.minimumLevel = .debug
        //GCKLogger.sharedInstance().filter = filter
        
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        #endif
        
        window?.clipsToBounds = true
        
        //---------------------------------------
        // アプリ内課金設定
        //---------------------------------------
        // デリゲート設定
        PurchaseManager.sharedManager().delegate = self
        // オブザーバー登録
        SKPaymentQueue.default().add(PurchaseManager.sharedManager())

        CloudFactory.shared.urlSessionDidFinishCallback = urlSessionDidFinishEvents
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        FFPlayerViewController.inFocus = false
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        FFPlayerViewController.inFocus = true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
        CloudFactory.shared.data.saveContext()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandlers[identifier] = completionHandler
        print("handleEventsForBackgroundURLSession \(identifier)")
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let sessionIdentifier = session.configuration.identifier
        print("urlSessionDidFinishEvents \(sessionIdentifier ?? "")")
        DispatchQueue.main.async {
            guard let sessionId = sessionIdentifier, let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                let handler = appDelegate.completionHandlers.removeValue(forKey: sessionId) else {
                    return
            }
            print("call handler()")
            handler()
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {

        // Determine who sent the URL.
        let sendingAppID = options[.sourceApplication]
        print("source application = \(sendingAppID ?? "Unknown")")
        
        // Process the URL.
        guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true),
            let targetPath = components.path else {
                print("Invalid URL or album path missing")
                return false
        }

        print(targetPath)
        return true
    }
        
    // 課金終了(前回アプリ起動時課金処理が中断されていた場合呼ばれる)
    func purchaseManager(_ purchaseManager: PurchaseManager!, didFinishUntreatedPurchaseWithTransaction transaction: SKPaymentTransaction!, decisionHandler: ((_ complete: Bool) -> Void)!) {
        print("#### didFinishUntreatedPurchaseWithTransaction ####")
        // TODO: コンテンツ解放処理
        //コンテンツ解放が終了したら、この処理を実行(true: 課金処理全部完了, false 課金処理中断)
        decisionHandler(true)
    }
}

// MARK: - GCKLoggerDelegate
extension AppDelegate: GCKLoggerDelegate {
    func logMessage(_ message: String,
                    at _: GCKLoggerLevel,
                    fromFunction function: String,
                    location: String) {
        if kDebugLoggingEnabled {
            // Send SDK's log messages directly to the console.
            print("\(location): \(function) - \(message)")
        }
    }
}


extension UIApplication {
    class func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        var controller2 = controller
        if controller2 == nil {
            controller2 = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController
        }
        if let navigationController = controller2 as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller2 as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller2?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller2
    }
}

extension UINavigationController {
    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
    }
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "ForceLandscape") {
            return .landscapeLeft
        }
        return .all
    }
}
