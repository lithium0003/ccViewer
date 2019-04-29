//
//  ViewControllerTutorialPage.swift
//  ccViewer
//
//  Created by rei6 on 2019/04/02.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class ViewControllerTutorialPage: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let button = self.view.viewWithTag(1) as! UIButton
        button.addTarget(self, action: #selector(buttonTap), for: .touchUpInside)
    }
    
    @objc func buttonTap(_ sender: UIButton) {
        dismiss(animated: true, completion: nil)
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
