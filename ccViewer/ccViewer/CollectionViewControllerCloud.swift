//
//  CollectionViewControllerCloud.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/10.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

import RemoteCloud

private let reuseIdentifier = "CellCloud"

class CollectionViewControllerCloud: UICollectionViewController {
    let storage = CloudFactory.shared
    let activityIndicator = UIActivityIndicatorView()

    let remotes = CloudStorages.allCases.filter({ $0 != .Local })
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Register cell classes
        //self.collectionView!.register(UICollectionViewCell.self, forCellWithReuseIdentifier: reuseIdentifier)

        // Do any additional setup after loading the view.
        activityIndicator.center = view.center
        activityIndicator.style = .gray
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using [segue destinationViewController].
        // Pass the selected object to the new view controller.
    }
    */

    // MARK: UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }


    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of items
        return remotes.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath)
    
        // Configure the cell
        let imageView = cell.contentView.viewWithTag(1) as! UIImageView
        let label = cell.contentView.viewWithTag(2) as! UILabel
        
        let image = storage.getIcon(service: remotes[indexPath.row])
        imageView.image = image
        label.text = CloudFactory.getServiceName(service: remotes[indexPath.row])
    
        return cell
    }

    // MARK: UICollectionViewDelegate

    /*
    // Uncomment this method to specify if the specified item should be highlighted during tracking
    override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    */

    
    // Uncomment this method to specify if the specified item should be selected
    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        
        let alert = UIAlertController(title: CloudFactory.getServiceName(service: remotes[indexPath.row]),
                                      message: "Add new item",
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let defaultAction = UIAlertAction(title: "OK",
                                          style: .default,
                                          handler:{ action in
                                            if let newname = alert.textFields?[0].text {
                                                if newname == "" {
                                                    return
                                                }
                                                if CloudFactory.shared[newname] != nil {
                                                    return
                                                }
                                                let newitem = CloudFactory.shared.newStorage(service: self.remotes[indexPath.row], tagname: newname)
                                                
                                                DispatchQueue.main.async {
                                                    self.activityIndicator.startAnimating()
                                                }
                                                
                                                newitem.auth() { success in
                                                    if success {
                                                        newitem.list(fileId: "") {
                                                            DispatchQueue.main.async {
                                                                self.activityIndicator.stopAnimating()
                                                                self.navigationController?.popToRootViewController(animated: true)
                                                            }
//                                                            CloudFactory.shared.deepLoad(storage: newname)
                                                        }
                                                    }
                                                    else{
                                                        CloudFactory.shared.delStorage(tagname: newname)
                                                        DispatchQueue.main.async {
                                                            self.activityIndicator.stopAnimating()
                                                            self.navigationController?.popToViewController(self, animated: true)
                                                        }
                                                    }
                                                }
                                            }
        })
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)
        
        alert.addTextField(configurationHandler: {(text:UITextField!) -> Void in
            text.placeholder = "user defined name"
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 30))
            label.text = "Name"
            text.leftView = label
            text.leftViewMode = .always
            text.enablesReturnKeyAutomatically = true
        })
        
        present(alert, animated: true, completion: nil)
        
        return true
    }
    

    /*
    // Uncomment these methods to specify if an action menu should be displayed for the specified item, and react to actions performed on the item
    override func collectionView(_ collectionView: UICollectionView, shouldShowMenuForItemAt indexPath: IndexPath) -> Bool {
        return false
    }

    override func collectionView(_ collectionView: UICollectionView, canPerformAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return false
    }

    override func collectionView(_ collectionView: UICollectionView, performAction action: Selector, forItemAt indexPath: IndexPath, withSender sender: Any?) {
    
    }
    */

}
