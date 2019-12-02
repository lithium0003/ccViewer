//
//  UploadManager.swift
//  RemoteCloud
//
//  Created by rei8 on 2019/09/29.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation

public protocol DownloadManagerDelegate {
    var filesize: Int { get set }
    var filepos: Int { get set }
    var isLive: Bool { get set }
}

public protocol UploadManagerDelegate: UIViewController, UIPopoverPresentationControllerDelegate {
    func didRefreshItems()
}

public class UploadManeger {
    private static let _shared = UploadManeger()
    public static var shared: UploadManeger { return _shared }
    
    let arg_queue = DispatchQueue(label: "UploadArgs")
    public weak var delegate: UploadManagerDelegate?
    
    class UploadItemInfo {
        var filename = ""
        var size = 0
        var position = 0
        var errorStr: String? = nil
        var finishDate: Date? = nil
    }
    var uploadSessions: [String: UploadItemInfo] = [:]
    var finishedSessions: [String: UploadItemInfo] = [:]
    var uploadIdentifers: [String] = []
    
    public var uploadCount: Int {
        return uploadIdentifers.count + finishedSessions.count
    }
    
    public var targetButton: UIBarButtonItem?
    
    public lazy var UploadCountButton: UIBarButtonItem = {
        let button = UIBarButtonItem(title: "0↑", style: .plain, target: self, action: #selector(openUploadList))
        return button
    }()
    
    lazy var UploadList: UploadManagerList = {
        let vc = UploadManagerList()
        vc.modalPresentationStyle = .popover
        vc.preferredContentSize = CGSize(width: 300, height: 400)
        vc.popoverPresentationController?.permittedArrowDirections = .any
        return vc
    }()
    
    @objc func openUploadList() {
        UploadList.popoverPresentationController?.delegate = delegate
        UploadList.popoverPresentationController?.barButtonItem = UploadCountButton
        UploadList.onClose = {
            self.delegate?.didRefreshItems()
        }
        delegate?.present(UploadList, animated: true, completion: nil)
    }
    
    public func UploadStart(identifier: String, filename: String) {
        let newItem = UploadItemInfo()
        newItem.filename = filename
        arg_queue.async {
            self.uploadSessions[identifier] = newItem
            self.uploadIdentifers += [identifier]
            DispatchQueue.main.async {
                self.UploadCountButton.title = "\(self.uploadIdentifers.count)↑"
                self.UploadList.tableView.reloadData()
                self.delegate?.didRefreshItems()
            }
        }
    }
    
    public func UploadFixSize(identifier: String, size: Int) {
        arg_queue.async {
            self.uploadSessions[identifier]?.size = size
            DispatchQueue.main.async {
                self.UploadList.tableView.reloadData()
                self.delegate?.didRefreshItems()
            }
        }
    }
    
    public func UploadProgress(identifier: String, possition: Int) {
        arg_queue.async {
            self.uploadSessions[identifier]?.position = possition
            DispatchQueue.main.async {
                self.UploadList.tableView.reloadData()
                self.delegate?.didRefreshItems()
            }
        }
    }
    
    public func UploadDone(identifier: String) {
        arg_queue.async {
            if let i = self.uploadIdentifers.firstIndex(of: identifier) {
                self.uploadIdentifers.remove(at: i)
            }
            self.uploadSessions[identifier]?.position = self.uploadSessions[identifier]?.size ?? 0
            self.finishedSessions[identifier] = self.uploadSessions[identifier]
            self.finishedSessions[identifier]?.finishDate = Date()
            self.uploadSessions[identifier] = nil
            DispatchQueue.main.async {
                self.UploadCountButton.title = "\(self.uploadIdentifers.count)↑"
                self.UploadList.tableView.reloadData()
                self.delegate?.didRefreshItems()
            }
        }
    }

    public func UploadFailed(identifier: String, errorStr: String? = nil) {
        arg_queue.async {
            if let i = self.uploadIdentifers.firstIndex(of: identifier) {
                self.uploadIdentifers.remove(at: i)
            }
            self.finishedSessions[identifier] = self.uploadSessions[identifier]
            self.finishedSessions[identifier]?.finishDate = Date()
            if let e = errorStr {
                self.finishedSessions[identifier]?.errorStr = e
            }
            else {
                self.finishedSessions[identifier]?.errorStr = "error"
            }
            self.uploadSessions[identifier] = nil
            DispatchQueue.main.async {
                self.UploadCountButton.title = "\(self.uploadIdentifers.count)↑"
                self.UploadList.tableView.reloadData()
                self.delegate?.didRefreshItems()
            }
        }
    }
}

class UploadItemCell: UITableViewCell {
    
