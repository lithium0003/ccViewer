//
//  StoreUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/11/14.
//

import SwiftUI
import StoreKit

struct StoreUIView: View {
    @State var store: Store = Store()
    @State var hiddenItem = false
    @State var loadingMessage = ""
    
    var body: some View {
        ZStack {
            List {
                Section {
                    Text("This app is free; all functions are available with no purchases.\nIf you want to help the developer for improving app, you can buy these menus.")
                }
                .onTapGesture(count: 10) {
                    hiddenItem.toggle()
                }
                Section {
                    ForEach(store.items) { item in
                        StoreCellUIView(product: item)
                    }
                }
                if !store.items.isEmpty, !store.items.allSatisfy({ store.count[$0.id] ?? 0 == 0 }) {
                    Section {
                        HStack {
                            Spacer()
                            ForEach(store.items) { item in
                                if store.count[item.id] ?? 0 > 0 {
                                    VStack {
                                        Image(item.id)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                        Text("\(store.count[item.id] ?? 0)")
                                            .bold()
                                            .font(.largeTitle)
                                    }
                                }
                                else {
                                    VStack {
                                        Image("empty")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                }
                if hiddenItem {
                    Button {
                        Store.clearProductCount()
                    } label: {
                        Text("Clear count")
                    }
                }
                CreditUIView()
            }
            if store.loading {
                ProgressView()
                    .padding(30)
                    .background {
                        Color(uiColor: .systemBackground)
                            .opacity(0.9)
                    }
                    .scaleEffect(3)
                    .cornerRadius(10)
            }
        }
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
        .environment(store)
    }
}

#Preview {
    StoreUIView()
}
