//
//  ContentView.swift
//  ccViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import Combine
import AVFoundation

@Observable class UserStateObject {
    static var shared = UserStateObject()
    var tutorial = UserDefaults.standard.bool(forKey: "tutorial")
    var locked = true
    var isPassworded: Bool {
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
        
        if let password = getKeyChain(key: "password"), password != "" {
            return true
        }
        else {
            return false
        }
    }
}

struct ContentView: View {
    @State var state = UserStateObject.shared
    
    var body: some View {
        if UserStateObject.shared.tutorial {
            if UserStateObject.shared.locked, UserStateObject.shared.isPassworded {
                ProtectUIView(locked: $state.locked)
            }
            else {
                MainUIView()
            }
        }
        else {
            TutorialUIView(tutorial: $state.tutorial)
        }
    }
}

#Preview {
    ContentView()
}