    var info: UploadManeger.UploadItemInfo? {
        didSet {
            if (info?.finishDate) != nil {
                if (info?.errorStr) != nil {
                    filenameLabel.text = "[ERROR]" + (info?.filename ?? "")
                    filenameLabel.textColor = .systemRed
                }
                else {
                    filenameLabel.text = "[OK]" + (info?.filename ?? "")
                    filenameLabel.textColor = .systemGreen
                }
            }
            else {
                filenameLabel.text = info?.filename
                if #available(iOS 13.0, *) {
                    filenameLabel.textColor = .label
                } else {
                    filenameLabel.textColor = .black
                }
            }
            if let p = info?.position, let s = info?.size, s != 0 {
                let ratio = Float(p) / Float(s)
                progressView.setProgress(ratio, animated: false)
            }
            else {
                progressView.setProgress(0, animated: false)
            }
        }
    }
    
    private let filenameLabel: UILabel = {
        let label = UILabel()
        if #available(iOS 13.0, *) {
            label.textColor = UIColor.label
        } else {
            label.textColor = UIColor.black
        }
        label.textAlignment = .left
        label.numberOfLines = 0
        return label
    }()
    
    private let progressView: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .default)
        return progress
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        addSubview(filenameLabel)
        addSubview(progressView)

        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        filenameLabel.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor, multiplier: 0.9).isActive = true
        filenameLabel.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor).isActive = true
        filenameLabel.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor).isActive = true
        filenameLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor).isActive = true

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor, multiplier: 0.1).isActive = true
        progressView.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor).isActive = true
        progressView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor).isActive = true
        progressView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class UploadManagerList: UITableViewController {

    let CellId = "cell"
    
    var onClose: (()->Void)?
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        tableView.register(UploadItemCell.self, forCellReuseIdentifier: CellId)
    }

    override func viewDidDisappear(_ animated: Bool) {
        onClose?()
    }
    
    func refresh() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    // MARK: - Table view data source

    override public func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        var count = 0
        UploadManeger.shared.arg_queue.sync {
            count = UploadManeger.shared.uploadIdentifers.count
            count += UploadManeger.shared.finishedSessions.count
        }
        return count
    }
    
    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CellId, for: indexPath) as! UploadItemCell
        UploadManeger.shared.arg_queue.sync {
            if indexPath.row < UploadManeger.shared.uploadIdentifers.count {
                let id = UploadManeger.shared.uploadIdentifers[indexPath.row]
                if let item = UploadManeger.shared.uploadSessions[id] {
                    cell.info = item
                }
            }
            else {
                let finished = UploadManeger.shared.finishedSessions.values.sorted(by: {a,b in
                    (a.finishDate ?? Date(timeIntervalSince1970: 0)) < (b.finishDate ?? Date(timeIntervalSince1970: 0))
                    })
                let i = indexPath.row - UploadManeger.shared.uploadIdentifers.count
                cell.info = finished[i]
            }
        }
        return cell
    }
    
    override public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        var info: String? = nil
        var name: String? = nil
        var delId: String? = nil
        let formatter2 = ByteCountFormatter()
        formatter2.allowedUnits = [.useAll]
        formatter2.countStyle = .file
        UploadManeger.shared.arg_queue.sync {
            if indexPath.row < UploadManeger.shared.uploadIdentifers.count {
                let id = UploadManeger.shared.uploadIdentifers[indexPath.row]
                if let item = UploadManeger.shared.uploadSessions[id] {
                    name = item.filename
                    info = "\(formatter2.string(fromByteCount: Int64(item.position))) / "
                        + "\(formatter2.string(fromByteCount: Int64(item.size)))\n"
                        + "now Uploading..."
                }
            }
            else {
                let finished = UploadManeger.shared.finishedSessions.sorted(by: {a,b in
                    (a.value.finishDate ?? Date(timeIntervalSince1970: 0)) < (b.value.finishDate ?? Date(timeIntervalSince1970: 0))
                    })
                let i = indexPath.row - UploadManeger.shared.uploadIdentifers.count
                let fin = finished[i].value
                delId = finished[i].key
                var reason = "Upload successful"
                if let e = fin.errorStr {
                    reason = "Upload failed : " + e
                }
                name = fin.filename
                info = "\(formatter2.string(fromByteCount: Int64(fin.size)))\n"
                    + reason
            }
        }
        if let strm = info, let strn = name {
            let alert = UIAlertController(title: strn, message: strm, preferredStyle: .alert)
            let cancel = UIAlertAction(title: "OK", style: .cancel, handler: nil)
            alert.addAction(cancel)
            present(alert, animated: true, completion: nil)
        }
        if let d = delId {
            UploadManeger.shared.arg_queue.async {
                UploadManeger.shared.finishedSessions[d] = nil
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
    }
}
