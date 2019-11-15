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
import ffconverter

#if !targetEnvironment(macCatalyst)
import GoogleCast
#endif

let kCastControlBarsAnimationDuration: TimeInterval = 0.20

public protocol SortItemsDelegate: NSObjectProtocol {
    func DoSort()
}

extension TableViewControllerItems: SortItemsDelegate {
    func DoSort() {
        let order = UserDefaults.standard.integer(forKey: "ItemSortOrder")
        switch order {
        case 0:
            result_base = result_base.sorted(by: { in1, in2 in (in1.name ?? "").lowercased() < (in2.name  ?? "").lowercased() } )
        case 1:
            result_base = result_base.sorted(by: { in1, in2 in (in1.name ?? "").lowercased() > (in2.name  ?? "").lowercased() } )
        case 2:
            result_base = result_base.sorted(by: { in1, in2 in in1.size < in2.size } )
        case 3:
            result_base = result_base.sorted(by: { in1, in2 in in1.size > in2.size } )
        case 4:
            result_base = result_base.sorted(by: { in1, in2 in (in1.mdate ?? Date(timeIntervalSince1970: 0)) < (in2.mdate ?? Date(timeIntervalSince1970: 0)) } )
        case 5:
            result_base = result_base.sorted(by: { in1, in2 in (in1.mdate ?? Date(timeIntervalSince1970: 0)) > (in2.mdate ?? Date(timeIntervalSince1970: 0)) } )
        case 6:
            result_base = result_base.sorted(by: { in1, in2 in (in1.ext ?? "") < (in2.ext ?? "") } )
        case 7:
            result_base = result_base.sorted(by: { in1, in2 in (in1.ext ?? "") > (in2.ext ?? "") } )
        default:
            result_base = result_base.sorted(by: { in1, in2 in (in1.name ?? "").lowercased() < (in2.name  ?? "").lowercased() } )
        }
        let folders = result_base.filter({ $0.folder })
        let files = result_base.filter({ !$0.folder })
        result_base = folders
        result_base += files

        // filter
        let text = navigationItem.searchController?.searchBar.text ?? ""
        if text.isEmpty {
            result = result_base
        } else {
            result = result_base.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
        }
        
        tableView.reloadData()
    }
}

extension TableViewControllerItems: UploadManagerDelegate {
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
    var playCastItem: UIBarButtonItem!
    var castButton: UIBarButtonItem?
    
    var player: CustomPlayerView?
    var convertPlayer: ConvertPlayerView?

    lazy var downloadProgress: DownloadProgressViewController = {
        let d = DownloadProgressViewController()
        d.modalPresentationStyle = .custom
        d.transitioningDelegate = self
        return d
    }()
    
    var editting = false
        
    let media_exts = [
        "mov",
        "mp4",
        "mp3",
        "wav",
        "aac",
    ]
    
    let pict_exts = [
        "tif","tiff",
        "heic",
        "jpg","jpeg",
        "gif",
        "png",
        "bmp",
        "ico",
        "cur",
        "xbm",
        "3fr", // (Hasselblad)
        "ari", // (Arri_Alexa)
        "arw","srf","sr2", // (Sony)
        "bay", // (Casio)
        "braw", // (Blackmagic Design)
        "cri", // (Cintel)
        "crw","cr2","cr3", // (Canon)
        "cap","iiq","eip", // (Phase_One)
        "dcs","dcr","drf","k25","kdc", // (Kodak)
        "dng", // (Adobe)
        "erf", // (Epson)
        "fff", // (Imacon/Hasselblad raw)
        "gpr", // (GoPro)
        "mef", // (Mamiya)
        "mdc", // (Minolta, Agfa)
        "mos", // (Leaf)
        "mrw", // (Minolta, Konica Minolta)
        "mos", // (Leaf)
        "mrw", // (Minolta, Konica Minolta)
        "nef","nrw", // (Nikon)
        "orf", // (Olympus)
        "pef","ptx", // (Pentax)
        "pxn", // (Logitech)
        "r3d", // (RED Digital Cinema)
        "raf", // (Fuji)
        "raw","rw2", // (Panasonic)
        "raw","rwl","dng", // (Leica)
        "rwz", // (Rawzor)
        "srw", // (Samsung)
        "x3f", // (Sigma)
    ]
        
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        self.title = rootPath
        
