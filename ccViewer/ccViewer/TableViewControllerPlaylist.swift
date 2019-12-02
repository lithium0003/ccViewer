//
//  TableViewControllerPlaylist.swift
//  ccViewer
//
//  Created by rei6 on 2019/04/12.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

import RemoteCloud
import ffplayer

class TableViewControllerPlaylist: UITableViewController, UISearchResultsUpdating {

    var listItem: [[String: Any]] = []
    var filtered: [Int] = []
    var folderName: String = ""

    var playallItem: UIBarButtonItem!
    var playloopItem: UIBarButtonItem!
    var playshuffleItem: UIBarButtonItem!
    var editlistItem: UIBarButtonItem!
    var flexible: UIBarButtonItem!

    var settingButton: UIBarButtonItem!
    var refreshButton: UIBarButtonItem!
    var uploadButton: UIBarButtonItem!
    
    var folderview: TableViewControllerPlayListFolder?
    let activityIndicator = UIActivityIndicatorView()

    let semaphore = DispatchSemaphore(value: 1)
    var gone = true

    var player: CustomPlayerView?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        self.title = (folderName == "") ? "PlayList" : folderName
        
        settingButton = UIBarButtonItem(image: UIImage(named: "gear"), style: .plain, target: self, action: #selector(settingButtonDidTap))
        refreshButton = UIBarButtonItem(image: UIImage(named: "import"), style: .plain, target: self, action: #selector(refreshButtonDidTap))
        uploadButton = UIBarButtonItem(image: UIImage(named: "up"), style: .plain, target: self, action: #selector(uploadButtonDidTap))
        
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

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        playallItem = UIBarButtonItem(image: UIImage(named: "playall"), style: .plain, target: self, action: #selector(barButtonPlayAllTapped))
        playloopItem = UIBarButtonItem(image: UIImage(named: "loop"), style: .plain, target: self, action: #selector(barButtonPlayLoopTapped))
        playshuffleItem = UIBarButtonItem(image: UIImage(named: "shuffle"), style: .plain, target: self, action: #selector(barButtonPlayShuffleTapped))
        editlistItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(barButtonEditTapped))
        flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem]

        definesPresentationContext = true
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            gone = false
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !tableView.isEditing && UserDefaults.standard.bool(forKey: "cloudPlaylist") {
            navigationItem.rightBarButtonItems = [settingButton, refreshButton, uploadButton]
        }
        else {
            navigationItem.rightBarButtonItems = [settingButton]
        }
        
        if UserDefaults.standard.bool(forKey: "playloop") {
            playloopItem.image = UIImage(named: "loop_inv")
        }
        else {
            playloopItem.image = UIImage(named: "loop")
        }
        if UserDefaults.standard.bool(forKey: "playshuffle") {
            playshuffleItem.image = UIImage(named: "shuffle_inv")
        }
        else {
            playshuffleItem.image = UIImage(named: "shuffle")
        }

        let group = DispatchGroup()
        self.activityIndicator.startAnimating()
        if let folderview = self.folderview {
            if let target = folderview.selected {
                if let selectedRows = tableView.indexPathsForSelectedRows {
                    for selIdx in selectedRows.map(({ $0.row })) {
                        let item = listItem[filtered[selIdx]]
                        var newItem = item
                        newItem["folder"] = target
                        listItem[filtered[selIdx]] = newItem
                        CloudFactory.shared.data.updatePlaylist(prevItem: item, newItem: newItem)
                    }
                }
            }
            self.folderview = nil
        }
        
        group.notify(queue: .main) {
            self.navigationController?.navigationBar.barTintColor = nil
            self.navigationController?.isToolbarHidden = false
            
            let group = DispatchGroup()
            self.setupListItem(group: group)
            group.notify(queue: .main) {
                let text = self.navigationItem.searchController?.searchBar.text ?? ""
                if text.isEmpty {
                    self.filtered = Array(0..<self.listItem.count)
                } else {
                    self.filtered = self.listItem.enumerated().filter({ ($1["name"] as? String)?.lowercased().contains(text.lowercased()) ?? false}).map({ $0.offset })
                }
                self.tableView.reloadData()
                self.activityIndicator.stopAnimating()
            }
        }
    }

    @objc func barButtonPlayLoopTapped(_ sender: UIBarButtonItem) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "playloop"), forKey: "playloop")
        if UserDefaults.standard.bool(forKey: "playloop") {
            playloopItem.image = UIImage(named: "loop_inv")
        }
        else {
            playloopItem.image = UIImage(named: "loop")
        }
    }
    
