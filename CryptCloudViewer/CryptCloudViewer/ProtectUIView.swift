//
//  ProtectUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI
import LocalAuthentication

struct ProtectUIView: View {
    @Binding var locked: Bool
    @State var text = ""

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

    func authenticate() async {
        let context = LAContext()
        var error: NSError?

        // 生体認証（Face IDやTouch ID）が利用可能であるかどうかを確認
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = String(localized: "unlock to start app")
            do {
                if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
                    locked = false
                }
            }
            catch {
                print(error)
            }
        }
    }
    
    var body: some View {
        if locked, let password = getKeyChain(key: "password"), password != "" {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                VStack {
                    Text("Require authentication")
                        .foregroundStyle(.white)
                    SecureField("password", text: $text)
                        .padding()
                        .frame(maxWidth: 300)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if let password = getKeyChain(key: "password"), password == text {
                                locked = false
                            }
                        }
                    Button {
                        if let password = getKeyChain(key: "password"), password == text {
                            locked = false
                        }
                        Task {
                            await authenticate()
                        }
                    } label: {
                        Text("Run Application")
                    }
                }
                .padding()
            }
            .task {
                await authenticate()
            }
        }
    }
}

#Preview {
    @Previewable @State var locked = true
    ProtectUIView(locked: $locked)
}
