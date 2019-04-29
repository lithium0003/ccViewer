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
        
        activityIndicator.center = tableView.center
        activityIndicator.style = .whiteLarge
        activityIndicator.color = .black
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        storage = CloudFactory.shared.storages
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
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return storage.count
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item", for: indexPath)

        let name = storage[indexPath.row]
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
        let name = CloudFactory.shared.storages[indexPath.row]
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
            let name = CloudFactory.shared.storages[indexPath.row]
            if name == "Local" {
                return
            }
            
            let alart = UIAlertController(title: "Logout", message: NSString(format: NSLocalizedString("Logout from %@ and remove item", comment: "") as NSString, name) as String, preferredStyle: .alert)
            let delAction = UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { action in
                CloudFactory.shared.delStorage(tagname: name)
                
                self.storage = CloudFactory.shared.storages
                tableView.reloadData()
            }
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
            alart.addAction(delAction)
            alart.addAction(cancelAction)
            
            present(alart, animated: true, completion: nil)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = true
        storage = CloudFactory.shared.storages
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
