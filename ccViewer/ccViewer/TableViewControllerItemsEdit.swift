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

extension TableViewControllerItemsEdit: SortItemsDelegate {
    func DoSort() {
        let order = UserDefaults.standard.integer(forKey: "ItemSortOrder")
        switch order {
        case 0:
            result_base = result_base.sorted(by: { in1, in2 in (in1.name ?? "") < (in2.name  ?? "")} )
        case 1:
            result_base = result_base.sorted(by: { in1, in2 in (in1.name ?? "") > (in2.name  ?? "")} )
        case 2:
            result_base = result_base.sorted(by: { in1, in2 in in1.size < in2.size } )
        case 3:
            result_base = result_base.sorted(by: { in1, in2 in in1.size > in2.size } )
        case 4:
            result_base = result_base.sorted(by: { in1, in2 in (in1.mdate ?? Date(timeIntervalSince1970: 0)) < (in2.mdate ?? Date(timeIntervalSince1970: 0)) } )
        case 5:
            result_base = result_base.sorted(by: { in1, in2 in (in1.mdate ?? Date(timeIntervalSince1970: 0)) > (in2.mdate ?? Date(timeIntervalSince1970: 0)) } )
        default:
            result_base = result_base.sorted(by: { in1, in2 in (in1.name ?? "") < (in2.name  ?? "")} )
        }
        let folders = result_base.filter({ $0.folder })
        let files = result_base.filter({ !$0.folder })
        result_base = folders
        result_base += files

        DispatchQueue.main.async {
            // filter
            let text = self.navigationItem.searchController?.searchBar.text ?? ""
            if text.isEmpty {
                self.result = self.result_base
            } else {
                self.result = self.result_base.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
            }
            
            self.tableView.reloadData()
        }
    }
}

extension TableViewControllerItemsEdit: UploadManagerDelegate {
    func didRefreshItems() {
        if var buttons = navigationItem.rightBarButtonItems {
            if UploadManeger.shared.uploadCount > 0, !buttons.contains(UploadManeger.shared.UploadCountButton) {
                buttons += [UploadManeger.shared.UploadCountButton]
                navigationItem.rightBarButtonItems = buttons
            }
            if UploadManeger.shared.uploadCount == 0, let i = buttons.firstIndex(of: UploadManeger.shared.UploadCountButton) {
                buttons.remove(at: i)
                navigationItem.rightBarButtonItems = buttons
            }
        }
    }
    
    // for iPhone
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

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
    
    var headerView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.title = "Edit Items"
        