        let settingButton = UIBarButtonItem(image: UIImage(named: "gear"), style: .plain, target: self, action: #selector(settingButtonDidTap))
        let editButton = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(editButtonDidTap))
            
        navigationItem.rightBarButtonItems = [settingButton, editButton]
        
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

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        
        playlistItem = UIBarButtonItem(image: UIImage(named: "playlist"), style: .plain, target: self, action: #selector(barButtonPlayListTapped))
        playallItem = UIBarButtonItem(image: UIImage(named: "playall"), style: .plain, target: self, action: #selector(barButtonPlayAllTapped))
        editlistItem = UIBarButtonItem(image: UIImage(named: "addplay"), style: .plain, target: self, action: #selector(barButtonEditListTapped))
        playloopItem = UIBarButtonItem(image: UIImage(named: "loop"), style: .plain, target: self, action: #selector(barButtonPlayLoopTapped))
        playshuffleItem = UIBarButtonItem(image: UIImage(named: "shuffle"), style: .plain, target: self, action: #selector(barButtonPlayShuffleTapped))
        playCastItem = UIBarButtonItem(image: UIImage(named: "cast"), style: .plain, target: self, action: #selector(barButtonPlayCastTapped))
        flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        #if !targetEnvironment(macCatalyst)
        castButton = UIBarButtonItem(customView: GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24)))
        #endif
        
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

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    func restoreToolbarButton() {
        #if !targetEnvironment(macCatalyst)
        let castContext = GCKCastContext.sharedInstance()
        if Converter.IsCasting() && (castContext.castState == .connected || castContext.castState == .connecting) {
            if let castButton = castButton {
                toolbarItems = [playlistItem, flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem, flexible, playCastItem, flexible, castButton]
            }
            else {
                toolbarItems = [playlistItem, flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem, flexible, playCastItem]
            }
        }
        else {
            toolbarItems = [playlistItem, flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem, flexible, playCastItem]
        }
        #else
        toolbarItems = [playlistItem, flexible, playloopItem, flexible, playallItem, flexible, playshuffleItem, flexible, editlistItem, flexible, playCastItem]
        #endif
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UploadManeger.shared.delegate = self
        didRefreshItems()
        
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
        if Converter.IsCasting() {
            playCastItem.image = UIImage(named: "cast_on")
        }
        else {
            playCastItem.image = UIImage(named: "cast")
        }

        restoreToolbarButton()
        
        navigationController?.navigationBar.barTintColor = nil
        navigationController?.isToolbarHidden = false

        self.result_base = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
        self.DoSort()
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
    
    @objc func barButtonPlayCastTapped(_ sender: UIBarButtonItem) {
        if Converter.IsCasting() {
            Converter.Stop()
            activityIndicator.stopAnimating()
            
            restoreToolbarButton()
        }
        else {
            let alert = UIAlertController(title: "Cast for", message: "select device to cast", preferredStyle: .alert)
            let default1 = UIAlertAction(title: "Local device", style: .default) { action in
                Converter.Start()

                if Converter.IsCasting() {
                    self.playCastItem.image = UIImage(named: "cast_on")
                }
                else {
                    self.playCastItem.image = UIImage(named: "cast")
                }
            }
            alert.addAction(default1)
            #if !targetEnvironment(macCatalyst)
            let default2 = UIAlertAction(title: "Chromecast", style: .default) { action in
                Converter.Start()

                if let castButton = self.castButton {
                    if !(self.toolbarItems?.contains(castButton) ?? false) {
                        self.toolbarItems = self.toolbarItems! + [self.flexible, castButton]
                    }
                }
                if Converter.IsCasting() {
                    self.playCastItem.image = UIImage(named: "cast_on")
                }
                else {
                    self.playCastItem.image = UIImage(named: "cast")
                }
            }
            alert.addAction(default2)
            #endif
            let cancel = UIAlertAction(title: "cancel", style: .cancel, handler: nil)

            alert.addAction(cancel)

            present(alert, animated: true, completion: nil)
        }
        if Converter.IsCasting() {
            playCastItem.image = UIImage(named: "cast_on")
        }
        else {
            playCastItem.image = UIImage(named: "cast")
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
            restoreToolbarButton()
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
            self.restoreToolbarButton()
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
        if UserDefaults.standard.bool(forKey: "FFplayer") && UserDefaults.standard.bool(forKey: "firstFFplayer") {
            media = false
        }
        
        if media {
            player = CustomPlayerView()
            let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
            let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
            player?.playItems = result.filter({ !$0.folder }).map({ item in
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
            for aitem in result.filter({ !$0.folder }) {
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
    
    @objc func refresh() {
        self.result = []
        self.tableView.reloadData()
        if subItem {
            (CloudFactory.shared[storageName] as? RemoteSubItem)?.listsubitem(fileId: self.rootFileId) {
                DispatchQueue.main.async {
                    self.result_base = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                    self.DoSort()
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
                    self.result_base = CloudFactory.shared.data.listData(storage: self.storageName, parentID: self.rootFileId)
                    self.DoSort()
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
        let contentVC = PopupEditContentViewController()
        contentVC.modalPresentationStyle = .popover
        contentVC.preferredContentSize = CGSize(width: 200, height: 400)
        contentVC.popoverPresentationController?.barButtonItem = sender
        contentVC.popoverPresentationController?.permittedArrowDirections = .any
        contentVC.popoverPresentationController?.delegate = self
        contentVC.dataparent = self
        contentVC.isShowEdit = !subItem
        
        present(contentVC, animated: true, completion: nil)
    }

    func editStartFunc() {
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
            result = result_base.compactMap { ($0.name?.lowercased().contains(text.lowercased()) ?? false) ? $0 : nil }
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
                                                                                        self.displayImageViewer(item: item)
                                                                                    })
                                                let defaultAction62 = UIAlertAction(title: NSLocalizedString("as PDF", comment: ""),
                                                                                    style: .default,
                                                                                    handler:{ action in
                                                                                        self.displayPDFViewer(item: item)
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
        DispatchQueue.main.async {
            self.downloadProgress.filepos = Int(pos)
        }
        var len = 2*1024*1024
        guard gone, downloadProgress.isLive else {
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
        
        downloadProgress.filepos = 0
        downloadProgress.filesize = Int(item.size)
        downloadProgress.isLive = true
        present(downloadProgress, animated: true, completion: nil)

        let stream = item.open()
        writeTempfile(file: url, stream: stream, pos: 0, size: item.size) {
            guard self.gone, self.downloadProgress.isLive else {
                return
            }
            DispatchQueue.main.async {
                self.downloadProgress.dismiss(animated: true, completion: nil)

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
            cell.detailTextLabel?.text = "\(tStr) \tfolder"
            cell.backgroundColor = UIColor(named: "FolderColor")
        }
        else if hasSubItem(name: result[indexPath.row].name) {
            cell.accessoryType = .disclosureIndicator
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
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr2) (\(sStr) bytes) \t\(result[indexPath.row].subinfo ?? "")"
            cell.backgroundColor = UIColor(named: "CueColor")
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
            cell.detailTextLabel?.text = "\(tStr) \t\(sStr2) (\(sStr) bytes) \t\(result[indexPath.row].subinfo ?? "")"
            if let storage = result[indexPath.row].storage, let id = result[indexPath.row].id {
                let localpos = CloudFactory.shared.data.getMark(storage: storage, targetID: id)
                if localpos != nil {
                    cell.backgroundColor = UIColor(named: "DidPlayColor")
                }
                else {
                    if #available(iOS 13.0, *) {
                        cell.backgroundColor = UIColor.systemBackground
                    } else {
                        cell.backgroundColor = UIColor.white
                    }
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
                else if UserDefaults.standard.bool(forKey: "FFplayer") && UserDefaults.standard.bool(forKey: "firstFFplayer") &&
                    !Converter.IsCasting() {
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
        if UserDefaults.standard.bool(forKey: "ImageViewer") && pict_exts.contains(item.ext) {
            
            displayImageViewer(item: item)
        }
        else if UserDefaults.standard.bool(forKey: "PDFViewer") && (item.ext == "pdf") {
            displayPDFViewer(item: item)
        }
        else if Converter.IsCasting() {
            semaphore.signal()
            playConverter(item: item) { fin in
            }
        }
        else if UserDefaults.standard.bool(forKey: "MediaViewer") && media_exts.contains(item.ext)  {
            
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

    func waitToPlay(target: URL, onFind: @escaping ()->Void) {
        let task = URLSession.shared.dataTask(with: target) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                        onFind()
                    }
                    return
                }
            }
            if Converter.IsCasting() {
                DispatchQueue.global().asyncAfter(deadline: .now()+1) {
                    self.waitToPlay(target: target, onFind: onFind)
                }
            }
            return
        }
        
        task.resume()
    }

    func playConverter(item: RemoteItem, onFinish: @escaping (Bool)->Void) {
        self.activityIndicator.startAnimating()
        #if !targetEnvironment(macCatalyst)
        let castContext = GCKCastContext.sharedInstance()
        if castContext.castState == .connected || castContext.castState == .connecting {
            var url: URL? = nil
            DispatchQueue.global().async {
                let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
                let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
                let info = ConvertIteminfo(item: item)
                if skip > 0 {
                    info.startpos = Double(skip)
                }
                if stop > 0 {
                    info.playduration = Double(stop)
                }
                url = Converter.Play(item: info, local: false, onSelect: {
                    info in
                    let group = DispatchGroup()
                    var video = info.mainVideo
                    var subtitle = info.mainSubtitle
                    group.enter()
                    DispatchQueue.main.async {
                        let dialog = SelectStreamViewController()
                        dialog.info = info
                        dialog.onDone = { v, s in
                            video = v
                            subtitle = s
                            group.leave()
                        }
                        self.present(dialog, animated: true, completion: nil)
                    }
                    group.wait()
                    return (video, subtitle)
                }) { ready in
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                        guard ready else {
                            return
                        }
                        let group = DispatchGroup()
                        if UserDefaults.standard.bool(forKey: "savePlaypos") {
                            if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                                CloudFactory.shared.data.setCloudMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: 0, group: group)
                            }
                            group.notify(queue: .main) {
                                CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: 0)
                                self.tableView.reloadData()
                            }
                        }
                        guard let target = url else {
                            return
                        }
                        print(target)
                        
                        let metadata = GCKMediaMetadata()
                        metadata.setString(item.name, forKey: kGCKMetadataKeyTitle)
                        let mediaInfoBuilder = GCKMediaInformationBuilder.init(contentURL: target)
                        mediaInfoBuilder.streamType = GCKMediaStreamType.none
                        mediaInfoBuilder.contentType = "application/vnd.apple.mpegurl"
                        mediaInfoBuilder.metadata = metadata
                        
                                            
                        let mediaInfo = mediaInfoBuilder.build()
                        let instance = GCKCastContext.sharedInstance()
                        instance.presentDefaultExpandedMediaControls()
                        instance.sessionManager.currentSession?.remoteMediaClient?.loadMedia(mediaInfo)

                    }
                }
                if(url == nil) {
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                    }
                }
                onFinish(url != nil)
            }
            return
        }
        #endif
        convertPlayer = ConvertPlayerView()
        var url: URL? = nil
        DispatchQueue.global().async {
            let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
            let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
            let info = ConvertIteminfo(item: item)
            if skip > 0 {
                info.startpos = Double(skip)
            }
            if stop > 0 {
                info.playduration = Double(stop)
            }
            url = Converter.Play(item: info, local: true, onSelect: {
                info in
                let group = DispatchGroup()
                var video = info.mainVideo
                var subtitle = info.mainSubtitle
                group.enter()
                DispatchQueue.main.async {
                    let dialog = SelectStreamViewController()
                    dialog.info = info
                    dialog.onDone = { v, s in
                        video = v
                        subtitle = s
                        group.leave()
                    }
                    self.present(dialog, animated: true, completion: nil)
                }
                group.wait()
                return (video, subtitle)
            }) { ready in
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    guard ready else {
                        return
                    }
                    let group = DispatchGroup()
                    if UserDefaults.standard.bool(forKey: "savePlaypos") {
                        if UserDefaults.standard.bool(forKey: "cloudPlaypos") {
                            CloudFactory.shared.data.setCloudMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: 0, group: group)
                        }
                        group.notify(queue: .main) {
                            CloudFactory.shared.data.setMark(storage: item.storage, targetID: item.id, parentID: self.rootFileId, position: 0)
                            self.tableView.reloadData()
                        }
                    }
                    guard let target = url else {
                        return
                    }
                    self.convertPlayer?.target = target
                    self.convertPlayer?.item = item
                    self.convertPlayer?.play(parent: self)
                }
            }
            if(url == nil) {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                }
            }
            onFinish(url != nil)
        }
    }
    
    func playFFmpeg(item: RemoteItem, onFinish: @escaping (Bool)->Void) {
        let localpos = UserDefaults.standard.bool(forKey: "resumePlaypos") ? CloudFactory.shared.data.getMark(storage: item.storage, targetID: item.id) : nil
        Player.play(parent: self, item: item, start: localpos) { position in
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
            if position == nil {
                DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                    onFinish(position != nil)
                }
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
    
    func displayImageViewer(item: RemoteItem) {
        downloadProgress.filepos = 0
        downloadProgress.filesize = Int(item.size)
        downloadProgress.isLive = true
        present(downloadProgress, animated: false, completion: nil)

        let next = self.storyboard!.instantiateViewController(withIdentifier: "ImageView") as? ViewControllerImage

        let image_ids = result.filter({ !$0.folder && pict_exts.contains($0.ext?.lowercased() ?? "") }).compactMap({ $0.id })
        let image_items = image_ids.compactMap({ CloudFactory.shared[storageName]?.get(fileId: $0) })
        
        guard image_items.count > 0 else {
            self.semaphore.signal()
            return
        }
        
        next?.items = image_items
        next?.itemIdx = image_items.firstIndex(where: { $0.id == item.id }) ?? 0
        next?.data = [Data?](repeating: nil, count: image_items.count)
        next?.images = [UIImage?](repeating: nil, count: image_items.count)
        
        let stream = item.open()
        stream.read(position: 0, length: Int(item.size), onProgress: { pos in
            DispatchQueue.main.async {
                self.downloadProgress.filepos = pos
            }
            return self.downloadProgress.isLive
        }) { data in
            guard self.downloadProgress.isLive else {
                self.semaphore.signal()
                stream.isLive = false
                return
            }
            DispatchQueue.main.async {
                self.downloadProgress.filepos = Int(item.size)
            }
            if let data = data, let image = UIImage(data: data), let fixedImage = image.fixedOrientation() {
                next?.data[next?.itemIdx ?? 0] = data
                next?.images[next?.itemIdx ?? 0] = fixedImage
                DispatchQueue.main.async {
                    next?.imagedata = fixedImage
                    next?.modalPresentationStyle = .fullScreen
                    self.downloadProgress.dismiss(animated: false, completion: nil)
                    self.activityIndicator.startAnimating()
                    self.semaphore.signal()
                    self.present(next!, animated: true) {
                        self.activityIndicator.stopAnimating()
                    }
                }
            }
            else {
                DispatchQueue.main.async {
                    self.downloadProgress.dismiss(animated: true, completion: nil)
                    self.semaphore.signal()
                }
            }
        }
    }
    
    func displayPDFViewer(item: RemoteItem) {
        downloadProgress.filepos = 0
        downloadProgress.filesize = Int(item.size)
        downloadProgress.isLive = true
        present(downloadProgress, animated: false, completion: nil)

        let stream = item.open()
        stream.read(position: 0, length: Int(item.size), onProgress: { pos in
            DispatchQueue.main.async {
                self.downloadProgress.filepos = pos
            }
            return self.downloadProgress.isLive
        }) { data in
            guard self.downloadProgress.isLive else {
                self.semaphore.signal()
                stream.isLive = false
                return
            }
            DispatchQueue.main.async {
                self.downloadProgress.filepos = Int(item.size)
            }
            if let data = data, let document = PDFDocument(data: data) {
                DispatchQueue.main.async {
                    let next = self.storyboard!.instantiateViewController(withIdentifier: "PDFView") as? ViewControllerPDF
                    next?.document = document
                    next?.modalPresentationStyle = .fullScreen
                    self.downloadProgress.dismiss(animated: false, completion: nil)
                    self.semaphore.signal()
                    self.present(next!, animated: true, completion: nil)
                }
            }
            else {
                DispatchQueue.main.async {
                    self.downloadProgress.dismiss(animated: true, completion: nil)
                    self.semaphore.signal()
                }
            }
        }
    }
    
    func displayMediaViewer(item: RemoteItem, fallback: Bool) {
        player = CustomPlayerView()
        
        let localpos = UserDefaults.standard.bool(forKey: "resumePlaypos") ? CloudFactory.shared.data.getMark(storage: item.storage, targetID: item.id) : nil
        var playitem: [String: Any] = ["storage": storageName, "id": item.id]
        if let start = localpos {
            playitem["start"] = start
        }
        let skip = UserDefaults.standard.integer(forKey: "playStartSkipSec")
        let stop = UserDefaults.standard.integer(forKey: "playStopAfterSec")
        if skip > 0 {
            if let start = localpos, start > Double(skip) {
            }
            else {
                playitem["start"] = Double(skip)
            }
        }
        if stop > 0 {
            let stoppos = Double(skip + stop)
            if let start = localpos, start > stoppos {
                if skip > 0 {
                    playitem["start"] = Double(skip)
                }
                else {
                    playitem["start"] = nil
                }
                playitem["stop"] = stoppos
            }
            else {
                playitem["stop"] = stoppos
            }
        }
        player?.playItems = [playitem]
        player?.onFinish = { position in
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

class PopupEditContentViewController: UIViewController {
    
    var stackView: UIStackView!
    var dataparent: TableViewControllerItems!
    var isShowEdit: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor).isActive = true

        if isShowEdit {
            let button1 = UIButton()
            button1.setTitle("Edit items", for: .normal)
            button1.setTitleColor(.systemRed, for: .normal)
            button1.addTarget(self, action: #selector(buttonEvent1), for: .touchUpInside)
            stackView.addArrangedSubview(button1)
        }
        
        let button2 = UIButton()
        button2.setTitle("Name A → Z", for: .normal)
        if #available(iOS 13.0, *) {
            button2.setTitleColor(.label, for: .normal)
        } else {
            button2.setTitleColor(.black, for: .normal)
        }
        button2.addTarget(self, action: #selector(buttonEvent2), for: .touchUpInside)
        stackView.addArrangedSubview(button2)

        let button3 = UIButton()
        button3.setTitle("Name Z → A", for: .normal)
        if #available(iOS 13.0, *) {
            button3.setTitleColor(.label, for: .normal)
        } else {
            button3.setTitleColor(.black, for: .normal)
        }
        button3.addTarget(self, action: #selector(buttonEvent3), for: .touchUpInside)
        stackView.addArrangedSubview(button3)

        let button4 = UIButton()
        button4.setTitle("Size 0 → 9", for: .normal)
        if #available(iOS 13.0, *) {
            button4.setTitleColor(.label, for: .normal)
        } else {
            button4.setTitleColor(.black, for: .normal)
        }
        button4.addTarget(self, action: #selector(buttonEvent4), for: .touchUpInside)
        stackView.addArrangedSubview(button4)

        let button5 = UIButton()
        button5.setTitle("Size 9 → 0", for: .normal)
        if #available(iOS 13.0, *) {
            button5.setTitleColor(.label, for: .normal)
        } else {
            button5.setTitleColor(.black, for: .normal)
        }
        button5.addTarget(self, action: #selector(buttonEvent5), for: .touchUpInside)
        stackView.addArrangedSubview(button5)

        let button6 = UIButton()
        button6.setTitle("Time old → new", for: .normal)
        if #available(iOS 13.0, *) {
            button6.setTitleColor(.label, for: .normal)
        } else {
            button6.setTitleColor(.black, for: .normal)
        }
        button6.addTarget(self, action: #selector(buttonEvent6), for: .touchUpInside)
        stackView.addArrangedSubview(button6)

        let button7 = UIButton()
        button7.setTitle("Time new → old", for: .normal)
        if #available(iOS 13.0, *) {
            button7.setTitleColor(.label, for: .normal)
        } else {
            button7.setTitleColor(.black, for: .normal)
        }
        button7.addTarget(self, action: #selector(buttonEvent7), for: .touchUpInside)
        stackView.addArrangedSubview(button7)

        let button8 = UIButton()
        button8.setTitle("Extension A → Z", for: .normal)
        if #available(iOS 13.0, *) {
            button8.setTitleColor(.label, for: .normal)
        } else {
            button8.setTitleColor(.black, for: .normal)
        }
        button8.addTarget(self, action: #selector(buttonEvent8), for: .touchUpInside)
        stackView.addArrangedSubview(button8)

        let button9 = UIButton()
        button9.setTitle("Extension Z → A", for: .normal)
        if #available(iOS 13.0, *) {
            button9.setTitleColor(.label, for: .normal)
        } else {
            button9.setTitleColor(.black, for: .normal)
        }
        button9.addTarget(self, action: #selector(buttonEvent9), for: .touchUpInside)
        stackView.addArrangedSubview(button9)
    }
    
    @objc func buttonEvent1(_ sender: UIButton) {
        dismiss(animated: true) {
            self.dataparent.editStartFunc()
        }
    }

    @objc func buttonEvent2(_ sender: UIButton) {
        UserDefaults.standard.set(0, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }

    @objc func buttonEvent3(_ sender: UIButton) {
        UserDefaults.standard.set(1, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }
    
    @objc func buttonEvent4(_ sender: UIButton) {
        UserDefaults.standard.set(2, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }

    @objc func buttonEvent5(_ sender: UIButton) {
        UserDefaults.standard.set(3, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }

    @objc func buttonEvent6(_ sender: UIButton) {
        UserDefaults.standard.set(4, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }

    @objc func buttonEvent7(_ sender: UIButton) {
        UserDefaults.standard.set(5, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }

    @objc func buttonEvent8(_ sender: UIButton) {
        UserDefaults.standard.set(6, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }

    @objc func buttonEvent9(_ sender: UIButton) {
        UserDefaults.standard.set(7, forKey: "ItemSortOrder")
        dismiss(animated: true) {
            self.dataparent.DoSort()
        }
    }
}

extension TableViewControllerItems: UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return CustomPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

class CustomPresentationController: UIPresentationController {
    // 呼び出し元のView Controller の上に重ねるオーバレイView
    var overlayView = UIView()

    // 表示トランジション開始前に呼ばれる
    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else {
            return
        }

        overlayView.frame = containerView.bounds
        //overlayView.gestureRecognizers = [UITapGestureRecognizer(target: self, action: #selector(CustomPresentationController.overlayViewDidTouch(_:)))]
        overlayView.backgroundColor = .black
        overlayView.alpha = 0.0
        containerView.insertSubview(overlayView, at: 0)

        // トランジションを実行
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: {[weak self] context in
            self?.overlayView.alpha = 0.7
            }, completion:nil)
    }

    // 非表示トランジション開始前に呼ばれる
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: {[weak self] context in
            self?.overlayView.alpha = 0.0
            }, completion:nil)
    }

    // 非表示トランジション開始後に呼ばれる
    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            overlayView.removeFromSuperview()
        }
    }

    // 子のコンテナサイズを返す
    override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
        return CGSize(width: 250, height: 250)
    }

    // 呼び出し先のView Controllerのframeを返す
    override var frameOfPresentedViewInContainerView: CGRect {
        var presentedViewFrame = CGRect()
        let containerBounds = containerView!.bounds
        let childContentSize = size(forChildContentContainer: presentedViewController, withParentContainerSize: containerBounds.size)

        presentedViewFrame.size = childContentSize
        presentedViewFrame.origin.x = (containerBounds.size.width - childContentSize.width) / 2.0
        presentedViewFrame.origin.y = (containerBounds.size.height - childContentSize.height) / 2.0

        return presentedViewFrame
    }

    // レイアウト開始前に呼ばれる
    override func containerViewWillLayoutSubviews() {
        overlayView.frame = containerView!.bounds
        presentedView?.frame = frameOfPresentedViewInContainerView
        presentedView?.layer.cornerRadius = 10
        presentedView?.clipsToBounds = true
    }


    // レイアウト開始後に呼ばれる
    override func containerViewDidLayoutSubviews() {
    }

    // overlayViewをタップした時に呼ばれる
    @objc func overlayViewDidTouch(_ sender: UITapGestureRecognizer) {
        presentedViewController.dismiss(animated: true, completion: nil)
    }
}

class DownloadProgressViewController: UIViewController, DownloadManagerDelegate {
    
    lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView()
        if #available(iOS 13.0, *) {
            activityIndicator.style = .large
        } else {
            activityIndicator.style = .whiteLarge
        }
        activityIndicator.color = UIColor(named: "IndicatorColor")
        return activityIndicator
    }()
    
    lazy var labelProgress: UILabel = {
        let label = UILabel()
        label.text = "0 / 0"
        return label
    }()
    
    lazy var progressView: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .default)
        return p
    }()
    
    func progress() {
        let formatter2 = ByteCountFormatter()
        formatter2.allowedUnits = [.useAll]
        formatter2.countStyle = .file
        let s2 = formatter2.string(fromByteCount: Int64(filesize))
        let p2 = formatter2.string(fromByteCount: Int64(filepos))
        labelProgress.text = "\(p2) / \(s2)"
        if filesize > 0 {
            progressView.setProgress(Float(filepos) / Float(filesize), animated: true)
        }
        else {
            progressView.setProgress(0.0, animated: true)
        }
    }
    
    var filesize: Int = 0 {
        didSet {
            progress()
        }
    }

    var filepos: Int = 0 {
        didSet {
            progress()
        }
    }
    
    var isLive = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        stackView.addArrangedSubview(activityIndicator)
        activityIndicator.heightAnchor.constraint(equalToConstant: 100).isActive = true
        activityIndicator.widthAnchor.constraint(equalToConstant: 100).isActive = true
        activityIndicator.startAnimating()

        stackView.addArrangedSubview(labelProgress)
        stackView.addArrangedSubview(progressView)
        progressView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        let buttonCancel = UIButton(type: .roundedRect)
        buttonCancel.setTitle("Cancel", for: .normal)
        buttonCancel.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView.addArrangedSubview(buttonCancel)
    }
    
    @objc func buttonEvent(_ sender: UIButton) {
        isLive = false
        dismiss(animated: true, completion: nil)
    }
}


class SelectStreamViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    var onDone: ((Int, Int)->Void)?
    var info: PlayItemInfo?
    
    var picker1: UIPickerView!
    var picker2: UIPickerView!
    
    var videoIdx: Int = -1
    var subtitleIdx: Int = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        
        videoIdx = info?.mainVideo ?? -1
        subtitleIdx = info?.mainSubtitle ?? -1
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        let stackView1 = UIStackView()
        stackView1.axis = .horizontal
        stackView1.spacing = 10
        stackView.addArrangedSubview(stackView1)
        
        let label1 = UILabel()
        label1.text = NSLocalizedString("Video", comment: "")
        stackView1.addArrangedSubview(label1)
        
        picker1 = UIPickerView()
        picker1.dataSource = self
        picker1.delegate = self
        stackView1.addArrangedSubview(picker1)
        
        let stackView2 = UIStackView()
        stackView2.axis = .horizontal
        stackView2.spacing = 10
        stackView.addArrangedSubview(stackView2)
        
        let label2 = UILabel()
        label2.text = NSLocalizedString("Subtitle", comment: "")
        stackView2.addArrangedSubview(label2)

        picker2 = UIPickerView()
        picker2.dataSource = self
        picker2.delegate = self
        stackView2.addArrangedSubview(picker2)

        let buttonOK = UIButton(type: .roundedRect)
        buttonOK.setTitle("OK", for: .normal)
        buttonOK.addTarget(self, action: #selector(buttonEvent), for: .touchUpInside)
        stackView.addArrangedSubview(buttonOK)
        
        if let key = info?.videos.keys.sorted(), let ind = key.firstIndex(of: videoIdx) {
            picker1.selectRow(ind, inComponent: 0, animated: false)
        }
        if let key = info?.subtitle.keys.sorted(), let ind = key.firstIndex(of: subtitleIdx) {
            picker2.selectRow(ind, inComponent: 0, animated: false)
        }
    }
        
    @objc func buttonEvent(_ sender: UIButton) {
        dismiss(animated: true) {
            self.onDone?(self.videoIdx, self.subtitleIdx)
        }
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView == picker1 {
            return info?.videos.count ?? 0
        }
        else if pickerView == picker2 {
            return info?.subtitle.count ?? 0
        }
        return 0
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView == picker1, let key = info?.videos.keys.sorted() {
            return "\(key[row]) : \(info?.videos[key[row]] ?? "")"
        }
        if pickerView == picker2, let key = info?.subtitle.keys.sorted() {
            return "\(key[row]) : \(info?.subtitle[key[row]] ?? "")"
        }
        return nil
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView == picker1, let key = info?.videos.keys.sorted() {
            videoIdx = key[row]
        }
        if pickerView == picker2, let key = info?.subtitle.keys.sorted() {
            subtitleIdx = key[row]
        }
    }
}
