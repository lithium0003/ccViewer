//
//  TutorialUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/10/19.
//

import SwiftUI

struct TutorialUIView: View {
    @Binding var tutorial: Bool

    var body: some View {
        TabView {
            Tab {
                VStack {
                    Text("Welcome to CryptCloudViewer!")
                        .font(.largeTitle)
                        .padding()
                    Spacer()
                    Text("First, add your cloud strage.")
                        .padding()
                    Image("tutorial1")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 300)
                    Button {
                        tutorial = true
                        UserDefaults.standard.set(true, forKey: "tutorial")
                    } label: {
                        Text("Skip tutorial")
                    }
                    Spacer()
                }
                .padding()
            }

            Tab {
                VStack {
                    Text("If you keep this app to be secure, set password.")
                        .padding()
                    HStack {
                        Image("tutorial2")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                        Image("tutorial3")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                    }
                    Text("If set any password, protection is ON. Turn off if enter empty password.")
                        .padding()
                    Button {
                        tutorial = true
                        UserDefaults.standard.set(true, forKey: "tutorial")
                    } label: {
                        Text("Skip tutorial")
                    }
                }
                .padding()
            }

            Tab {
                VStack {
                    Text("If you plan to add encrypted folder, register base storage before add the crypto storage.")
                        .padding()
                    Text("(Filen.io has cryption storage its own, so just add it.)")
                        .padding()
                    HStack {
                        Image("tutorial4")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                        Image("tutorial5")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                    }
                    VStack(alignment: .leading) {
                        Text("(1) Set the local name")
                        Text("(2) Select the cryption method")
                        Text("(3) Enter the password and options")
                        Text("(4) Select the folder as root,")
                        Text("(5) Tap 'Done'.")
                    }
                    .padding()
                    Button {
                        tutorial = true
                        UserDefaults.standard.set(true, forKey: "tutorial")
                    } label: {
                        Text("End tutorial")
                    }
                }
                .padding()
            }
        }
        .tabViewStyle(.page)
        .background {
            Color("TutorialBackgroundColor")
                .ignoresSafeArea()
        }
    }
}

#Preview {
    @Previewable @State var tutorial = false
    TutorialUIView(tutorial: $tutorial)
}
