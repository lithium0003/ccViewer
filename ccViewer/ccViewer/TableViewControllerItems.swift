//
//  TableViewControllerItems.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/11.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import PDFKit

import RemoteCloud
import ffplayer

class TableViewControllerItems: UITableViewController, UISearchResultsUpdating, UIDocumentInteractionControllerDelegate {
    var rootPath: String = ""
    var rootFileId: String = ""
    var storageName: String = ""
    var subItem = false
    let activityIndicator = UIActivityIndicatorView()
    var result: [RemoteData] = []
    var result_base: [RemoteData] = []
    let semaphore = DispatchSemaphore(value: 1)
    var gone = true

    var sending: [URL] = []
    var documentInteractionController: UIDocumentInteractionController?
    
    var playlistItem: UIBarButtonItem!
    var playallItem: UIBarButtonItem!
    var editlistItem: UIBarButtonItem!
    var flexible: UIBarButtonItem!
    var playloopItem: UIBarButtonItem!
    var playshuffleItem: UIBarButtonItem!

    var editting = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.title = rootPath
        
        let settingButton = UIBarButtonItem(image: UIImage(named: "gear"), style: .plain, target: self, action: #selector(settingButtonDidTap))
        let editButton = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(editButtonDidTap))

        if subItem {
            navigationItem.rightBarButtonItem = settingButton
        }
        else {
            navigationItem.rightBarButtonItems = [settingButton, editButton]
        }
        
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)

        activityIndicator.center = tableView.center
        activityIndicator.style = .whiteLarge
        activityIndicator.color = .black
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        
        playlistItem = UIBarButtonItem(image: UIImage(named: "playlist"), style: .plain, target: self, action: #selector(barButtonPlayListTapped))
        playallItem = UIBarButtonItem(image: UIImage(named: "playall"), style: .plain, target: self, action: #selector(barButtonPlayAllTapped))
        editlistItem = UIBarButtonItem(image: UIImage(named: "addplay"), style: .plain, target: self, action: #selector(barButtonEditListTapped))
        playloopItem = UIBarButtonItem(image: UIImage(named: "loop"), style: .plain, target: self, action: #selector(barButtonPlayLoopTapped))
        playshuffleItem = UIBarButtonItem(image: UIImage(named: "shuffle"), style: .plain, target: self, action: #selector(barButtonPlayShuffleTapped))
        flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [playlistItem, flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem]
        
        definesPresentationContext = true
        editting = true        
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
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
        
        navigationController?.navigationBar.barTintColor = nil
        navigationController?.isToolbarHidden = false

        self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
        self.result_base = self.result
        let text = self.navigationItem.searchController?.searchBar.text ?? ""
        if !text.isEmpty {
            self.result = self.result.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
        }
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            CloudFactory.shared.data.getCloudMark(storage: self.storageName, parentID: self.rootFileId) {
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
        editting = false
        self.tableView.reloadData()
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            gone = false
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
    

    @objc func barButtonPlayListTapped(_ sender: UIBarButtonItem) {
        let next = storyboard!.instantiateViewController(withIdentifier: "PlayList") as? TableViewControllerPlaylist
        
        self.navigationController?.pushViewController(next!, animated: true)
    }
    
    @objc func barButtonEditListTapped(_ sender: UIBarButtonItem) {
        tableView.isEditing = !tableView.isEditing
        if tableView.isEditing {
            let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(barButtonDoneTapped))
            let selectionButton = UIBarButtonItem(image: UIImage(named: "check"), style: .plain, target: self, action: #selector(barButtonSelectTapped))
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(barButtonEditListTapped))
            toolbarItems = [cancelButton, flexible, selectionButton, flexible, doneButton]
        }
        else {
            toolbarItems = [playlistItem, flexible, playallItem, flexible, editlistItem]
        }
        tableView.reloadData()
    }

    @objc func barButtonSelectTapped(_ sender: UIBarButtonItem) {
        if let selectedIndexPaths = tableView.indexPathsForSelectedRows, selectedIndexPaths.count == result.count {
            for selectedIndexPath in selectedIndexPaths {
                tableView.deselectRow(at: selectedIndexPath, animated: true)
            }
        }
        else {
            let allIndexPath = result.enumerated().map({ IndexPath(row: $0.offset, section: 0) })
            for selectedIndexPath in allIndexPath {
                tableView.selectRow(at: selectedIndexPath, animated: true, scrollPosition: .none)
            }
        }
    }
    
    @objc func barButtonDoneTapped(_ sender: UIBarButtonItem) {
        let group = DispatchGroup()
        activityIndicator.startAnimating()
        if let selectedRows = tableView.indexPathsForSelectedRows {
            for indexPath in selectedRows {
                let item = result[indexPath.row]
                if item.folder {
                    continue
                }
                var newItem = [String: Any]()
                newItem["id"] = item.id
                newItem["storage"] = item.storage
                newItem["folder"] = ""
                
                CloudFactory.shared.data.updatePlaylist(prevItem: [:], newItem: newItem)
            }
        }
        group.notify(queue: .main) {
            self.tableView.isEditing = false
            self.toolbarItems = [self.playlistItem, self.flexible, self.playloopItem, self.flexible, self.playallItem, self.flexible, self.playshuffleItem, self.flexible, self.editlistItem]
            self.tableView.reloadData()
            self.activityIndicator.stopAnimating()
        }
    }

    @objc func barButtonPlayAllTapped(_ sender: UIBarButtonItem) {
        var media = false
        if UserDefaults.standard.bool(forKey: "MediaViewer") {
            media = result.allSatisfy { item in
                item.folder ||
                item.ext == "mov" || item.ext == "mp4" || item.ext == "mp3" || item.ext == "wav" || item.ext == "aac"
            }
        }
        
        if media {
            let next = CustomPlayerViewController()
            next.playItems = result.filter({ !$0.folder }).map({ item in
                let storage = item.storage ?? ""
                let id = item.id ?? ""
                let playitem: [String: Any] = ["storage": storage, "id": id]
                return playitem
            })
            next.shuffle = UserDefaults.standard.bool(forKey: "playshuffle")
            next.loop = UserDefaults.standard.bool(forKey: "playloop")

            next.onFinish = { position in
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    self.navigationController?.popToViewController(self, animated: true)
                }
            }
            
            if next.playItems.count > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    self.navigationController?.pushViewController(next, animated: false)
                }
            }
        }
        else {
            let base = ViewControllerFFplayer()
            base.view.backgroundColor = .black
            navigationController?.pushViewController(base, animated: true)
            
            var playItems = [RemoteItem]()
            for aitem in result.filter({ !$0.folder }) {
                if let item = CloudFactory.shared[aitem.storage ?? ""]?.get(fileId: aitem.id ?? "") {
                    playItems += [item]
                }
            }
            
            if playItems.count > 0 {
                Player.play(items: playItems, shuffle: UserDefaults.standard.bool(forKey: "playshuffle"), loop: UserDefaults.standard.bool(forKey: "playloop"), fontsize: 60) { finish in
                    DispatchQueue.main.async {
                        self.navigationController?.popToViewController(self, animated: true)
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    @objc func refresh() {
        self.result = []
        self.tableView.reloadData()
        if subItem {
            (CloudFactory.shared[storageName] as? RemoteSubItem)?.listsubitem(fileId: self.rootFileId) {
                DispatchQueue.main.async {
                    self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                    self.result_base = self.result
                    let text = self.navigationItem.searchController?.searchBar.text ?? ""
                    if text.isEmpty {
                        self.result = self.result_base
                    } else {
                        self.result = self.result_base
                        self.result = self.result.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
                    }
                    if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                        CloudFactory.shared.data.getCloudMark(storage: self.storageName, parentID: self.rootFileId) {
                            DispatchQueue.main.async {
                                self.tableView.reloadData()
                                self.refreshControl?.endRefreshing()
                            }
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            self.tableView.reloadData()
                            self.refreshControl?.endRefreshing()
                        }
                    }
                }
            }
        }
        else {
            CloudFactory.shared[storageName]?.list(fileId: rootFileId) {
                DispatchQueue.main.async {
                    self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                    self.result_base = self.result
                    let text = self.navigationItem.searchController?.searchBar.text ?? ""
                    if text.isEmpty {
                        self.result = self.result_base
                    } else {
                        self.result = self.result_base
                        self.result = self.result.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
                    }
                    if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                        CloudFactory.shared.data.getCloudMark(storage: self.storageName, parentID: self.rootFileId) {
                            DispatchQueue.main.async {
                                self.tableView.reloadData()
                                self.refreshControl?.endRefreshing()
                            }
                        }
                    }
                    else {
                        DispatchQueue.main.async {
                            self.tableView.reloadData()
                            self.refreshControl?.endRefreshing()
                        }
                    }
                }
            }
        }
    }
    
    @objc func settingButtonDidTap(_ sender: UIBarButtonItem) {
        let next = storyboard!.instantiateViewController(withIdentifier: "Setting") as? TableViewControllerSetting
        
        self.navigationController?.pushViewController(next!, animated: true)
    }

    @objc func editButtonDidTap(_ sender: UIBarButtonItem) {
        let next = storyboard!.instantiateViewController(withIdentifier: "MainEdit") as? TableViewControllerItemsEdit
        
        next?.rootPath = rootPath
        next?.rootFileId = rootFileId
        next?.storageName = storageName
        
        editting = true
        self.navigationController?.pushViewController(next!, animated: false)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        if text.isEmpty {
            result = result_base
        } else {
            result = result.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
        }
        tableView.reloadData()
    }

    @IBAction func cellLongPressed(_ sender: UILongPressGestureRecognizer) {
        let point = sender.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point) else {
            return
        }
        if sender.state == .began {
            guard !result[indexPath.row].folder else {
                return
            }
            guard let item = CloudFactory.shared[storageName]?.get(fileId: result[indexPath.row].id ?? "") else {
                return
            }
            let alert = UIAlertController(title: item.name,
                                          message: nil,
                                          preferredStyle: .actionSheet)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
            let defaultAction = UIAlertAction(title: NSLocalizedString("Export ...", comment: ""),
                                              style: .default,
                                              handler:{ action in
                                                let cell = self.tableView.cellForRow(at: indexPath)
                                                self.exportItem(item: item, rect: CGRect(x: cell?.frame.midX ?? 0, y: cell?.frame.midY ?? 0, width: 0, height: 0))
            })
            let defaultAction2 = UIAlertAction(title: NSLocalizedString("Toggle Mark", comment: ""),
                                              style: .default,
                                              handler:{ action in
                                                let pos = CloudFactory.shared.data.getMark(storage: item.storage, targetID: item.id)
                                                if pos != nil {
                                                    CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: nil)
                                                    let group = DispatchGroup()
                                                    self.activityIndicator.startAnimating()
                                                    if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                                                        CloudFactory.shared.data.setCloudMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: nil, group: group)
                                                    }
                                                    group.notify(queue: .main) {
                                                        self.tableView.reloadRows(at: [indexPath], with: .automatic)
                                                        self.activityIndicator.stopAnimating()
                                                    }
                                                }
                                                else {
                                                    CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: 0)
                                                    let group = DispatchGroup()
                                                    self.activityIndicator.startAnimating()
                                                    if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                                                        CloudFactory.shared.data.setCloudMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: 0, group: group)
                                                        
                                                    }
                                                    group.notify(queue: .main) {
                                                        self.tableView.reloadRows(at: [indexPath], with: .automatic)
                                                        self.activityIndicator.stopAnimating()
                                                    }
                                                }
                                                
            })
            let defaultAction4 = UIAlertAction(title: NSLocalizedString("Media player", comment: ""),
                                               style: .default,
                                               handler:{ action in
                                                if self.semaphore.wait(wallTimeout: .now()) == .timedOut {
                                                    return
                                                }
                                                self.displayMediaViewer(item: item, fallback: false)
            })
            let defaultAction5 = UIAlertAction(title: NSLocalizedString("Sofware player", comment: ""),
                                               style: .default,
                                               handler:{ action in
                                                self.playFFmpeg(item: item, onFinish: { finish in
                                                })
            })
            let defaultAction6 = UIAlertAction(title: NSLocalizedString("Force open with ...", comment: ""),
                                               style: .default,
                                               handler:{ action in
                                                let alert2 = UIAlertController(title: item.name,
                                                                              message: nil,
                                                                              preferredStyle: .actionSheet)
                                                let cancelAction2 = UIAlertAction(title: "Cancel", style: .cancel)
                                                let defaultAction61 = UIAlertAction(title: NSLocalizedString("as Image", comment: ""),
                                                                                    style: .default,
                                                                                    handler:{ action in
                                                                                        self.displayImageViewer(item: item, fallback: false)
                                                                                    })
                                                let defaultAction62 = UIAlertAction(title: NSLocalizedString("as PDF", comment: ""),
                                                                                    style: .default,
                                                                                    handler:{ action in
                                                                                        self.displayPDFViewer(item: item, fallback: false)
                                                })
                                                let defaultAction63 = UIAlertAction(title: NSLocalizedString("as Raw binay", comment: ""),
                                                                                   style: .default,
                                                                                   handler:{ action in
                                                                                    self.displayRawViewer(item: item)
                                                })
                                                alert2.addAction(cancelAction2)
                                                alert2.addAction(defaultAction61)
                                                alert2.addAction(defaultAction62)
                                                alert2.addAction(defaultAction63)

                                                let cell = self.tableView.cellForRow(at: indexPath)
                                                alert2.popoverPresentationController?.sourceView = self.tableView
                                                alert2.popoverPresentationController?.sourceRect = CGRect(x: cell?.frame.midX ?? 0, y: cell?.frame.midY ?? 0, width: 0, height: 0)
                                                
                                                self.present(alert2, animated: true, completion: nil)

                                                })
            alert.addAction(cancelAction)
            alert.addAction(defaultAction)
            alert.addAction(defaultAction2)
            alert.addAction(defaultAction4)
            alert.addAction(defaultAction5)
            alert.addAction(defaultAction6)

            let cell = tableView.cellForRow(at: indexPath)
            alert.popoverPresentationController?.sourceView = tableView
            alert.popoverPresentationController?.sourceRect = CGRect(x: cell?.frame.midX ?? 0, y: cell?.frame.midY ?? 0, width: 0, height: 0)
            
            present(alert, animated: true, completion: nil)
        }
    }
    
    func writeTempfile(file: URL,stream: RemoteStream, pos: Int64, size: Int64, onFinish: @escaping ()->Void) {
        var len = 1024*1024
        guard gone else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        if pos + Int64(len) > size {
            len = Int(size - pos)
        }
        if len > 0 {
            stream.read(position: pos, length: len) { data in
                if let data = data {
                    let output = OutputStream(url: file, append: true)
                    output?.open()
                    let count = data.withUnsafeBytes() { bytes in
                        output?.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count) ?? 0
                    }
                    if count > 0 {
                        self.writeTempfile(file: file, stream: stream, pos: pos + Int64(count), size: size, onFinish: onFinish)
                    }
                    else {
                        onFinish()
                    }
                }
                else {
                    onFinish()
                }
            }
        }
        else {
            onFinish()
        }
    }
    
    func exportItem(item: RemoteItem, rect: CGRect) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory()) else {
            return
        }
        let freesize = (attributes[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        if item.size >= freesize {
            let alart = UIAlertController(title: "No storage", message: "item is too big", preferredStyle: .alert)
            let okButton = UIAlertAction(title: "OK", style: .default, handler: nil)
            alart.addAction(okButton)
            present(alart, animated: true, completion: nil)
        }
        guard let url = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(item.name) else {
            return
        }
        activityIndicator.startAnimating()

        let stream = item.open()
        writeTempfile(file: url, stream: stream, pos: 0, size: item.size) {
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()

                self.documentInteractionController = UIDocumentInteractionController.init(url: url)
                self.documentInteractionController?.delegate = self
                if self.documentInteractionController?.presentOpenInMenu(from: rect, in: self.tableView, animated: true) ?? false {
                }
                else {
                    let alart = UIAlertController(title: "No share app", message: "item cannot be handled", preferredStyle: .alert)
                    let okButton = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alart.addAction(okButton)
                    self.present(alart, animated: true, completion: nil)
                }
            }
        }
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        if let url = controller.url {
            if !sending.contains(url) {
                try? FileManager.default.removeItem(at: url)
                sending.removeAll(where: { $0 == url } )
            }
        }
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, willBeginSendingToApplication application: String?) {
        if let url = controller.url {
            sending += [url]
        }
    }
    
    func documentInteractionController(_ controller: UIDocumentInteractionController, didEndSendingToApplication application: String?) {
        if let url = controller.url {
            try? FileManager.default.removeItem(at: url)
            sending.removeAll(where: { $0 == url } )
        }
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return result.count
    }

    func hasSubItem(name: String?) -> Bool {
        return name?.lowercased().hasSuffix(".cue") ?? false
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item", for: indexPath)

        // Configure the cell...

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        cell.textLabel?.text = result[indexPath.row].name
        
        if result[indexPath.row].folder {
            cell.accessoryType = .disclosureIndicator
            var tStr = ""
            if result[indexPath.row].mdate != nil {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .medium
                tStr = f.string(from: result[indexPath.row].mdate!)
            }
            cell.detailTextLabel?.text = "\(tStr) \tfolder"
            cell.backgroundColor = UIColor.init(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0)
        }
        else if hasSubItem(name: result[indexPath.row].name) {
            cell.accessoryType = .disclosureIndicator
            var tStr = ""
            if result[indexPath.row].mdate != nil {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .medium
                tStr = f.string(from: result[indexPath.row].mdate!)
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            let sStr = formatter.string(from: result[indexPath.row].size as NSNumber) ?? "0"
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.lineBreakMode = .byWordWrapping
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr) bytes \t\(result[indexPath.row].subinfo ?? "")"
            cell.backgroundColor = UIColor.init(red: 0.95, green: 1.0, blue: 0.95, alpha: 1.0)
        }
        else {
            cell.accessoryType = .none
            var tStr = ""
            if result[indexPath.row].mdate != nil {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .medium
                tStr = f.string(from: result[indexPath.row].mdate!)
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            let sStr = formatter.string(from: result[indexPath.row].size as NSNumber) ?? "0"
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.lineBreakMode = .byWordWrapping
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr) bytes \t\(result[indexPath.row].subinfo ?? "")"
            if let storage = result[indexPath.row].storage, let id = result[indexPath.row].id {
                let localpos = CloudFactory.shared.data.getMark(storage: storage, targetID: id)
                if localpos != nil {
                    cell.backgroundColor = UIColor.init(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
                }
                else {
                    cell.backgroundColor = .white
                }
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            return
        }
        
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        if semaphore.wait(wallTimeout: .now()) == .timedOut {
            return
        }
        
        if result[indexPath.row].folder {
            if let path = result[indexPath.row].path {
                let next = storyboard!.instantiateViewController(withIdentifier: "Main") as? TableViewControllerItems

                next?.rootPath = path
                next?.rootFileId = result[indexPath.row].id ?? ""
                next?.storageName = storageName
                let newroot = CloudFactory.shared.data.listData(storage: storageName, parentID: next?.rootFileId ?? "")
                if newroot.count == 0 {
                    activityIndicator.startAnimating()
                    
                    CloudFactory.shared[storageName]?.list(fileId: result[indexPath.row].id ?? "") {
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            self.semaphore.signal()
                            self.navigationController?.pushViewController(next!, animated: true)
                        }
                    }
                }
                else {
                    semaphore.signal()
                    self.navigationController?.pushViewController(next!, animated: true)
                }
            }
        }
        else if hasSubItem(name: result[indexPath.row].name) {
            if let path = result[indexPath.row].path {
                let next = storyboard!.instantiateViewController(withIdentifier: "Main") as? TableViewControllerItems
                
                next?.rootPath = path
                next?.rootFileId = result[indexPath.row].id ?? ""
                next?.storageName = storageName
                next?.subItem = true
                let newroot = CloudFactory.shared.data.listData(storage: storageName, parentID: next?.rootFileId ?? "")
                if newroot.count == 0 {
                    activityIndicator.startAnimating()
                    
                    (CloudFactory.shared[storageName] as? RemoteSubItem)?.listsubitem(fileId: result[indexPath.row].id ?? "") {
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            self.semaphore.signal()
                            self.navigationController?.pushViewController(next!, animated: true)
                        }
                    }
                }
                else {
                    semaphore.signal()
                    self.navigationController?.pushViewController(next!, animated: true)
                }
            }
        }
        else {
            if let item = CloudFactory.shared[storageName]?.get(fileId: result[indexPath.row].id ?? "") {
                
                if item.ext == "txt" {
                    semaphore.signal()
                    self.displayRawViewer(item: item)
                }
                else if UserDefaults.standard.bool(forKey: "FFplayer") && UserDefaults.standard.bool(forKey: "firstFFplayer") {
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
        if UserDefaults.standard.bool(forKey: "ImageViewer") && (item.ext == "tif" || item.ext == "tiff" || item.ext == "heic" || item.ext == "jpg" || item.ext == "jpeg" || item.ext == "gif" || item.ext == "png" || item.ext == "bmp" || item.ext == "ico" || item.ext ==  "cur" || item.ext == "xbm") {
            
            displayImageViewer(item: item, fallback: true)
        }
        else if UserDefaults.standard.bool(forKey: "MediaViewer") && (item.ext == "mov" || item.ext == "mp4" || item.ext == "mp3" || item.ext == "wav" || item.ext == "aac") {
            
            displayMediaViewer(item: item, fallback: true)
        }
        else if UserDefaults.standard.bool(forKey: "PDFViewer") && (item.ext == "pdf") {
            displayPDFViewer(item: item, fallback: true)
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
        let base = ViewControllerFFplayer()
        base.view.backgroundColor = .black
        navigationController?.pushViewController(base, animated: true)
        let localpos = UserDefaults.standard.bool(forKey: "resumePlaypos") ? CloudFactory.shared.data.getMark(storage: item.storage, targetID: item.id) : nil
        Player.play(item: item, start: localpos, fontsize: 60) { position in
            self.navigationController?.popToViewController(self, animated: true)
            let group = DispatchGroup()
            if let pos = position {
                if UserDefaults.standard.bool(forKey: "savePlaypos") {
                    if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                        CloudFactory.shared.data.setCloudMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: pos, group: group)
                    }
                    group.notify(queue: .main) {
                        CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: pos)
                    }
                }
            }
            group.notify(queue: .main) {
                self.tableView.reloadData()
                onFinish(position != nil)
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
    
    func displayImageViewer(item: RemoteItem, fallback: Bool) {
        let prevRoot = UIApplication.topViewController()
        activityIndicator.startAnimating()
        let stream = item.open()
        stream.read(position: 0, length: Int(item.size)) { data in
            if let data = data, let image = UIImage(data: data), let fixedImage = image.fixedOrientation() {
                DispatchQueue.main.async {
                    let next = self.storyboard!.instantiateViewController(withIdentifier: "ImageView") as? ViewControllerImage
                    next?.imagedata = fixedImage
                    self.activityIndicator.stopAnimating()
                    self.semaphore.signal()
                    prevRoot?.present(next!, animated: true, completion: nil)
                }
            }
            else {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    if fallback {
                        self.fallbackView(item: item)
                    }
                }
            }
        }
    }
    
    func displayPDFViewer(item: RemoteItem, fallback: Bool) {
        let prevRoot = UIApplication.topViewController()
        activityIndicator.startAnimating()
        let stream = item.open()
        stream.read(position: 0, length: Int(item.size)) { data in
            if let data = data, let document = PDFDocument(data: data) {
                DispatchQueue.main.async {
                    let next = self.storyboard!.instantiateViewController(withIdentifier: "PDFView") as? ViewControllerPDF
                    next?.document = document
                    self.activityIndicator.stopAnimating()
                    self.semaphore.signal()
                    prevRoot?.present(next!, animated: true, completion: nil)
                }
            }
            else {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    if fallback {
                        self.fallbackView(item: item)
                    }
                }
            }
        }
    }
    
    func displayMediaViewer(item: RemoteItem, fallback: Bool) {
        let next = CustomPlayerViewController()
        
        let localpos = UserDefaults.standard.bool(forKey: "resumePlaypos") ? CloudFactory.shared.data.getMark(storage: item.storage, targetID: item.id) : nil
        var playitem: [String: Any] = ["storage": storageName, "id": item.id]
        if let start = localpos {
            playitem["start"] = start
        }
        next.playItems = [playitem]
        next.onFinish = { position in
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.navigationController?.popToViewController(self, animated: true)
            }
            if let pos = position {
                if UserDefaults.standard.bool(forKey: "savePlaypos") {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        let group = DispatchGroup()
                        self.activityIndicator.startAnimating()
                        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                            CloudFactory.shared.data.setCloudMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: pos, group: group)
                        }
                        group.notify(queue: .main) {
                            CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: pos)
                            self.activityIndicator.stopAnimating()
                            self.tableView.reloadData()
                        }
                    }
                }
            }
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
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            self.navigationController?.pushViewController(next, animated: false)
        }
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

// https://gist.github.com/schickling/b5d86cb070130f80bb40
extension UIImage {
    
    /// Fix image orientaton to protrait up
    func fixedOrientation() -> UIImage? {
        guard imageOrientation != UIImage.Orientation.up else {
            // This is default orientation, don't need to do anything
            return self.copy() as? UIImage
        }
        
        guard let cgImage = self.cgImage else {
            // CGImage is not available
            return nil
        }
        
        guard let colorSpace = cgImage.colorSpace, let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil // Not able to create CGContext
        }
        
        var transform: CGAffineTransform = CGAffineTransform.identity
        
        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: CGFloat.pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2.0)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: CGFloat.pi / -2.0)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }
        
        // Flip image one more time if needed to, this is to prevent flipped image
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        @unknown default:
            break
        }
        
        ctx.concatenate(transform)
        
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            break
        }
        
        guard let newCGImage = ctx.makeImage() else { return nil }
        return UIImage.init(cgImage: newCGImage, scale: 1, orientation: .up)
    }
}
