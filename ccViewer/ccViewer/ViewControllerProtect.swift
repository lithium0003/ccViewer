//
//  ViewControllerProtect.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/07.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import LocalAuthentication

class ViewControllerProtect: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var InfoLabel: UILabel!
    @IBOutlet weak var PasswordText: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        PasswordText.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if let password = getKeyChain(key: "password"), password != "" {
            self.InfoLabel.text = NSLocalizedString("Require Authentication", comment: "")
            Authentication()
        }
        else{
            let next = storyboard!.instantiateViewController(withIdentifier: "MainNavigation")
            self.present(next, animated: false)
        }
    }
    

    func Authentication() {
        let myContext = LAContext()
        var authError: NSError? = nil
        
        if myContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError){
            myContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Locked") { (success, evaluateError) in
                if success {
                    DispatchQueue.main.async {
                        let next = self.storyboard!.instantiateViewController(withIdentifier: "MainNavigation")
                        self.present(next, animated: false)
                    }
                }
                else{
                    DispatchQueue.main.async {
                        self.InfoLabel.text = NSLocalizedString("Authentication failed", comment: "")
                    }
                }
            }
        }
        else {
            DispatchQueue.main.async {
                self.InfoLabel.text = NSLocalizedString("Require password", comment: "")
            }
        }
    }
    
    @IBAction func RunButton(_ sender: Any) {
        Authentication()
    }
    
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
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        if let password = getKeyChain(key: "password") {
            if textField.text == password {
                let next = self.storyboard!.instantiateViewController(withIdentifier: "MainNavigation")
                self.present(next, animated: false)
            }
            else{
                self.InfoLabel.text = NSLocalizedString("Incorrect password", comment: "")
            }
        }
        else{
            let next = self.storyboard!.instantiateViewController(withIdentifier: "MainNavigation")
            self.present(next, animated: false)
        }
        
        return true
    }

}
