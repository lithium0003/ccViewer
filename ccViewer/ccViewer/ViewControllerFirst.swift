//
//  ViewControllerFirst.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/14.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import LocalAuthentication

class ViewControllerFirst: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        if UserDefaults.standard.integer(forKey: "playSkipForwardSec") == 0 {
            UserDefaults.standard.set(30, forKey: "playSkipForwardSec")
        }
        if UserDefaults.standard.integer(forKey: "playSkipBackwardSec") == 0 {
            UserDefaults.standard.set(30, forKey: "playSkipBackwardSec")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        if UserDefaults.standard.bool(forKey: "tutorial") {
            if let password = getKeyChain(key: "password"), password != "" {
                let next = storyboard!.instantiateViewController(withIdentifier: "Protect")
                next.modalPresentationStyle = .fullScreen
                self.present(next, animated: false)
            }
            else{
                let next = storyboard!.instantiateViewController(withIdentifier: "MainNavigation")
                next.modalPresentationStyle = .fullScreen
                self.present(next, animated: false)
            }
        }
        else {
            UserDefaults.standard.set(true, forKey: "ImageViewer")
            UserDefaults.standard.set(true, forKey: "PDFViewer")
            UserDefaults.standard.set(true, forKey: "MediaViewer")
            UserDefaults.standard.set(false, forKey: "FFplayer")
            UserDefaults.standard.set(false, forKey: "savePlaypos")
            UserDefaults.standard.set(false, forKey: "resumePlaypos")
            UserDefaults.standard.set(false, forKey: "cloudPlaypos")
            UserDefaults.standard.set(false, forKey: "cloudPlaylist")
            UserDefaults.standard.set(true, forKey: "PDF_continuous")
            
            UserDefaults.standard.set(true, forKey: "tutorial")
            let next = storyboard!.instantiateViewController(withIdentifier: "Tutorial")
            next.modalPresentationStyle = .fullScreen
            self.present(next, animated: false)
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    func getKeyChain(key: String) -> String? {
        
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecReturnData as String: kCFBooleanTrue as Any]
        
        var data: AnyObject?
        let matchingStatus = withUnsafeMutablePointer(to: &data){
            SecItemCopyMatching(dic as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if matchingStatus == errSecSuccess {
            if let getData = data as? Data,
                let getStr = String(data: getData, encoding: .utf8) {
                return getStr
            }
            return nil
        } else {
            return nil
        }
    }
    
}
