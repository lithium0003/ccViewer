//
//  ViewControllerAbout.swift
//  CryptCloudViewer
//
//  Created by rei8 on 2019/11/27.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class ViewControllerAbout: UIViewController {

    @IBOutlet weak var textVersion: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        let version = "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")"
        let build = "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")"
        let appname = "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "")"
        textVersion.text = "\(appname)\n\nVersion \(version)(\(build))"
    }
    
    @IBAction func tapOK(_ sender: UIButton) {
        dismiss(animated: true) {
            #if targetEnvironment(macCatalyst)
            guard let session = self.view.window?.windowScene?.session else {
                return
            }
            let options = UIWindowSceneDestructionRequestOptions()
            options.windowDismissalAnimation = .standard
            UIApplication.shared.requestSceneSessionDestruction(session, options: options)
            #endif
        }
    }
    
    @IBAction func backToTop(segue: UIStoryboardSegue) {
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