    @objc func barButtonPlayShuffleTapped(_ sender: UIBarButtonItem) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "playshuffle"), forKey: "playshuffle")
        if UserDefaults.standard.bool(forKey: "playshuffle") {
            playshuffleItem.image = UIImage(named: "shuffle_inv")
        }
        else {
            playshuffleItem.image = UIImage(named: "shuffle")
        }
    }
    
    @objc func barButtonPlayAllTapped(_ sender: UIBarButtonItem) {
        if semaphore.wait(wallTimeout: .now()) == .timedOut {
            return
        }
        semaphore.signal()

        var media = false
        if UserDefaults.standard.bool(forKey: "MediaViewer") {
            media = listItem.enumerated().filter({ filtered.contains($0.offset) }).map({ $1 }).allSatisfy { item in
                item["isFolder"] as? Bool ?? true ||
                (item["result"] as? RemoteData)?.ext == "mov" || (item["result"] as? RemoteData)?.ext == "mp4" || (item["result"] as? RemoteData)?.ext == "mp3" || (item["result"] as? RemoteData)?.ext == "wav" || (item["result"] as? RemoteData)?.ext == "aac"
            }
        }
        if UserDefaults.standard.bool(forKey: "FFplayer") && UserDefaults.standard.bool(forKey: "firstFFplayer") {
            media = false
        }
        
        if media {
            player = CustomPlayerView()
            let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
            let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
            player?.playItems = listItem.enumerated().filter({ filtered.contains($0.offset) }).map({ $1 }).filter({ !($0["isFolder"] as? Bool ?? true)}).map({ $0["result"] as! RemoteData }).filter({ !$0.folder }).map({ item in
                let storage = item.storage ?? ""
                let id = item.id ?? ""
                var playitem: [String: Any] = ["storage": storage, "id": id]
                if skip > 0 {
                    playitem["start"] = Double(skip)
                }
                if stop > 0 {
                    playitem["stop"] = Double(skip+stop)
                }
                return playitem
            })
            player?.shuffle = UserDefaults.standard.bool(forKey: "playshuffle")
            player?.loop = UserDefaults.standard.bool(forKey: "playloop")

            player?.onFinish = { position in
            }

            if player?.playItems.count ?? 0 > 0 {
                self.player?.play(parent: self)
            }
        }
        else {
            var playItems = [RemoteItem]()
            for aitem in listItem.enumerated().filter({ filtered.contains($0.offset) }).map({ $1 }).filter({ !($0["isFolder"] as? Bool ?? true)}).map({ $0["result"] as! RemoteData }).filter({ !$0.folder })
            {
                if let item = CloudFactory.shared[aitem.storage ?? ""]?.get(fileId: aitem.id ?? "") {
                    playItems += [item]
                }
            }

            if playItems.count > 0 {
                Player.play(parent: self, items: playItems, shuffle: UserDefaults.standard.bool(forKey: "playshuffle"), loop: UserDefaults.standard.bool(forKey: "playloop")) { finish in
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }

    @objc func barButtonEditTapped(_ sender: UIBarButtonItem) {
        if semaphore.wait(wallTimeout: .now()) == .timedOut {
            return
        }
        semaphore.signal()
        
        tableView.isEditing = !tableView.isEditing
        if tableView.isEditing {
            let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(barButtonDeleteTapped))
            let allButton = UIBarButtonItem(image: UIImage(named: "check"), style: .plain, target: self, action: #selector(barButtonAllTapped))
            let folderButton = UIBarButtonItem(image: UIImage(named: "newfolder"), style: .plain, target: self, action: #selector(barButtonFolderTapped))
            let moveButton = UIBarButtonItem(title: NSLocalizedString("Move", comment: ""), style: .plain, target: self, action: #selector(barButtonMoveTapped))
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(barButtonEditTapped))
            toolbarItems = [deleteButton, flexible, folderButton, flexible, allButton, flexible, moveButton, flexible, doneButton]
            navigationItem.rightBarButtonItems = [settingButton]
            tableView.reloadData()
        }
        else {
            CloudFactory.shared.data.touchPlaylist(items: listItem)
            toolbarItems = [flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem]
            if UserDefaults.standard.bool(forKey: "cloudPlaylist") {
                navigationItem.rightBarButtonItems = [settingButton, refreshButton, uploadButton]
            }
            else {
                navigationItem.rightBarButtonItems = [settingButton]
            }
            tableView.reloadData()
        }
    }

    @objc func barButtonMoveTapped(_ sender: UIBarButtonItem) {
        if let selectedRows = tableView.indexPathsForSelectedRows, selectedRows.count > 0, selectedRows.allSatisfy({ !(listItem[filtered[$0.row]]["isFolder"] as? Bool ?? false) }) {
            folderview = storyboard!.instantiateViewController(withIdentifier: "PlayListFolder") as? TableViewControllerPlayListFolder
            folderview?.listItem = listItem.filter({ $0["isFolder"] as? Bool ?? false }).filter({ $0["name"] as? String != self.folderName })
            if folderName != "" {
                folderview?.listItem += [["name": "", "isFolder": true]]
            }
            
            navigationController?.pushViewController(folderview!, animated: true)
        }
    }
    
    @objc func barButtonFolderTapped(_ sender: UIBarButtonItem) {
        let alert = UIAlertController(title: "PlayList",
                                      message: "Add new Folder",
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let defaultAction = UIAlertAction(title: "OK",
                                          style: .default,
                                          handler:{ action in
                                            if let newname = alert.textFields?[0].text {
                                                if newname == "" {
                                                    return
                                                }
                                                if self.listItem.filter({ $0["isFolder"] as? Bool ?? false }).allSatisfy({ $0["name"] as? String != newname }) {
                                                    self.listItem += [["name": newname, "isFolder": true]]
                                                    self.listItem = self.listItem.sorted(by: { $0["name"] as? String ?? "" < $1["name"] as? String ?? "" }).sorted(by: { $0["index"] as? Int64 ?? -1 < $1["index"] as? Int64 ?? -1}).sorted(by: { ($0["isFolder"] as? Bool ?? false ? 0 : 1) < ($1["isFolder"] as? Bool ?? false ? 0 : 1) })
                                                    DispatchQueue.main.async {
                                                        let text = self.navigationItem.searchController?.searchBar.text ?? ""
                                                        if text.isEmpty {
                                                            self.filtered = Array(0..<self.listItem.count)
                                                        } else {
                                                            self.filtered = self.listItem.enumerated().filter({ ($1["name"] as? String)?.lowercased().contains(text.lowercased()) ?? false}).map({ $0.offset })
                                                        }
                                                        self.tableView.reloadData()
                                                    }
                                                }
                                            }
        })
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)
        
        alert.addTextField(configurationHandler: {(text:UITextField!) -> Void in
            text.placeholder = "new name"
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 50, height: 30))
            label.text = "Name"
            text.leftView = label
            text.leftViewMode = .always
            text.enablesReturnKeyAutomatically = true
        })
        
        present(alert, animated: true, completion: nil)
    }
    
    @objc func barButtonAllTapped(_ sender: UIBarButtonItem) {
        if let selectedIndexPaths = tableView.indexPathsForSelectedRows, selectedIndexPaths.count == filtered.count {
            for selectedIndexPath in selectedIndexPaths {
                tableView.deselectRow(at: selectedIndexPath, animated: true)
            }
        }
        else {
            if let selectedIndexPaths = tableView.indexPathsForSelectedRows {
                let selectIdx = selectedIndexPaths.map({ $0.row })
                if selectIdx.map({ listItem[filtered[$0]] }).allSatisfy({ $0["isFolder"] as? Bool ?? false }) {
                    let nonFolder = filtered.filter({ !(listItem[$0]["isFolder"] as? Bool ?? false) })
                    if nonFolder.count > 0 {
                        for selectedIndexPath in nonFolder.map({ IndexPath(row: $0, section: 0) }) {
                            tableView.selectRow(at: selectedIndexPath, animated: true, scrollPosition: .none)
                        }
                        return
                    }
                }
            }
            else {
                let nonFolder = filtered.filter({ !(listItem[$0]["isFolder"] as? Bool ?? false) })
                if nonFolder.count > 0 {
                    for selectedIndexPath in nonFolder.map({ IndexPath(row: $0, section: 0) }) {
                        tableView.selectRow(at: selectedIndexPath, animated: true, scrollPosition: .none)
                    }
                    return
                }
            }
            let allIndexPath = filtered.map({ IndexPath(row: $0, section: 0) })
            for selectedIndexPath in allIndexPath {
                tableView.selectRow(at: selectedIndexPath, animated: true, scrollPosition: .none)
            }
        }
    }
    
    @objc func barButtonDeleteTapped(_ sender: UIBarButtonItem) {
        if let selectedRows = tableView.indexPathsForSelectedRows {
            let delIdx = selectedRows.map(({ $0.row }))
            let group = DispatchGroup()
            self.activityIndicator.startAnimating()
            var addDel = [Int]()
            let playlist = CloudFactory.shared.data.getPlaylist()
            for idx in delIdx {
                if listItem[filtered[idx]]["isFolder"] as? Bool ?? false {
                    addDel += playlist.enumerated().filter({ $1["folder"] as? String == listItem[filtered[idx]]["name"] as? String }).map({ $0.offset })
                }
            }
            for idx in delIdx.sorted(by: >) {
                let delItem = listItem.remove(at: filtered[idx])
                let text = self.navigationItem.searchController?.searchBar.text ?? ""
                if text.isEmpty {
                    filtered = Array(0..<self.listItem.count)
                }
                else {
                    filtered = listItem.enumerated().filter({ ($1["name"] as? String)?.lowercased().contains(text.lowercased()) ?? false}).map({ $0.offset })
                }
                CloudFactory.shared.data.updatePlaylist(prevItem: delItem, newItem: [:])
            }
            for idx in addDel.sorted(by: >) {
                let delItem = playlist[idx]
                CloudFactory.shared.data.updatePlaylist(prevItem: delItem, newItem: [:])
            }
            group.notify(queue: .main) {
                self.tableView.beginUpdates()
                self.tableView.deleteRows(at: selectedRows, with: .automatic)
                self.tableView.endUpdates()
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    func setupListItem(group: DispatchGroup) {
        let playlist = CloudFactory.shared.data.getPlaylist()
        let result = playlist.map({ CloudFactory.shared.data.getData(storage: $0["storage"] as? String ?? "", fileId: $0["id"] as? String ?? "")})
        let existList = playlist.enumerated().map({ (i, element)->[String: Any] in
            if let name = result[i]?.name {
                var ret = element
                ret["name"] = name
                ret["result"] = result[i]!
                ret["isFolder"] = false
                return ret
            }
            else {
                return [:]
            }
        }).filter({ $0.count > 0})
        CloudFactory.shared.data.touchPlaylist(items: existList)

        let playlist2 = CloudFactory.shared.data.getPlaylist()
        if self.folderName != "" {
            let items = playlist2.filter({ $0["folder"] as? String == self.folderName })
            let result = items.map({ CloudFactory.shared.data.getData(storage: $0["storage"] as? String ?? "", fileId: $0["id"] as? String ?? "")})
            self.listItem = items.enumerated().map({ (i, element)->[String: Any] in
                if let name = result[i]?.name {
                    var ret = element
                    ret["name"] = name
                    ret["result"] = result[i]!
                    ret["isFolder"] = false
                    return ret
                }
                else {
                    return [:]
                }
            }).filter({ $0.count > 0}).sorted(by: { $0["name"] as? String ?? "" < $1["name"] as? String ?? "" }).sorted(by: { $0["index"] as? Int64 ?? -1 < $1["index"] as? Int64 ?? -1})
        }
        else {
            let folders = Array(Set(playlist2.map({ $0["folder"] as? String}))).filter({$0 != nil && $0 != ""}).sorted(by: { $0 ?? "" < $1 ?? "" })
            self.listItem = folders.map({ ["name": $0!, "isFolder": true] })
            let items = playlist2.filter({ $0["folder"] as? String == self.folderName })
            let result = items.map({ CloudFactory.shared.data.getData(storage: $0["storage"] as? String ?? "", fileId: $0["id"] as? String ?? "")})
            self.listItem += items.enumerated().map({ (i, element)->[String: Any] in
                if let name = result[i]?.name {
                    var ret = element
                    ret["name"] = name
                    ret["result"] = result[i]!
                    ret["isFolder"] = false
                    return ret
                }
                else {
                    return [:]
                }
            }).filter({ $0.count > 0 }).sorted(by: { $0["name"] as? String ?? "" < $1["name"] as? String ?? "" }).sorted(by: { $0["index"] as? Int64 ?? -1 < $1["index"] as? Int64 ?? -1})
        }
    }
    
    @objc func refreshButtonDidTap(_ sender: UIBarButtonItem) {
        guard UserDefaults.standard.bool(forKey: "cloudPlaylist") else {
            return
        }
        self.activityIndicator.startAnimating()
        self.listItem = []
        self.filtered = []
        DispatchQueue.main.async {
            self.tableView.reloadData()
            CloudFactory.shared.data.getCloudPlaylist {
                let group = DispatchGroup()
                self.setupListItem(group: group)
                group.notify(queue: .main) {
                    let text = self.navigationItem.searchController?.searchBar.text ?? ""
                    if text.isEmpty {
                        self.filtered = Array(0..<self.listItem.count)
                    } else {
                        self.filtered = self.listItem.enumerated().filter({ ($1["name"] as? String)?.lowercased().contains(text.lowercased()) ?? false}).map({ $0.offset })
                    }
                    self.tableView.reloadData()
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }

    @objc func uploadButtonDidTap(_ sender: UIBarButtonItem) {
        guard UserDefaults.standard.bool(forKey: "cloudPlaylist") else {
            return
        }
        self.activityIndicator.startAnimating()
        CloudFactory.shared.data.uploadCloudPlaylist {
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
            }
        }
    }

    @objc func settingButtonDidTap(_ sender: UIBarButtonItem) {
        let next = storyboard!.instantiateViewController(withIdentifier: "Setting") as? TableViewControllerSetting
        
        self.navigationController?.pushViewController(next!, animated: true)
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
        
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        cell.textLabel?.text = filterdItem[indexPath.row]["name"] as? String
        cell.detailTextLabel?.text = ""

        cell.detailTextLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        guard let formatString = DateFormatter.dateFormat(fromTemplate: "yyyyMMdd", options: 0, locale: Locale.current) else { fatalError() }

        if filterdItem[indexPath.row]["isFolder"] as? Bool ?? false {
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = UIColor(named: "FolderColor")
        }
        else {
            cell.accessoryType = .none
            var tStr = ""
            if let mdate = (filterdItem[indexPath.row]["result"] as? RemoteData)?.mdate {
                let f = DateFormatter()
                f.dateFormat = formatString + " HH:mm:ss"
                tStr = f.string(from: mdate)
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            let sStr = formatter.string(from: (filterdItem[indexPath.row]["result"] as? RemoteData)?.size as NSNumber? ?? 0) ?? "0"
            let formatter2 = ByteCountFormatter()
            formatter2.allowedUnits = [.useAll]
            formatter2.countStyle = .file
            let sStr2 = formatter2.string(fromByteCount: Int64((filterdItem[indexPath.row]["result"] as? RemoteData)?.size ?? 0))
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.lineBreakMode = .byWordWrapping
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr2) (\(sStr) bytes) \t\((filterdItem[indexPath.row]["result"] as? RemoteData)?.subinfo ?? "")"
            if #available(iOS 13.0, *) {
                cell.backgroundColor = UIColor.systemBackground
            } else {
                cell.backgroundColor = UIColor.white
            }
        }
        return cell
    }

    
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return tableView.isEditing
    }
    
    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            let delItem = listItem.remove(at: filtered[indexPath.row])
            let text = self.navigationItem.searchController?.searchBar.text ?? ""
            if text.isEmpty {
                filtered = Array(0..<self.listItem.count)
            }
            else {
                filtered = listItem.enumerated().filter({ ($1["name"] as? String)?.lowercased().contains(text.lowercased()) ?? false}).map({ $0.offset })
            }
            CloudFactory.shared.data.updatePlaylist(prevItem: delItem, newItem: [:])
            if UserDefaults.standard.bool(forKey: "cloudPlaylist") {
                CloudFactory.shared.data.updatePlaylistCloud(prevItem: delItem, newItem: [:])
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
    */
    
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
        let fromIdx = filtered[fromIndexPath.row]
        let toIdx = filtered[to.row]
        let fromTmp = listItem[fromIdx]
        listItem.remove(at: fromIdx)
        listItem.insert(fromTmp, at: toIdx)
        let minIdx = min(fromIdx, toIdx)
        let maxIdx = max(fromIdx, toIdx)
        let index = listItem[minIdx...maxIdx].map({ $0["index"] as? Int64 ?? -1 }).sorted()
        for (i,j) in zip(0..<index.count, minIdx...maxIdx) {
            var tmp = listItem[j]
            tmp["index"] = index[i]
            CloudFactory.shared.data.updatePlaylist(prevItem: listItem[j], newItem: tmp)
            listItem[j] = tmp
        }
    }


    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            return
        }
        
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        if semaphore.wait(wallTimeout: .now()) == .timedOut {
            return
        }

        let target = listItem[filtered[indexPath.row]]
        if target["isFolder"] as? Bool ?? false {
            semaphore.signal()
            let next = storyboard!.instantiateViewController(withIdentifier: "PlayList") as? TableViewControllerPlaylist
            next?.folderName = target["name"] as? String ?? ""
            navigationController?.pushViewController(next!, animated: true)
        }
        else {
            if let item = CloudFactory.shared[target["storage"] as? String ?? ""]?.get(fileId: target["id"] as? String ?? "") {
                if UserDefaults.standard.bool(forKey: "FFplayer") && UserDefaults.standard.bool(forKey: "firstFFplayer") {
                    semaphore.signal()
                    playFFmpeg(item: item) { finish in
                        if finish {
                            return
                        }
                        DispatchQueue.main.async {
                            self.activityIndicator.startAnimating()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                            self.activityIndicator.stopAnimating()
                            self.autoDetectRun(item: item)
                        }
                    }
                }
                else {
                    autoDetectRun(item: item)
                }
            }
        }
    }
    
    func autoDetectRun(item: RemoteItem) {
        guard gone else {
            return
        }
        if UserDefaults.standard.bool(forKey: "MediaViewer") && (item.ext == "mov" || item.ext == "mp4" || item.ext == "mp3" || item.ext == "wav" || item.ext == "aac") {
            
            displayMediaViewer(item: item, fallback: true)
        }
        else {
            DispatchQueue.main.async {
                self.activityIndicator.startAnimating()
            }
            DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                self.activityIndicator.stopAnimating()
                self.fallbackView(item: item)
            }
        }
    }

    func playFFmpeg(item: RemoteItem, onFinish: @escaping (Bool)->Void) {
        Player.play(parent: self, item: item, start: nil) { position in
            DispatchQueue.main.async {
                self.navigationController?.popToViewController(self, animated: true)
                onFinish(position != nil)
                self.tableView.reloadData()
            }
        }
    }
    
    func fallbackView(item: RemoteItem) {
        guard gone else {
            return
        }
        if UserDefaults.standard.bool(forKey: "FFplayer") && !UserDefaults.standard.bool(forKey: "firstFFplayer") {
            self.semaphore.signal()
            self.playFFmpeg(item: item) { finish in
                if finish {
                    return
                }
                self.semaphore.wait()
                DispatchQueue.main.async {
                    self.activityIndicator.startAnimating()
                }
                DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                    defer {
                        self.activityIndicator.stopAnimating()
                    }
                    guard self.gone else {
                        return
                    }
                    self.displayRawViewer(item: item)
                }
            }
        }
        else {
            semaphore.signal()
            displayRawViewer(item: item)
        }
    }

    func displayRawViewer(item: RemoteItem) {
        let next = self.storyboard!.instantiateViewController(withIdentifier: "TextView") as? ViewControllerText
        next?.setData(data: item)
        self.semaphore.signal()
        self.navigationController?.pushViewController(next!, animated: true)
    }
    
    func displayMediaViewer(item: RemoteItem, fallback: Bool) {
        player = CustomPlayerView()

        let playitem: [String: Any] = ["storage": item.storage, "id": item.id]
        player?.playItems = [playitem]
        player?.onFinish = { position in
            if position == nil && fallback {
                self.semaphore.wait()
                self.activityIndicator.startAnimating()
                DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                    self.activityIndicator.stopAnimating()
                    self.fallbackView(item: item)
                }
            }
        }

        semaphore.signal()
        self.player?.play(parent: self)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
