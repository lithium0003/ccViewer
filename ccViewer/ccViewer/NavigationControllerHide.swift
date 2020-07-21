//
//  NavigationControllerHide.swift
//  ccViewer
//
//  Created by rei6 on 2019/04/08.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class NavigationControllerHide: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    override open var childForStatusBarStyle: UIViewController? {
        return topViewController ?? super.childForStatusBarStyle
    }
    
    override open var childForStatusBarHidden: UIViewController? {
        return topViewController ?? super.childForStatusBarHidden
    }

    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
    }
    
    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "ForceLandscape") {
            if UserDefaults.standard.bool(forKey: "LandscapeCameraLeft") {
                return .landscapeRight
            }
            return .landscapeLeft
        }
        return .all
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
