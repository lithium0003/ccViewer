//
//  PurchaceViewController.swift
//  barometer
//
//  Created by rei6 on 2018/09/14.
//  Copyright © 2018年 lithium03. All rights reserved.
//

import UIKit
import StoreKit
import os.log

class PurchaceViewController: UIViewController, PurchaseManagerDelegate {
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "Utility")
    #if targetEnvironment(macCatalyst)
    let productIdentifiers : [String] = ["maccatalyst.info.lithium03.ccViewer.coffee",
                                         "maccatalyst.info.lithium03.ccViewer.orange",
                                         "maccatalyst.info.lithium03.ccViewer.dinner"]
    #else
    let productIdentifiers : [String] = ["info.lithium03.ccViewer.coffee",
                                         "info.lithium03.ccViewer.orange",
                                         "info.lithium03.ccViewer.dinner"]
    #endif
    var retry_count = 0
    
    
    @IBOutlet weak var item1: UIButton!
    @IBOutlet weak var item2: UIButton!
    @IBOutlet weak var item3: UIButton!
    @IBOutlet weak var image1: UIImageView!
    @IBOutlet weak var image2: UIImageView!
    @IBOutlet weak var image3: UIImageView!
    @IBOutlet weak var count1: UILabel!
    @IBOutlet weak var count2: UILabel!
    @IBOutlet weak var count3: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        // プロダクト情報取得
        fetchProductInformationForIds(productIdentifiers)
        title = NSLocalizedString("Purchase", comment: "")
        //restore.setTitle(NSLocalizedString("Restore purchases", comment: ""), for: .normal)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func item1_touch(_ sender: Any) {
        startPurchase(productIdentifier: productIdentifiers[0])
    }
    
    @IBAction func item2_touch(_ sender: Any) {
        startPurchase(productIdentifier: productIdentifiers[1])
    }
    
    @IBAction func item3_touch(_ sender: Any) {
        startPurchase(productIdentifier: productIdentifiers[2])
    }
    
    @IBAction func restore_touch(_ sender: Any) {
        startRestore()
    }
    
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

    //------------------------------------
    // 課金処理開始
    //------------------------------------
    func startPurchase(productIdentifier : String) {
        print("課金処理開始!!")
        //デリゲード設定
        PurchaseManager.sharedManager().delegate = self
        //プロダクト情報を取得
        ProductManager.productsWithProductIdentifiers(productIdentifiers: [productIdentifier], completion: { (products, error) -> Void in
            if (products?.count)! > 0 {
                //課金処理開始
                PurchaseManager.sharedManager().startWithProduct((products?[0])!)
            }
            if (error != nil) {
                os_log("startPurchase %{public}@", log: self.log, type: .error, error!.localizedDescription)
            }
        })
    }
    // リストア開始
    func startRestore() {
        //デリゲード設定
        PurchaseManager.sharedManager().delegate = self
        //リストア開始
        PurchaseManager.sharedManager().startRestore()
    }
    //------------------------------------
    // MARK: - PurchaseManager Delegate
    //------------------------------------
    //課金終了時に呼び出される
    func purchaseManager(_ purchaseManager: PurchaseManager!, didFinishPurchaseWithTransaction transaction: SKPaymentTransaction!, decisionHandler: ((_ complete: Bool) -> Void)!) {
        
        print("課金終了！！")
        //---------------------------
        // コンテンツ解放処理
        //---------------------------
        DispatchQueue.main.async {
            if let id = self.productIdentifiers.firstIndex(of: transaction.payment.productIdentifier) {
                switch id {
                case 0:
                    let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product1") + 1
                    NSUbiquitousKeyValueStore.default.set(count, forKey: "Product1")
                    self.item1.isEnabled = true
                    self.image1.image = UIImage(named: "Image1")
                    self.count1.text = (count > 0) ? "\(count)" : ""
                case 1:
                    let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product2") + 1
                    NSUbiquitousKeyValueStore.default.set(count, forKey: "Product2")
                    self.item2.isEnabled = true
                    self.image2.image = UIImage(named: "Image2")
                    self.count2.text = (count > 0) ? "\(count)" : ""
                case 2:
                    let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product3") + 1
                    NSUbiquitousKeyValueStore.default.set(count, forKey: "Product3")
                    self.item3.isEnabled = true
                    self.image3.image = UIImage(named: "Image3")
                    self.count3.text = (count > 0) ? "\(count)" : ""
                default:
                    break
                }
            }
            //コンテンツ解放が終了したら、この処理を実行(true: 課金処理全部完了, false 課金処理中断)
            decisionHandler(true)
        }
    }
    //課金終了時に呼び出される(startPurchaseで指定したプロダクトID以外のものが課金された時。)
    func purchaseManager(_ purchaseManager: PurchaseManager!, didFinishUntreatedPurchaseWithTransaction transaction: SKPaymentTransaction!, decisionHandler: ((_ complete: Bool) -> Void)!) {
        print("課金終了（指定プロダクトID以外）！！")
        //---------------------------
        // コンテンツ解放処理
        //---------------------------
        DispatchQueue.main.async {
            if let id = self.productIdentifiers.firstIndex(of: transaction.payment.productIdentifier) {
                switch id {
                case 0:
                    let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product1") + 1
                    NSUbiquitousKeyValueStore.default.set(count, forKey: "Product1")
                    self.item1.isEnabled = true
                    self.image1.image = UIImage(named: "Image1")
                    self.count1.text = (count > 0) ? "\(count)" : ""
                case 1:
                    let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product2") + 1
                    NSUbiquitousKeyValueStore.default.set(count, forKey: "Product2")
                    self.item2.isEnabled = true
                    self.image2.image = UIImage(named: "Image2")
                    self.count2.text = (count > 0) ? "\(count)" : ""
                case 2:
                    let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product3") + 1
                    NSUbiquitousKeyValueStore.default.set(count, forKey: "Product3")
                    self.item3.isEnabled = true
                    self.image3.image = UIImage(named: "Image3")
                    self.count3.text = (count > 0) ? "\(count)" : ""
                default:
                    break
                }
            }
            //コンテンツ解放が終了したら、この処理を実行(true: 課金処理全部完了, false 課金処理中断)
            decisionHandler(true)
        }
    }
    //課金失敗時に呼び出される
    func purchaseManager(_ purchaseManager: PurchaseManager!, didFailWithError error: NSError!) {
        print("課金失敗！！")
        // TODO errorを使ってアラート表示
        os_log("purchaseManager(didFailWithError) %{public}@", log: self.log, type: .error, error.localizedDescription)
        DispatchQueue.main.async {
            let alert: UIAlertController = UIAlertController(title: error.localizedDescription, message: error.localizedRecoverySuggestion, preferredStyle:  UIAlertController.Style.alert)
            let defaultAction = UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil)
            alert.addAction(defaultAction)
            
            let screenSize = UIScreen.main.bounds
            alert.popoverPresentationController?.sourceRect = CGRect(x: screenSize.size.width/2, y: screenSize.size.height, width: 0, height: 0)
            self.present(alert, animated: true)
        }

    }
    // リストア終了時に呼び出される(個々のトランザクションは”課金終了”で処理)
    func purchaseManagerDidFinishRestore(_ purchaseManager: PurchaseManager!) {
        print("リストア終了！！")
        // TODO インジケータなどを表示していたら非表示に
    }
    // 承認待ち状態時に呼び出される(ファミリー共有)
    func purchaseManagerDidDeferred(_ purchaseManager: PurchaseManager!) {
        print("承認待ち！！")
        // TODO インジケータなどを表示していたら非表示に
    }
    // プロダクト情報取得
    fileprivate func fetchProductInformationForIds(_ productIds:[String]) {
        let group = DispatchGroup()
        group.enter()
        ProductManager.productsWithProductIdentifiers(productIdentifiers: productIds,completion: {[weak self] (products : [SKProduct]?, error : NSError?) -> Void in
            if error != nil {
                if self != nil {
                    os_log("productsWithProductIdentifiers %{public}@", log: self!.log, type: .error, error!.localizedDescription)
                    self?.retry_count += 1
                }
                print(error!.localizedDescription)
                return
            }
            DispatchQueue.main.async {
                for product in products! {
                    let priceString = ProductManager.priceStringFromProduct(product: product)
                    if let id = self?.productIdentifiers.firstIndex(of: product.productIdentifier) {
                        if self != nil {
                            switch id {
                            case 0:
                                self?.item1.titleLabel?.numberOfLines = 0
                                self?.item1.titleLabel?.textAlignment = .center
                                self?.item1.setTitle("\(product.localizedTitle) : \(priceString)\n\(product.localizedDescription)", for: .normal)
                                self?.item1.isEnabled = true
                                let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product1")
                                if count > 0 {
                                    self?.image1.image = UIImage(named: "Image1")
                                    self?.count1.text = (count > 0) ? "\(count)" : ""
                                }
                            case 1:
                                self?.item2.titleLabel?.numberOfLines = 0
                                self?.item2.titleLabel?.textAlignment = .center
                                self?.item2.setTitle("\(product.localizedTitle) : \(priceString)\n\(product.localizedDescription)", for: .normal)
                                self?.item2.isEnabled = true
                                let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product2")
                                if count > 0 {
                                    self?.image2.image = UIImage(named: "Image2")
                                    self?.count2.text = (count > 0) ? "\(count)" : ""
                                }
                            case 2:
                                self?.item3.titleLabel?.numberOfLines = 0
                                self?.item3.titleLabel?.textAlignment = .center
                                self?.item3.setTitle("\(product.localizedTitle) : \(priceString)\n\(product.localizedDescription)", for: .normal)
                                self?.item3.isEnabled = true
                                let count = NSUbiquitousKeyValueStore.default.longLong(forKey: "Product3")
                                if count > 0 {
                                    self?.image3.image = UIImage(named: "Image3")
                                    self?.count3.text = (count > 0) ? "\(count)" : ""
                                }
                            default:
                                break
                            }
                        }
                        print(product.productIdentifier + " \(product.localizedTitle):\(priceString)\n\(product.localizedDescription)" )
                    }
                }
                group.leave()
            }
        })
        group.notify(queue: .main ) { [weak self] in
            if (self?.retry_count ?? 0) > 0 {
                if self!.retry_count > 5 {
                    os_log("productsWithProductIdentifiers retry 5times", log: self!.log, type: .error)
                }
                else {
                    self!.fetchProductInformationForIds(productIds)
                }
            }
        }
    }
}
