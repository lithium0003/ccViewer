//
//  TableViewControllerItemsEdit.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/27.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import Photos

import RemoteCloud

class TableViewControllerItemsEdit: UITableViewController, UISearchResultsUpdating, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var rootPath: String = ""
    var rootFileId: String = ""
    var storageName: String = ""
    var upitemStr = "Upload Item"
    let activityIndicator = UIActivityIndicatorView()
    var result: [RemoteData] = [] {
        didSet {
            DispatchQueue.main.async {
                self.selectionLabel.text = "All : \(self.result_base.count)  Display : \(self.result.count) Selected : \(self.selection.count)"
            }
        }
    }
    var result_base: [RemoteData] = []
    let semaphore = DispatchSemaphore(value: 1)

    var gone = true
    var selection: [String] = [] {
        didSet {
            if selection.count == 0 {
                uploadButton.isHidden = false
                mkdirButton.isHidden = false
                renameButton.isHidden = true
                timeButton.isHidden = true
                moveButton.isHidden = true
                deleteButton.isHidden = true
            }
            else if selection.count == 1 {
                uploadButton.isHidden = true
                mkdirButton.isHidden = true
                renameButton.isHidden = false
                timeButton.isHidden = false
                moveButton.isHidden = false
                deleteButton.isHidden = false
            }
            else {
                uploadButton.isHidden = true
                mkdirButton.isHidden = true
                renameButton.isHidden = true
                timeButton.isHidden = true
                moveButton.isHidden = false
                deleteButton.isHidden = false
            }
            selectionLabel.text = "All : \(result_base.count)  Display : \(result.count) Selected : \(selection.count)"
        }
    }
    
    var uploadButton: UIButton!
    var mkdirButton: UIButton!
    var renameButton: UIButton!
    var timeButton: UIButton!
    var moveButton: UIButton!
    var deleteButton: UIButton!
    
    var selectionLabel: UILabel!
    var selectionButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.title = "Edit Items"
        
        let settingButton = UIBarButtonItem(image: UIImage(named: "gear"), style: .plain, target: self, action: #selector(settingButtonDidTap))
        
        navigationItem.rightBarButtonItem = settingButton
        navigationController?.navigationBar.barTintColor = UIColor(red: 0.9, green: 1, blue: 0.9, alpha: 1)

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        activityIndicator.center = tableView.center
        activityIndicator.style = .whiteLarge
        activityIndicator.color = .black
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
        self.result_base = self.result
        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
            CloudFactory.shared.data.getCloudMark(storage: self.storageName, parentID: self.rootFileId) {
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        
        definesPresentationContext = true

        let headerCell: UITableViewCell = tableView.dequeueReusableCell(withIdentifier: "header")!
        let headerView: UIView = headerCell.contentView
        let label = headerView.viewWithTag(1) as? UILabel
        label?.text = rootPath
        tableView.tableHeaderView = headerCell
        
        let upbutton = headerView.viewWithTag(2) as? UIButton
        let inbutton = headerView.viewWithTag(8) as? UIButton
        
        if storageName == "Local" {
            uploadButton = inbutton
            upbutton?.isHidden = true
            upitemStr = "Import Item"
        }
        else {
            uploadButton = upbutton
            inbutton?.isHidden = true
        }
        mkdirButton = headerView.viewWithTag(3) as? UIButton
        renameButton = headerView.viewWithTag(4) as? UIButton
        timeButton = headerView.viewWithTag(5) as? UIButton
        moveButton = headerView.viewWithTag(6) as? UIButton
        deleteButton = headerView.viewWithTag(7) as? UIButton
        
        selectionLabel = headerView.viewWithTag(10) as? UILabel
        selectionButton = headerView.viewWithTag(11) as? UIButton

        selection = []
        uploadButton.addTarget(self, action: #selector(uploadButtonDidTap), for: .touchUpInside)
        mkdirButton.addTarget(self, action: #selector(mkdirButtonDidTap), for: .touchUpInside)
        renameButton.addTarget(self, action: #selector(renameButtonDidTap), for: .touchUpInside)
        timeButton.addTarget(self, action: #selector(timeButtonDidTap), for: .touchUpInside)
        moveButton.addTarget(self, action: #selector(moveButtonDidTap), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteButtonDidTap), for: .touchUpInside)
        selectionButton.addTarget(self, action: #selector(checkButtonDidTap), for: .touchUpInside)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }

    override func viewWillAppear(_ animated: Bool) {
        navigationController?.isToolbarHidden = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }
    
    override func didMove(toParent parent: UIViewController?) {
        if parent == nil {
            gone = false
        }
    }

    func checkDupName(testName: String, onFinish: ((Bool)->Void)?) {
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
                
                for item in self.result {
                    if item.name == testName {
                        DispatchQueue.global().async {
                            onFinish?(false)
                        }
                        return
                    }
                }
                DispatchQueue.global().async {
                    onFinish?(true)
                }
            }
        }
    }
    
    @objc func refresh() {
        self.result = []
        self.tableView.reloadData()
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
    
    @objc func settingButtonDidTap(_ sender: UIBarButtonItem) {
        let next = storyboard!.instantiateViewController(withIdentifier: "Setting") as? TableViewControllerSetting
        
        self.navigationController?.pushViewController(next!, animated: true)
    }

    @objc func checkButtonDidTap(_ sender: UIBarButtonItem) {
        if selection.count > 0 {
            selection = []
        }
        else {
            selection = result.map { $0.id ?? "" }
        }
        tableView.reloadData()
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        if text.isEmpty {
            result = result_base
        } else {
            result = result_base
            result = result.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
        }
        tableView.reloadData()
    }
    
    @objc func uploadButtonDidTap(_ sender: UIButton) {

        let alert = UIAlertController(title: rootPath,
                                      message: upitemStr,
                                      preferredStyle: .actionSheet)

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let documentAction = UIAlertAction(title: "Document ...",
                                           style: .default,
                                           handler:{ action in

                                            let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .open)
                                            picker.delegate = self
                                            self.present(picker, animated: true, completion: nil)
        })
        let pictureAction = UIAlertAction(title: "Picture ...",
                                           style: .default,
                                           handler:{ action in
                                            PHPhotoLibrary.requestAuthorization() { status in
                                                guard status == .authorized else {
                                                    return
                                                }
                                                guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                                                    return
                                                }
                                                let picker = UIImagePickerController()
                                                picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
                                                picker.allowsEditing = false
                                                picker.delegate = self
                                                DispatchQueue.main.async {
                                                    self.present(picker, animated: true, completion: nil)
                                                }
                                            }
        })
        
        alert.addAction(documentAction)
        alert.addAction(pictureAction)
        alert.addAction(cancelAction)
        alert.popoverPresentationController?.sourceView = self.view
        alert.popoverPresentationController?.sourceRect = CGRect(x: self.view.frame.width/2, y: self.view.frame.height, width: 0, height: 0)
        present(alert, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var target: URL?
        let group = DispatchGroup()
        group.enter()
        if let mPhasset = info[UIImagePickerController.InfoKey.phAsset] as? PHAsset {
            switch mPhasset.mediaType {
            case .unknown:
                group.leave()
            case .image:
                let options: PHContentEditingInputRequestOptions = PHContentEditingInputRequestOptions()
                options.canHandleAdjustmentData = {(adjustmeta: PHAdjustmentData) -> Bool in
                    return true
                }
                mPhasset.requestContentEditingInput(with: options, completionHandler: { (contentEditingInput, info) in
                    target = contentEditingInput!.fullSizeImageURL
                    group.leave()
                })
            case .video:
                let options: PHVideoRequestOptions = PHVideoRequestOptions()
                options.version = .original
                PHImageManager.default().requestAVAsset(forVideo: mPhasset, options: options, resultHandler: {(asset, audioMix, info) in
                    if let urlAsset = asset as? AVURLAsset {
                        let localVideoUrl = urlAsset.url
                        target = localVideoUrl
                    }
                    group.leave()
                })
            case .audio:
                group.leave()
            @unknown default:
                group.leave()
            }
        }
        self.dismiss(animated: true, completion: nil)

        guard let service = CloudFactory.shared[storageName] else {
            return
        }
        group.notify(queue: .main) {
            guard let url = target else {
                return
            }
            let alert = UIAlertController(title: self.rootPath,
                                          message: self.upitemStr,
                                          preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
            let defaultAction = UIAlertAction(title: "OK",
                                              style: .default,
                                              handler:{ action in
                                                if let newname = alert.textFields?[0].text {
                                                    if newname == "" {
                                                        return
                                                    }
                                                    self.checkDupName(testName: newname) { success in
                                                        guard success else {
                                                            return
                                                        }

                                                        DispatchQueue.global().async {
                                                            CFURLStartAccessingSecurityScopedResource(url as CFURL)
                                                            defer {
                                                                CFURLStopAccessingSecurityScopedResource(url as CFURL)
                                                            }
                                                            let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                                                            do {
                                                                if FileManager.default.fileExists(atPath: tmpurl.path) {
                                                                    try FileManager.default.removeItem(at: tmpurl)
                                                                }
                                                                try FileManager.default.copyItem(at: url, to: tmpurl)
                                                            } catch {
                                                                return
                                                            }
                                                            service.upload(parentId: self.rootFileId, uploadname: newname, target: tmpurl) { id in
                                                                guard id != nil, self.gone else {
                                                                    return
                                                                }
                                                                DispatchQueue.main.asyncAfter(deadline: .now()) {
                                                                    self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                                    self.result_base = self.result
                                                                    self.tableView.reloadData()
                                                                }
                                                            }
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
                text.text = target?.lastPathComponent
            })
            
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let service = CloudFactory.shared[storageName] else {
            return
        }
        if let url = urls.first {
            let alert = UIAlertController(title: rootPath,
                                          message: upitemStr,
                                          preferredStyle: .alert)
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
            let defaultAction = UIAlertAction(title: "OK",
                                              style: .default,
                                              handler:{ action in
                                                if let newname = alert.textFields?[0].text {
                                                    if newname == "" {
                                                        return
                                                    }
                                                    self.checkDupName(testName: newname) { success in
                                                        guard success else {
                                                            return
                                                        }
                                                        DispatchQueue.global().async {
                                                            guard CFURLStartAccessingSecurityScopedResource(url as CFURL) else {
                                                                return
                                                            }
                                                            defer {
                                                                CFURLStopAccessingSecurityScopedResource(url as CFURL)
                                                            }
                                                            let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID.init().uuidString)
                                                            do {
                                                                if FileManager.default.fileExists(atPath: tmpurl.path) {
                                                                    try FileManager.default.removeItem(at: tmpurl)
                                                                }
                                                                try FileManager.default.copyItem(at: url, to: tmpurl)
                                                            }
                                                            catch let error {
                                                                print(error)
                                                                return
                                                            }
                                                            service.upload(parentId: self.rootFileId, uploadname: newname, target: tmpurl) { id in
                                                                guard id != nil, self.gone else {
                                                                    return
                                                                }
                                                                DispatchQueue.main.asyncAfter(deadline: .now()) {
                                                                    self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                                    self.result_base = self.result
                                                                    self.tableView.reloadData()
                                                                }
                                                            }
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
                text.text = url.lastPathComponent
            })
            
            present(alert, animated: true, completion: nil)
        }
    }
    
    @objc func mkdirButtonDidTap(_ sender: UIButton) {
        guard let service = CloudFactory.shared[storageName] else {
            return
        }
        let alert = UIAlertController(title: rootPath,
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
                                                
                                                self.checkDupName(testName: newname) { success in
                                                    guard success else {
                                                        return
                                                    }
                                                    DispatchQueue.main.async {
                                                        self.activityIndicator.startAnimating()
                                                    }
                                                    service.mkdir(parentId: self.rootFileId, newname: newname) { id in
                                                        if id != nil {
                                                            self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                            self.result_base = self.result
                                                        }
                                                        DispatchQueue.main.async {
                                                            self.activityIndicator.stopAnimating()
                                                            self.tableView.reloadData()
                                                        }
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
    
    @objc func renameButtonDidTap(_ sender: UIButton) {
        guard let id = selection.first, let item = CloudFactory.shared[storageName]?.get(fileId: id) else {
            return
        }
        let alert = UIAlertController(title: rootPath,
                                      message: "Rename",
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let defaultAction = UIAlertAction(title: "OK",
                                          style: .default,
                                          handler:{ action in
                                            if let newname = alert.textFields?[0].text {
                                                if newname == "" {
                                                    return
                                                }
                                                self.selection = []
                                                self.checkDupName(testName: newname) { success in
                                                    guard success else {
                                                        return
                                                    }
                                                    DispatchQueue.main.async {
                                                        self.activityIndicator.startAnimating()
                                                    }
                                                    item.rename(newname: newname) { id in
                                                        var result = "failed"
                                                        if id != nil {
                                                            self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                            self.result_base = self.result
                                                            result = "done"
                                                        }
                                                        DispatchQueue.main.async {
                                                            self.activityIndicator.stopAnimating()
                                                            self.tableView.reloadData()
                                                            
                                                            let alert2 = UIAlertController(title: "Result",
                                                                                           message: "rename \(result)",
                                                                preferredStyle: .alert)
                                                            let okAction = UIAlertAction(title: "OK", style: .default)
                                                            alert2.addAction(okAction)
                                                            
                                                            self.present(alert2, animated: true, completion: nil)
                                                        }
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
            text.text = item.name
            text.leftView = label
            text.leftViewMode = .always
            text.enablesReturnKeyAutomatically = true
        })
        
        present(alert, animated: true, completion: nil)
    }
    
    @objc func timeButtonDidTap(_ sender: UIButton) {
        guard let id = selection.first, let item = CloudFactory.shared[storageName]?.get(fileId: id) else {
            return
        }
        
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .dateAndTime
        datePicker.setDate(item.mDate ?? Date(), animated: false)

        let alert = UIAlertController(title: "\n\n\n\n\n\n\n\n",
                                      message: nil,
                                      preferredStyle: .alert)

        alert.view.addSubview(datePicker)
        datePicker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor).isActive = true

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let defaultAction = UIAlertAction(title: "OK",
                                          style: .default,
                                          handler:{ action in
                                            self.selection = []
                                            DispatchQueue.main.async {
                                                self.activityIndicator.startAnimating()
                                            }
                                            item.changetime(newdate: datePicker.date) { id in
                                                var result = "failed"
                                                if id != nil {
                                                    self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                    self.result_base = self.result
                                                    result = "done"
                                                }
                                                DispatchQueue.main.async {
                                                    self.activityIndicator.stopAnimating()
                                                    self.tableView.reloadData()
                                                    
                                                    let alert2 = UIAlertController(title: "Result",
                                                                                   message: "Time change \(result)",
                                                        preferredStyle: .alert)
                                                    let okAction = UIAlertAction(title: "OK", style: .default)
                                                    alert2.addAction(okAction)
                                                    
                                                    self.present(alert2, animated: true, completion: nil)
                                                }
                                            }
        })
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)

        present(alert, animated: true, completion: nil)
    }
    
    @objc func moveButtonDidTap(_ sender: UIButton) {
        let items = selection.map({ CloudFactory.shared[storageName]?.get(fileId: $0 ) }).compactMap { $0 }
        
        let alert = UIAlertController(title: "Move \(items.count) items",
                                      message: "select target folder",
            preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let defaultAction = UIAlertAction(title: "OK",
                                          style: .default,
                                          handler:{ action in
                                            self.selection = []
                                            DispatchQueue.main.async {
                                                let root = ViewControllerPathSelect()
                                                root.storageName = self.storageName
                                                root.rootPath = "\(self.storageName):/"
                                                root.rootFileId = ""
                                                root.onCancel = {
                                                    self.navigationController?.popToViewController(self, animated: true)
                                                }
                                                root.onDone = { rootid in
                                                    self.navigationController?.popToViewController(self, animated: true)
                                                    self.activityIndicator.startAnimating()
                                                    let group = DispatchGroup()
                                                    var scount = 0
                                                    for item in items {
                                                        group.enter()
                                                        DispatchQueue.global().async {
                                                            item.move(toParentId: rootid) { id in
                                                                if id != nil {
                                                                    scount += 1
                                                                }
                                                                group.leave()
                                                            }
                                                        }
                                                    }
                                                    group.notify(queue: .global()) {
                                                        self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                        self.result_base = self.result
                                                        DispatchQueue.main.async {
                                                            self.activityIndicator.stopAnimating()
                                                            self.tableView.reloadData()
                                                            
                                                            let alert2 = UIAlertController(title: "Result",
                                                                                           message: "Move \(scount)/\(items.count) items",
                                                                preferredStyle: .alert)
                                                            let okAction = UIAlertAction(title: "OK", style: .default)
                                                            alert2.addAction(okAction)
                                                            
                                                            self.present(alert2, animated: true, completion: nil)
                                                        }
                                                    }
                                                }
                                                self.navigationController?.pushViewController(root, animated: true)
                                            }
        })
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    @objc func deleteButtonDidTap(_ sender: UIButton) {
        let items = selection.map({ CloudFactory.shared[storageName]?.get(fileId: $0 ) }).compactMap { $0 }

        let alert = UIAlertController(title: rootPath,
                                      message: "Delete \(items.count) items",
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        let defaultAction = UIAlertAction(title: "OK",
                                          style: .default,
                                          handler:{ action in
                                            self.selection = []
                                            self.activityIndicator.startAnimating()
                                            let group = DispatchGroup()
                                            var scount = 0
                                            for item in items {
                                                group.enter()
                                                item.delete() { success in
                                                    if success {
                                                        scount += 1
                                                    }
                                                    group.leave()
                                                }
                                            }
                                            group.notify(queue: .global()) {
                                                self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                self.result_base = self.result
                                                DispatchQueue.main.async {
                                                    self.activityIndicator.stopAnimating()
                                                    self.tableView.reloadData()
                                                    
                                                    let alert2 = UIAlertController(title: "Result",
                                                                                  message: "Delete \(scount)/\(items.count) items",
                                                        preferredStyle: .alert)
                                                    let okAction = UIAlertAction(title: "OK", style: .default)
                                                    alert2.addAction(okAction)

                                                    self.present(alert2, animated: true, completion: nil)
                                                }
                                            }
        })
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)

        present(alert, animated: true, completion: nil)
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
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Item", for: indexPath)
        
        // Configure the cell...
        
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byWordWrapping
        cell.textLabel?.text = result[indexPath.row].name
        
        if result[indexPath.row].folder {
            if selection.contains(result[indexPath.row].id ?? "") {
                cell.accessoryType = .checkmark
            }
            else {
                cell.accessoryType = .disclosureIndicator
            }
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
        else {
            if selection.contains(result[indexPath.row].id ?? "") {
                cell.accessoryType = .checkmark
            }
            else {
                cell.accessoryType = .none
            }
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
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr) bytes"
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
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        if semaphore.wait(wallTimeout: .now()) == .timedOut {
            return
        }

        let cell = tableView.cellForRow(at: indexPath)
        
        if selection.contains(result[indexPath.row].id ?? "") {
            selection.removeAll(where: { $0 == result[indexPath.row].id ?? "" })
            if result[indexPath.row].folder {
                cell?.accessoryType = .disclosureIndicator
            }
            else {
                cell?.accessoryType = .none
            }
        }
        else {
            selection += [result[indexPath.row].id ?? ""]
            cell?.accessoryType = .checkmark
        }
        
        semaphore.signal()
    }
}

class ViewControllerPathSelect: UIViewController, UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate {
    var tableView: UITableView!
    var activityIndicator: UIActivityIndicatorView!
    var refreshControl: UIRefreshControl!
    
    var rootPath: String = ""
    var rootFileId: String = ""
    var storageName: String = ""
    
    var onCancel: (()->Void)!
    var onDone: ((String)->Void)!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView = UITableView()
        tableView.frame = view.frame
        
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.tableFooterView = UIView(frame: .zero)
        
        view.addSubview(tableView)
        
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonDidTap))
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonDidTap))
        
        navigationItem.rightBarButtonItems = [doneButton, cancelButton]
        
        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        activityIndicator = UIActivityIndicatorView()
        activityIndicator.center = tableView.center
        activityIndicator.style = .whiteLarge
        activityIndicator.color = .black
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        
        self.title = rootPath
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if rootFileId == "" {
            navigationItem.hidesBackButton = true
        }
    }
    
    @objc func refresh() {
        CloudFactory.shared[storageName]?.list(fileId: rootFileId) {
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.refreshControl.endRefreshing()
            }
        }
    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let result = CloudFactory.shared.data.listData(storage: storageName, parentID: rootFileId)
        return result.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        // Configure the cell...
        
        let result = CloudFactory.shared.data.listData(storage: storageName, parentID: rootFileId)
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
            cell.detailTextLabel?.text = "\(tStr)\tfolder"
            cell.backgroundColor = UIColor.init(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0)
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
            cell.detailTextLabel?.text = "\(tStr)\t\(sStr) bytes"
            cell.backgroundColor = .white
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
        
        let result = CloudFactory.shared.data.listData(storage: storageName, parentID: rootFileId)
        if result[indexPath.row].folder {
            if let path = result[indexPath.row].path {
                let next = ViewControllerPathSelect()
                
                next.rootPath = path
                next.rootFileId = result[indexPath.row].id ?? ""
                next.storageName = storageName
                next.onCancel = onCancel
                next.onDone = onDone
                let newroot = CloudFactory.shared.data.listData(storage: storageName, parentID: next.rootFileId)
                if newroot.count == 0 {
                    activityIndicator.startAnimating()
                    
                    CloudFactory.shared[storageName]?.list(fileId: result[indexPath.row].id ?? "") {
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            self.navigationController?.pushViewController(next, animated: true)
                        }
                    }
                }
                else {
                    self.navigationController?.pushViewController(next, animated: true)
                }
            }
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        activityIndicator.center = tableView.center
        activityIndicator.center.y = tableView.bounds.size.height/2 + tableView.contentOffset.y
    }
    
    @objc func cancelButtonDidTap(_ sender: UIBarButtonItem)
    {
        onCancel()
    }
    
    @objc func doneButtonDidTap(_ sender: UIBarButtonItem)
    {
        onDone(rootFileId)
    }
}
