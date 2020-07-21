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

#if !targetEnvironment(macCatalyst)
import GoogleCast
#endif

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    let kReceiverAppID = "5171613F"
    //let kReceiverAppID = "AA0DBCA4"
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

        // MARK: google chromecast
        #if !targetEnvironment(macCatalyst)
        let criteria = GCKDiscoveryCriteria(applicationID: kReceiverAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        // Enable logger.
        //GCKLogger.sharedInstance().delegate = self
        //let filter = GCKLoggerFilter()
        //filter.minimumLevel = .debug
        //GCKLogger.sharedInstance().filter = filter
        
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        #endif

        // MARK: RemoteCloud
        CloudFactory.shared.urlSessionDidFinishCallback = urlSessionDidFinishEvents

        // MARK: Payment
        PurchaseManager.sharedManager().delegate = self
        SKPaymentQueue.default().add(PurchaseManager.sharedManager())

        return true
    }

    // MARK: UISceneSession Lifecycle

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        if options.userActivities.filter({$0.activityType == "info.lithium03.ccViewer.about"}).first != nil {
            return UISceneConfiguration(name: "About Configuration", sessionRole: connectingSceneSession.role)
        }
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

    // MARK: background URLSession
    
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
    
    // MARK: - MENU
    #if targetEnvironment(macCatalyst)
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        
        let aboutCommand = UICommand(title: NSLocalizedString("About CryptCloudViewer", comment: ""), action: #selector(aboutAction))
        let aboutMenu = UIMenu(title: "About", image: nil, identifier: .about, options: .displayInline, children: [aboutCommand])
        builder.replace(menu: .about, with: aboutMenu)
    }
    
    @objc func aboutAction(_ sender: AnyObject) {
        let userActivity = NSUserActivity(activityType: "info.lithium03.ccViewer.about")
        let windowScene = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first
        if let windowScene = windowScene as? UIWindowScene {
            let session = windowScene.session
            UIApplication.shared.requestSceneSessionActivation(session, userActivity: userActivity, options: nil)
        }
    }
    #endif
    
    // MARK: iOS12 back compatibility

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
        FFPlayerViewController.inFocus = false
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        FFPlayerViewController.inFocus = true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
        CloudFactory.shared.data.saveContext()
        CloudFactory.shared.cache.saveContext()
    }

}

extension AppDelegate: PurchaseManagerDelegate {
    
    func purchaseManager(_ purchaseManager: PurchaseManager!, didFinishUntreatedPurchaseWithTransaction transaction: SKPaymentTransaction!, decisionHandler: ((_ complete: Bool) -> Void)!) {
        print("#### didFinishUntreatedPurchaseWithTransaction ####")
        // TODO: コンテンツ解放処理
        //コンテンツ解放が終了したら、この処理を実行(true: 課金処理全部完了, false 課金処理中断)
        decisionHandler(true)
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
