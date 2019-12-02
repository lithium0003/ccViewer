//
//  TableViewController.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/06.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import CoreData

import RemoteCloud

class TableViewControllerRoot: UITableViewController {

    let activityIndicator = UIActivityIndicatorView()
    var storage: [String] = []
    var storageShow: [String] = []
    let semaphore = DispatchSemaphore(value: 1)

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.title = "Root"
        
        let settingButton = UIBarButtonItem(image: UIImage(named: "gear"), style: .plain, target: self, action: #selector(settingButtonDidTap))
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonDidTap))
        
        navigationItem.rightBarButtonItems = [settingButton, addButton]
        
        navigationItem.leftBarButtonItem = editButtonItem
            
        activityIndicator.center = tableView.center
        if #available(iOS 13.0, *) {
            activityIndicator.style = .large
        } else {
            activityIndicator.style = .whiteLarge
        }
        activityIndicator.layer.cornerRadius = 10
        activityIndicator.color = .white
        activityIndicator.backgroundColor = UIColor(white: 0, alpha: 0.8)
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.widthAnchor.constraint(equalToConstant: 100).isActive = true
        activityIndicator.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let allStorages = CloudFactory.shared.storages
        if let prev1 = UserDefaults.standard.array(forKey: "ShowingStorages"), let prevShowing = prev1 as? [String] {
            storageShow = prevShowing
        }
        else {
            storageShow = allStorages
        }
        if let prev0 = UserDefaults.standard.array(forKey: "AllStorages"), let prevAll = prev0 as? [String] {
            storage = prevAll
            let newStorage = allStorages.filter { !storage.contains($0) }
            storage.append(contentsOf: newStorage)
            storageShow = storage.filter { storageShow.contains($0) || newStorage.contains($0) }
        }
        else {
            storage = allStorages
        }
    }

    func saveListItems() {
        UserDefaults.standard.set(storage, forKey: "AllStorages")
        UserDefaults.standard.set(storageShow, forKey: "ShowingStorages")
    }
    
    @objc func settingButtonDidTap(_ sender: UIBarButtonItem)
    {
        let next = storyboard!.instantiateViewController(withIdentifier: "Setting") as? TableViewControllerSetting
        
        self.navigationController?.pushViewController(next!, animated: true)
    }
    
    @objc func addButtonDidTap(_ sender: UIBarButtonItem)
    {
        let next = storyboard!.instantiateViewController(withIdentifier: "AddCloud") as? CollectionViewControllerCloud
        
        self.navigationController?.pushViewController(next!, animated: true)
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        tableView.isEditing = editing
        tableView.reloadData()
        super.setEditing(editing, animated: animated)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return tableView.isEditing ? storage.count : storageShow.count
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item", for: indexPath)

        let name = tableView.isEditing ? storage[indexPath.row] : storageShow[indexPath.row]
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        cell.textLabel?.text = name
        if let service = CloudFactory.shared[name]?.getStorageType() {
            let image = CloudFactory.shared.getIcon(service: service)
            cell.imageView?.image = image
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        if semaphore.wait(wallTimeout: .now()) == .timedOut {
            return
        }
        
        activityIndicator.startAnimating()
        let next = storyboard!.instantiateViewController(withIdentifier: "Main") as? TableViewControllerItems
        let name = tableView.isEditing ? storage[indexPath.row] : storageShow[indexPath.row]
        CloudFactory.shared[name]?.list(fileId: "") {
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                next?.rootPath = "\(name):/"
                next?.rootFileId = ""
                next?.storageName = name
                self.semaphore.signal()
                self.navigationController?.pushViewController(next!, animated: true)
            }
        }
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            let name = tableView.isEditing ? storage[indexPath.row] : storageShow[indexPath.row]
            if name == "Local" {
                return
            }
            
            let alart0 = UIAlertController(title: "Remove Item", message: NSString(format: NSLocalizedString("Select 'Just hide on menu' / 'Log out'", comment: "") as NSString, name) as String, preferredStyle: .alert)

            let hideAction = UIAlertAction(title: NSLocalizedString("Just hide on menu", comment: ""), style: .default) { action in
                let hideItem = self.storage[indexPath.row]
                if let hideIndex = self.storageShow.firstIndex(of: hideItem) {
                    self.storageShow.remove(at: hideIndex)
                }
                self.saveListItems()
                tableView.reloadData()
            }
            
            let deleteAction = UIAlertAction(title: NSLocalizedString("Logout and Delete", comment: ""), style: .destructive) { action in
                
                let alart = UIAlertController(title: "Logout", message: NSString(format: NSLocalizedString("Logout from %@ and remove item", comment: "") as NSString, name) as String, preferredStyle: .alert)
                let delAction = UIAlertAction(title: NSLocalizedString("Logout and Delete", comment: ""), style: .destructive) { action in
                    CloudFactory.shared.delStorage(tagname: name)
                    
                    let allItems = CloudFactory.shared.storages
                    self.storage = self.storage.filter(allItems.contains)
                    self.storageShow = self.storageShow.filter(allItems.contains)
                    self.saveListItems()
                    tableView.reloadData()
                }
                let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
                alart.addAction(delAction)
                alart.addAction(cancelAction)
                
                self.present(alart, animated: true, completion: nil)
            }

            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)

            alart0.addAction(hideAction)
            alart0.addAction(deleteAction)
            alart0.addAction(cancelAction)
            
            present(alart0, animated: true, completion: nil)
        }
        else if editingStyle == .insert {
            let insertItem = storage[indexPath.row]
            storageShow = storage.filter { storageShow.contains($0) || $0 == insertItem }
            saveListItems()
            tableView.reloadData()
        }
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if tableView.isEditing {
            if storageShow.contains(storage[indexPath.row]) {
                return .delete
            }
            else {
                return .insert
            }
        }
        return .none
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        
        let element = storage.remove(at: sourceIndexPath.row)
        storage.insert(element, at: destinationIndexPath.row)
        storageShow = storage.filter(storageShow.contains)
        saveListItems()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
        let allstorage = CloudFactory.shared.storages
        let newItem = allstorage.filter { !storage.contains($0) }
        storage.append(contentsOf: newItem)
        storageShow.append(contentsOf: newItem)
        saveListItems()
        tableView.reloadData()
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }
}
