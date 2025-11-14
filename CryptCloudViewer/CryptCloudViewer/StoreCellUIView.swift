//
//  StoreCellUIView.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/11/14.
//

import SwiftUI
import StoreKit

struct StoreCellUIView: View {
    @Environment(Store.self) var store: Store
    @State var isPurchased: Bool = false
    @State var errorTitle = ""
    @State var isShowingError: Bool = false

    let product: Product

    init(product: Product) {
        self.product = product
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(product.displayName)
                    .bold()
                Text(product.description)
            }
            .foregroundColor(isPurchased ? .green : nil)
            Text("+1")
                .foregroundColor(.red)
                .bold(isPurchased)
                .opacity(isPurchased ? 1.0 : 0.0)
            Spacer()
            buyButton
        }
        .alert(isPresented: $isShowingError, content: {
            Alert(title: Text(errorTitle), message: nil, dismissButton: .default(Text("OK")))
        })
    }

    var buyButton: some View {
        Button(action: {
            Task {
                await buy()
            }
        }) {
            Text(product.displayPrice)
                .bold()
        }
    }

    func buy() async {
        store.loading = true
        defer {
            store.loading = false
        }
        do {
            if try await store.purchase(product) != nil {
                withAnimation {
                    isPurchased = true
                }
                try await Task.sleep(for: .seconds(1))
                withAnimation {
                    isPurchased = false
                }
            }
        } catch StoreError.failedVerification {
            errorTitle = "Your purchase could not be verified by the App Store."
            isShowingError = true
        } catch {
            print("Failed purchase for \(product.id): \(error)")
        }
    }
}
