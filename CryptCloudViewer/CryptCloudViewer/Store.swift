//
//  Store.swift
//  CryptCloudViewer
//
//  Created by rei9 on 2025/11/14.
//

import Foundation
import StoreKit
import Combine

public enum StoreError: Error {
    case failedVerification
}

@Observable
class Store {
    var loading = false
    private(set) var items: [Product]
    private(set) var count: [String: Int] = [:]

    var updateListenerTask: Task<Void, Error>? = nil

    private static let products = [
        "info.lithium03.ccViewer.coffee",
        "info.lithium03.ccViewer.orange",
        "info.lithium03.ccViewer.dinner",
    ]

    @MainActor
    init() {
        //Initialize empty products, and then do a product request asynchronously to fill them in.
        items = []
        loadProductIdToCount()
        
        //Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        updateListenerTask = listenForTransactions()

        Task {
            //During store initialization, request products from the App Store.
            await requestProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }
    
    @MainActor
    static func clearProductCount() {
        for id in products {
            NSUbiquitousKeyValueStore.default.set(0, forKey: id)
        }
    }

    @MainActor
    func loadProductIdToCount() {
        var ret: [String: Int] = [:]
        for id in Store.products {
            ret[id] = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: id))
        }
        count = ret
    }

    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            //Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    if transaction.productType == .consumable {
                        let newCount = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: transaction.productID)) + transaction.purchasedQuantity
                        NSUbiquitousKeyValueStore.default.set(newCount, forKey: transaction.productID)
                        await self.loadProductIdToCount()
                    }
                    
                    //Always finish a transaction.
                    await transaction.finish()
                } catch {
                    //StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }

    @MainActor
    func requestProducts() async {
        do {
            //Request products from the App Store using the identifiers that the Products.plist file defines.
            let storeProducts = try await Product.products(for: Store.products)

            var newItems: [Product] = []

            //Filter the products into categories based on their type.
            for product in storeProducts {
                switch product.type {
                case .consumable:
                    newItems.append(product)
                default:
                    //Ignore this product.
                    print("Unknown product")
                }
            }

            //Sort each product category by price, lowest to highest, to update the store.
            items = sortByPrice(newItems)
        } catch {
            print("Failed product request from the App Store server: \(error)")
        }
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        //Begin purchasing the `Product` the user selects.
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            //Check whether the transaction is verified. If it isn't,
            //this function rethrows the verification error.
            let transaction = try checkVerified(verification)

            if transaction.productType == .consumable {
                let newCount = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: transaction.productID)) + transaction.purchasedQuantity
                print(newCount)
                NSUbiquitousKeyValueStore.default.set(newCount, forKey: transaction.productID)
                loadProductIdToCount()
            }

            //Always finish a transaction.
            await transaction.finish()

            return transaction
        case .userCancelled, .pending:
            return nil
        default:
            return nil
        }
    }

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        //Check whether the JWS passes StoreKit verification.
        switch result {
        case .unverified:
            //StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            //The result is verified. Return the unwrapped value.
            return safe
        }
    }

    func sortByPrice(_ products: [Product]) -> [Product] {
        products.sorted(by: { return $0.price < $1.price })
    }
}
