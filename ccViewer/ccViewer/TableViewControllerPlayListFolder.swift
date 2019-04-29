//
//  TableViewControllerPlayListFolder.swift
//  ccViewer
//
//  Created by rei6 on 2019/04/12.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class TableViewControllerPlayListFolder: UITableViewController, UISearchResultsUpdating {

    var listItem: [[String: Any]] = []
    var filtered: [Int] = []
    var selected: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("Select Folder", comment: "")
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        filtered = Array(0..<self.listItem.count)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.isToolbarHidden = true
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        if text.isEmpty {
            filtered = Array(0..<self.listItem.count)
        } else {
            filtered = listItem.enumerated().filter({ ($1["name"] as? String)?.lowercased().contains(text.lowercased()) ?? false}).map({ $0.offset })
        }
        tableView.reloadData()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return filtered.count
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item", for: indexPath)
        
        // Configure the cell...
        let filterdItem = self.listItem.enumerated().filter({ filtered.contains($0.offset) }).map({ $1 })
        
        var name = filterdItem[indexPath.row]["name"] as? String
        if name == "" {
            name = "(root)"
            cell.backgroundColor = UIColor.init(red: 1.0, green: 0.95, blue: 0.9, alpha: 1.0)
        }
        else {
            cell.backgroundColor = UIColor.init(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0)
        }
        
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        cell.textLabel?.text = name
        cell.accessoryType = .none
        cell.detailTextLabel?.text = ""

        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        selected = listItem[filtered[indexPath.row]]["name"] as? String
        navigationController?.popViewController(animated: true)
    }
    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