        let settingButton = UIBarButtonItem(image: UIImage(named: "gear"), style: .plain, target: self, action: #selector(settingButtonDidTap))
        
        navigationItem.rightBarButtonItem = settingButton
        navigationController?.navigationBar.barTintColor = UIColor(named: "NavigationEditColor")

        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
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

        self.result_base = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
        self.DoSort()
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
        headerView = headerCell.contentView
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
        super.viewWillAppear(animated)
        
        UploadManeger.shared.delegate = self
        didRefreshItems()

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
            semaphore.signal()
        }
    }

    func checkDupName(testNames: [String], onFinish: (([Bool])->Void)?) {
        CloudFactory.shared[storageName]?.list(fileId: rootFileId) {
            self.result_base = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
            self.DoSort()
        
            var ret: [Bool] = []
            for testName in testNames {
                var pass = true
                for item in self.result {
                    if item.name == testName {
                        pass = false
                        break
                    }
                }
                ret += [pass]
            }
            DispatchQueue.global().async {
                onFinish?(ret)
            }
        }
    }
    
    @objc func refresh() {
        self.result = []
        self.tableView.reloadData()
        CloudFactory.shared[storageName]?.list(fileId: rootFileId) {
            self.result_base = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
            self.DoSort()
            DispatchQueue.global().async {
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
            result = result_base.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
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
                                            picker.allowsMultipleSelection = true
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
                                                DispatchQueue.main.async {
                                                    let picker = UIImagePickerController()
                                                    picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
                                                    picker.allowsEditing = false
                                                    picker.delegate = self
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
                                                    self.checkDupName(testNames: [newname]) { success in
                                                        guard success[0] else {
                                                            return
                                                        }
                                                        let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                                                        let sessionId = UUID().uuidString
                                                        UploadManeger.shared.UploadStart(identifier: sessionId, filename: newname)

                                                        DispatchQueue.global().async {
                                                            do {
                                                                CFURLStartAccessingSecurityScopedResource(url as CFURL)
                                                                defer {
                                                                    CFURLStopAccessingSecurityScopedResource(url as CFURL)
                                                                }
                                                                do {
                                                                    if FileManager.default.fileExists(atPath: tmpurl.path) {
                                                                        try FileManager.default.removeItem(at: tmpurl)
                                                                    }
                                                                    try FileManager.default.copyItem(at: url, to: tmpurl)
                                                                } catch let error {
                                                                    UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: error.localizedDescription)

                                                                    return
                                                                }
                                                            }
                                                            service.upload(parentId: self.rootFileId, sessionId: sessionId, uploadname: newname, target: tmpurl) { id in
                                                                                                                                if id == nil {
                                                                    UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: "failed to upload")
                                                                }
                                                                else {
                                                                    UploadManeger.shared.UploadDone(identifier: sessionId)
                                                                }

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
        if urls.count > 1 {
            var passUrl: [URL] = []
            checkDupName(testNames: urls.map({ $0.lastPathComponent })) { pass in
                for (url, ok) in zip(urls, pass) {
                    if ok {
                        passUrl += [url]
                    }
                }

                for url in passUrl {
                    let newname = url.lastPathComponent
                    let sessionId = UUID().uuidString
                    let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                    UploadManeger.shared.UploadStart(identifier: sessionId, filename: newname)

                    DispatchQueue.global().async {
                        do {
                            guard CFURLStartAccessingSecurityScopedResource(url as CFURL) else {
                                UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: "CFURLStartAccessingSecurityScopedResource")
                                
                                return
                            }
                            defer {
                                CFURLStopAccessingSecurityScopedResource(url as CFURL)
                            }
                            do {
                                if FileManager.default.fileExists(atPath: tmpurl.path) {
                                    try FileManager.default.removeItem(at: tmpurl)
                                }
                                try FileManager.default.copyItem(at: url, to: tmpurl)
                            }
                            catch let error {
                                print(error)
                                UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: error.localizedDescription)
                                return
                            }
                        }
                        service.upload(parentId: self.rootFileId, sessionId: sessionId, uploadname: newname, target: tmpurl) { id in
                            if id == nil {
                                UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: "failed to upload")
                            }
                            else {
                                UploadManeger.shared.UploadDone(identifier: sessionId)
                            }
                            
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
        }
        else if let url = urls.first {
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
                                                    self.checkDupName(testNames: [newname]) { success in
                                                        guard success[0] else {
                                                            return
                                                        }
                                                        let sessionId = UUID().uuidString
                                                        let tmpurl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
                                                        UploadManeger.shared.UploadStart(identifier: sessionId, filename: newname)

                                                        DispatchQueue.global().async {
                                                            do {
                                                                guard CFURLStartAccessingSecurityScopedResource(url as CFURL) else {
                                                                    UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: "CFURLStartAccessingSecurityScopedResource")
                                                                    
                                                                    return
                                                                }
                                                                defer {
                                                                    CFURLStopAccessingSecurityScopedResource(url as CFURL)
                                                                }
                                                                do {
                                                                    if FileManager.default.fileExists(atPath: tmpurl.path) {
                                                                        try FileManager.default.removeItem(at: tmpurl)
                                                                    }
                                                                    try FileManager.default.copyItem(at: url, to: tmpurl)
                                                                }
                                                                catch let error {
                                                                    print(error)
                                                                    UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: error.localizedDescription)
                                                                    return
                                                                }
                                                            }
                                                            service.upload(parentId: self.rootFileId, sessionId: sessionId, uploadname: newname, target: tmpurl) { id in
                                                                if id == nil {
                                                                    UploadManeger.shared.UploadFailed(identifier: sessionId, errorStr: "failed to upload")
                                                                }
                                                                else {
                                                                    UploadManeger.shared.UploadDone(identifier: sessionId)
                                                                }
                                                                
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
                                                
                                                self.checkDupName(testNames: [newname]) { success in
                                                    guard success[0] else {
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
                                                self.checkDupName(testNames: [newname]) { success in
                                                    guard success[0] else {
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
        
        let contentVC = DatePickerPopupView()
        contentVC.modalPresentationStyle = .popover
        contentVC.preferredContentSize = CGSize(width: 350, height: 200)
        contentVC.popoverPresentationController?.sourceRect = sender.bounds
        contentVC.popoverPresentationController?.sourceView = sender
        contentVC.popoverPresentationController?.permittedArrowDirections = .any
        contentVC.popoverPresentationController?.delegate = self
        contentVC.targetDate = item.mDate ?? Date()
        contentVC.didFinish = { newDate in
            guard let newDate = newDate else {
                return
            }
            if newDate == item.mDate {
                return
            }
            DispatchQueue.main.async {
                self.activityIndicator.startAnimating()
            }
            item.changetime(newdate: newDate) { id in
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
        }
        present(contentVC, animated: true, completion: nil)
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
                                                    group.notify(queue: .main) {
                                                        self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                        self.result_base = self.result
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
                                            group.notify(queue: .main) {
                                                self.result = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                                                self.result_base = self.result
                                                self.activityIndicator.stopAnimating()
                                                self.tableView.reloadData()
                                                
                                                let alert2 = UIAlertController(title: "Result",
                                                                              message: "Delete \(scount)/\(items.count) items",
                                                    preferredStyle: .alert)
                                                let okAction = UIAlertAction(title: "OK", style: .default)
                                                alert2.addAction(okAction)

                                                self.present(alert2, animated: true, completion: nil)
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
            cell.backgroundColor = UIColor(named: "FolderColor")
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
            let formatter2 = ByteCountFormatter()
            formatter2.allowedUnits = [.useAll]
            formatter2.countStyle = .file
            let sStr2 = formatter2.string(fromByteCount: Int64(result[indexPath.row].size))
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.lineBreakMode = .byWordWrapping
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr2) (\(sStr) bytes)"
            if let storage = result[indexPath.row].storage, let id = result[indexPath.row].id {
                let localpos = CloudFactory.shared.data.getMark(storage: storage, targetID: id)
                if localpos != nil {
                    cell.backgroundColor = UIColor(named: "DidPlayColor")
                }
                else {
                    cell.backgroundColor = nil
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
        if #available(iOS 13.0, *) {
            activityIndicator.style = .large
        } else {
            activityIndicator.style = .whiteLarge
        }
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
        
        cell.detailTextLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        guard let formatString = DateFormatter.dateFormat(fromTemplate: "yyyyMMdd", options: 0, locale: Locale.current) else { fatalError() }

        if result[indexPath.row].folder {
            cell.accessoryType = .disclosureIndicator
            var tStr = ""
            if result[indexPath.row].mdate != nil {
                let f = DateFormatter()
                f.dateFormat = formatString + " HH:mm:ss"
                tStr = f.string(from: result[indexPath.row].mdate!)
            }
            cell.detailTextLabel?.text = "\(tStr)\tfolder"
            cell.backgroundColor = UIColor(named: "FolderColor")
        }
        else {
            cell.accessoryType = .none
            var tStr = ""
            if result[indexPath.row].mdate != nil {
                let f = DateFormatter()
                f.dateFormat = formatString + " HH:mm:ss"
                tStr = f.string(from: result[indexPath.row].mdate!)
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            let sStr = formatter.string(from: result[indexPath.row].size as NSNumber) ?? "0"
            let formatter2 = ByteCountFormatter()
            formatter2.allowedUnits = [.useAll]
            formatter2.countStyle = .file
            let sStr2 = formatter2.string(fromByteCount: Int64(result[indexPath.row].size))
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.lineBreakMode = .byWordWrapping
            cell.detailTextLabel?.text = "\(tStr)\t\(sStr2) (\(sStr) bytes)"
            if #available(iOS 13.0, *) {
                cell.backgroundColor = UIColor.systemBackground
            } else {
                cell.backgroundColor = UIColor.white
            }
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

class DatePickerPopupView: UIViewController {
    var targetDate = Date()
    var didFinish: ((Date?)->Void)?
    
    var datePicker: UIDatePicker!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        datePicker = UIDatePicker()
        datePicker.datePickerMode = .dateAndTime
        datePicker.setDate(targetDate, animated: false)
        view.addSubview(datePicker)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        didFinish?(datePicker.date)
    }
}
