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
    
    override var childForStatusBarStyle: UIViewController? {
        return visibleViewController
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return visibleViewController
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
