//
//  RemoteStorage.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import AuthenticationServices
import os.log

public protocol RemoteStorageProtocol {
    
}



public class RemoteStorageBase {
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "application")
    var storageName: String?
    
    var tokenDate: Date = Date(timeIntervalSince1970: 0)
    var tokenLife: TimeInterval = 0
    var accessToken: String {
        if let name = storageName {
            return getKeyChain(key: "\(name)_accessToken") ?? ""
        }
        else {
            return ""
        }
    }
    var refreshToken: String {
        if let name = storageName {
            return getKeyChain(key: "\(name)_refreshToken") ?? ""
        }
        else {
            return ""
        }
    }

    public func auth(onFinish: ((Bool) -> Void)?) -> Void {
        checkToken(){ success in
            if success {
                onFinish?(true)
            }
            else {
                self.isAuthorized(){ success in
                    if success {
                        onFinish?(true)
                    }
                    else {
                        self.authorize(onFinish: onFinish)
                    }
                }
            }
        }
    }
    public func logout() {
        if let name = storageName {
            os_log("%{public}@", log: log, type: .info, "revokeToken")
            if let aToken = getKeyChain(key: "\(name)_accessToken") {
                revokeToken(token: aToken, onFinish: nil)
            }
            let _ = delKeyChain(key: "\(name)_accessToken")
            let _ = delKeyChain(key: "\(name)_refreshToken")
            tokenDate = Date(timeIntervalSince1970: 0)
            tokenLife = 0
        }
    }

    func checkToken(onFinish: ((Bool) -> Void)?) -> Void {
        if Date() < tokenDate + tokenLife - 5*60 {
            onFinish?(true)
        }
        else if refreshToken == "" {
            onFinish?(false)
        }
        else {
            refreshToken(onFinish: onFinish)
        }
    }
    
    func isAuthorized(onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(false)
    }
    func authorize(onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(false)
    }
    func getToken(oauthToken: String, onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(false)
    }
    func saveToken(accessToken: String, refreshToken: String) -> Void {
        if let name = storageName {
            os_log("%{public}@", log: log, type: .info, "saveToken")
            tokenDate = Date()
            let _ = setKeyChain(key: "\(name)_accessToken", value: accessToken)
            let _ = setKeyChain(key: "\(name)_refreshToken", value: refreshToken)
        }
    }
    func refreshToken(onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(false)
    }
    func revokeToken(token: String, onFinish: ((Bool) -> Void)?) -> Void {
        onFinish?(false)
    }
    
    private func getKeyChain(key: String) -> String? {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecReturnData as String: kCFBooleanTrue]
        
        var data: AnyObject?
        let matchingStatus = withUnsafeMutablePointer(to: &data){
            SecItemCopyMatching(dic as CFDictionary, UnsafeMutablePointer($0))
        }
        
        if matchingStatus == errSecSuccess {
            print("取得成功")
            if let getData = data as? Data,
                let getStr = String(data: getData, encoding: .utf8) {
                return getStr
            }
            print("取得失敗: Dataが不正")
            return nil
        } else {
            print("取得失敗")
            return nil
        }
    }

    private func delKeyChain(key: String) -> Bool {
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key]
        
        if SecItemDelete(dic as CFDictionary) == errSecSuccess {
            print("削除成功")
            return true
        } else {
            print("削除失敗")
            return false
        }
    }
    
    func setKeyChain(key: String, value: String) -> Bool{
        let data = value.data(using: .utf8)
        
        guard let _data = data else {
            return false
        }
        
        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: _data]
        
        var itemAddStatus: OSStatus?
        let matchingStatus = SecItemCopyMatching(dic as CFDictionary, nil)
        
        if matchingStatus == errSecItemNotFound {
            // 保存
            itemAddStatus = SecItemAdd(dic as CFDictionary, nil)
        } else if matchingStatus == errSecSuccess {
            // 更新
            itemAddStatus = SecItemUpdate(dic as CFDictionary, [kSecValueData as String: _data] as CFDictionary)
        } else {
            print("保存失敗")
        }
        
        if itemAddStatus == errSecSuccess {
            print("正常終了")
            return true
        } else {
            print("保存失敗")
            return false
        }
    }
}
