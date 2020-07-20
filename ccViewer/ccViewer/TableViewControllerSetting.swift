//
//  TableViewControllerSetting.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import RemoteCloud

class TableViewControllerSetting: UITableViewController, UITextFieldDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.title = NSLocalizedString("Settings", comment: "")
        
        let purchaseButton = UIBarButtonItem(title: NSLocalizedString("Purchase", comment: ""), style: .plain, target: self, action: #selector(settingButtonDidTap))
        
        navigationItem.rightBarButtonItem = purchaseButton
        
        tableView.keyboardDismissMode = .interactive
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.isToolbarHidden = true
    }
    
    @objc func settingButtonDidTap(_ sender: UIBarButtonItem) {
        let next = storyboard!.instantiateViewController(withIdentifier: "Purchase") as? PurchaceViewController
        
        self.navigationController?.pushViewController(next!, animated: true)
    }
    
    func SetPassword(key: String, password: String){
        let data = password.data(using: .utf8)

        guard let _data = data else {
            return
        }

        let dic: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrAccount as String: key,
                                  kSecValueData as String: _data]

        var itemAddStatus: OSStatus?
        let matchingStatus = SecItemCopyMatching(dic as CFDictionary, nil)

        if matchingStatus == errSecItemNotFound {
            // 保存
            itemAddStatus = SecItemAdd(dic as CFDictionary, nil)
        } else if matchingStatus == errSecSuccess {
            // 更新
            itemAddStatus = SecItemUpdate(dic as CFDictionary, [kSecValueData as String: _data] as CFDictionary)
        } else {
            print("保存失敗")
        }

        if itemAddStatus == errSecSuccess {
            print("正常終了")
        } else {
            print("保存失敗")
        }
    }
    
    let sections = [NSLocalizedString("Protect on Lanch", comment: ""), //0
                    NSLocalizedString("Tutorial", comment: ""),         //1
                    NSLocalizedString("Viewer", comment: ""),           //2
                    NSLocalizedString("Software decode", comment: ""),  //3
                    NSLocalizedString("Save play position", comment: ""),//4
                    NSLocalizedString("PlayList", comment: ""),         //5
                    NSLocalizedString("Partial Play", comment: ""),     //6
                    NSLocalizedString("Player control", comment: ""),   //7
                    NSLocalizedString("Cast converter", comment: ""),   //8
                    NSLocalizedString("Network cache", comment: ""),    //9
                    NSLocalizedString("Help", comment: ""),             //10
                    NSLocalizedString("Delete", comment: ""),           //11
    ]
    let settings = [["Password"],
                    [NSLocalizedString("Run one more", comment: "")],
                    [NSLocalizedString("Use Image viewer", comment: ""),
                     NSLocalizedString("Use PDF viewer", comment: ""),
                     NSLocalizedString("Use Media viewer", comment: ""),
                     NSLocalizedString("Lock rotation", comment: ""),
                     NSLocalizedString("Force landscape", comment: "")],
                    [NSLocalizedString("Use FFmpeg Media viewer", comment: ""),
                     NSLocalizedString("Prior Media viewer is FFmpeg", comment: "")],
                    [NSLocalizedString("Save last play position", comment: ""),
                     NSLocalizedString("Resume play at last position", comment: ""),
                     NSLocalizedString("Synchronize on devices", comment: "")],
                    [NSLocalizedString("Synchronize on devices", comment: "")],
                    [NSLocalizedString("Start skip", comment: ""),
                     NSLocalizedString("Stop after specified duration", comment: "")],
                    [NSLocalizedString("Skip foward (sec)", comment: ""),
                     NSLocalizedString("Skip backward (sec)", comment: ""),
                     NSLocalizedString("Keep open when done", comment: "")],
                    [NSLocalizedString("Ignore overlay subtiles", comment: ""),
                     NSLocalizedString("Auto select streams", comment: "")],
                    [NSLocalizedString("Current cache size", comment: ""),
                     NSLocalizedString("Cache limit", comment: "")],
                    [NSLocalizedString("View online help", comment: ""),
                     NSLocalizedString("View privacy policy", comment: ""),
                     NSLocalizedString("Version", comment: ""),
                     NSLocalizedString("About", comment: "")],
                    [NSLocalizedString("Clear all Auth and Cache", comment: "")],
    ]
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return settings[section].count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingItem", for: indexPath)

        // Configure the cell...
        cell.textLabel?.text = settings[indexPath.section][indexPath.row]
        
        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                let textFiled = UITextField(frame: CGRect(x: 10, y: 8, width: 180, height: 28))
                textFiled.placeholder = "password"
                textFiled.borderStyle = .roundedRect
                textFiled.returnKeyType = .done
                textFiled.clearButtonMode = .whileEditing
                textFiled.isSecureTextEntry = true
                textFiled.textContentType = .oneTimeCode
                textFiled.tag = 0;
                textFiled.delegate = self
                cell.accessoryView = textFiled
            default:
                break
            }
        case 1:
            switch indexPath.row {
            case 0:
                cell.accessoryType = .detailButton
            default:
                break;
            }
        case 2:
            let aSwitch = UISwitch()
            aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            switch indexPath.row {
            case 0:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "ImageViewer")
                aSwitch.tag = 1
            case 1:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "PDFViewer")
                aSwitch.tag = 2
            case 2:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "MediaViewer")
                aSwitch.tag = 3
            case 3:
                aSwitch.isEnabled = UIDevice.current.userInterfaceIdiom == .phone
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "MediaViewerRotation")
                aSwitch.tag = 4
            case 4:
                aSwitch.isEnabled = UIDevice.current.userInterfaceIdiom == .phone
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "ForceLandscape")
                aSwitch.tag = 11
            default:
                break
            }
            cell.accessoryView = aSwitch
        case 3:
            let aSwitch = UISwitch()
            aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            switch indexPath.row {
            case 0:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "FFplayer")
                aSwitch.tag = 5
            case 1:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "firstFFplayer")
                aSwitch.tag = 6
            default:
                break
            }
            cell.accessoryView = aSwitch
        case 4:
            let aSwitch = UISwitch()
            aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            switch indexPath.row {
            case 0:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "savePlaypos")
                aSwitch.tag = 7
            case 1:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "resumePlaypos")
                aSwitch.tag = 8
            case 2:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "cloudPlaypos")
                aSwitch.tag = 9
            default:
                break
            }
            cell.accessoryView = aSwitch
        case 5:
            let aSwitch = UISwitch()
            aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            switch indexPath.row {
            case 0:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "cloudPlaylist")
                aSwitch.tag = 10
            default:
                break
            }
            cell.accessoryView = aSwitch
        case 6:
            switch indexPath.row {
            case 0:
                let picker = TimePickerKeyboard(frame: CGRect(x: 0, y: 0, width: 80, height: 28))
                picker.setValue(time: UserDefaults.standard.integer(forKey: "playStartSkipSec")) { value in
                    UserDefaults.standard.set(value, forKey: "playStartSkipSec")
                }
                cell.accessoryView = picker
            case 1:
                let picker = TimePickerKeyboard(frame: CGRect(x: 0, y: 0, width: 80, height: 28))
                picker.setValue(time: UserDefaults.standard.integer(forKey: "playStopAfterSec")) { value in
                    UserDefaults.standard.set(value, forKey: "playStopAfterSec")
                }
                cell.accessoryView = picker
            default:
                break
            }
        case 7:
            switch indexPath.row {
            case 0:
                let picker = SecPickerKeyboard(frame: CGRect(x: 0, y: 0, width: 40, height: 28))
                picker.setValue(time: UserDefaults.standard.integer(forKey: "playSkipForwardSec")) { value in
                    UserDefaults.standard.set(value, forKey: "playSkipForwardSec")
                }
                cell.accessoryView = picker
            case 1:
                let picker = SecPickerKeyboard(frame: CGRect(x: 0, y: 0, width: 40, height: 28))
                picker.setValue(time: UserDefaults.standard.integer(forKey: "playSkipBackwardSec")) { value in
                    UserDefaults.standard.set(value, forKey: "playSkipBackwardSec")
                }
                cell.accessoryView = picker
            case 2:
                let aSwitch = UISwitch()
                aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "keepOpenWhenDone")
                aSwitch.tag = 14
                cell.accessoryView = aSwitch
            default:
                break
            }
        case 8:
            let aSwitch = UISwitch()
            aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
            switch indexPath.row {
            case 0:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "noOverlaySubtitles")
                aSwitch.tag = 12
            case 1:
                aSwitch.isOn = UserDefaults.standard.bool(forKey: "autoSelectStreams")
                aSwitch.tag = 13
            default:
                break
            }
            cell.accessoryView = aSwitch
        case 9:
            switch indexPath.row {
            case 0:
                let formatter2 = ByteCountFormatter()
                formatter2.allowedUnits = [.useAll]
                formatter2.countStyle = .file
                let s2 = formatter2.string(fromByteCount: Int64(CloudFactory.shared.cache.getCacheSize()))
                cell.detailTextLabel?.text = s2
            case 1:
                let limit = CloudFactory.shared.cache.cacheMaxSize
                if limit > 0 {
                    let formatter2 = ByteCountFormatter()
                    formatter2.allowedUnits = [.useAll]
                    formatter2.countStyle = .file
                    let s2 = formatter2.string(fromByteCount: Int64(limit))
                    cell.detailTextLabel?.text = s2
                }
                else {
                    cell.detailTextLabel?.text = NSLocalizedString("Not use", comment: "")
                }
                cell.accessoryType = .disclosureIndicator
            default:
                break
            }
        case 10:
            switch indexPath.row {
            case 0...1,3:
                cell.accessoryType = .detailButton
            case 2:
                cell.detailTextLabel?.text = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            default:
                break;
            }
        case 11:
            break
        default:
            break;
        }

        return cell
    }

    @objc func switchChanged(mySwitch: UISwitch) {
        let value = mySwitch.isOn
        switch mySwitch.tag {
        case 1:
            UserDefaults.standard.set(value, forKey: "ImageViewer")
        case 2:
            UserDefaults.standard.set(value, forKey: "PDFViewer")
        case 3:
            UserDefaults.standard.set(value, forKey: "MediaViewer")
        case 4:
            UserDefaults.standard.set(value, forKey: "MediaViewerRotation")
            let v = UIViewController()
            v.modalPresentationStyle = .fullScreen
            present(v, animated: false) {
                v.dismiss(animated: false, completion: nil)
            }
        case 5:
            UserDefaults.standard.set(value, forKey: "FFplayer")
        case 6:
            UserDefaults.standard.set(value, forKey: "firstFFplayer")
        case 7:
            UserDefaults.standard.set(value, forKey: "savePlaypos")
        case 8:
            UserDefaults.standard.set(value, forKey: "resumePlaypos")
        case 9:
            UserDefaults.standard.set(value, forKey: "cloudPlaypos")
        case 10:
            UserDefaults.standard.set(value, forKey: "cloudPlaylist")
        case 11:
            UserDefaults.standard.set(value, forKey: "ForceLandscape")
            let v = UIViewController()
            v.modalPresentationStyle = .fullScreen
            present(v, animated: false) {
                v.dismiss(animated: false, completion: nil)
            }
        case 12:
            UserDefaults.standard.set(value, forKey: "noOverlaySubtitles")
        case 13:
            UserDefaults.standard.set(value, forKey: "autoSelectStreams")
        case 14:
            UserDefaults.standard.set(value, forKey: "keepOpenWhenDone")
        default:
            break
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
        self.view.endEditing(true)

        switch indexPath.section {
            case 9:
                switch indexPath.row {
                case 1:
                    let contentVC = SizePickerViewController()
                    contentVC.modalPresentationStyle = .popover
                    contentVC.preferredContentSize = CGSize(width: 300, height: 200)
                    var rect = tableView.rectForRow(at: indexPath)
                    rect = CGRect(x: view.frame.width - 30, y: rect.minY, width: 30, height: rect.height)
                    contentVC.popoverPresentationController?.sourceRect = rect
                    contentVC.popoverPresentationController?.sourceView = view
                    contentVC.popoverPresentationController?.permittedArrowDirections = .any
                    contentVC.popoverPresentationController?.delegate = self
                    contentVC.initalValue = CloudFactory.shared.cache.cacheMaxSize
                    contentVC.onSelect = { size in
                        CloudFactory.shared.cache.cacheMaxSize = size
                        CloudFactory.shared.cache.increseFreeSpace()
                        DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                            self.tableView.reloadData()
                        }
                    }
                    present(contentVC, animated: true, completion: nil)
                default:
                    break
                }
        case 11:
            switch indexPath.row {
            case 0:
                deleteAllData()
            default:
                break
            }
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        switch indexPath.section {
        case 1:
            switch indexPath.row {
            case 0:
                let next = storyboard!.instantiateViewController(withIdentifier: "Tutorial")
                next.modalPresentationStyle = .fullScreen
                self.present(next, animated: false)
            default:
                break
            }
        case 10:
            switch indexPath.row {
            case 0:
                let url = URL(string: NSLocalizedString("Online help URL", comment: ""))!
                UIApplication.shared.open(url)
            case 1:
                let url = URL(string: NSLocalizedString("Privacy policy URL", comment: ""))!
                UIApplication.shared.open(url)
            case 3:
                let storyboardAbout = UIStoryboard(name: "About", bundle: nil)
                let next = storyboardAbout.instantiateViewController(withIdentifier: "AboutView")
                self.present(next, animated: false)
            default:
                break
            }
        default:
            break;
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        if textField.tag == 0 {
            SetPassword(key: "password", password: textField.text ?? "")
        }
        
        return true
    }

    @objc func doActionTextField(_ sender: UITextField) {
        SetPassword(key: "password", password: sender.text ?? "")
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    // MARK: - internal
    
    func deleteAllData() {
        let alert = UIAlertController(title: NSLocalizedString("Clear all Auth and Cache", comment: ""),
                                      message: NSLocalizedString("Delete all Auth infomation, Delete all internal cache, Delete all user setting in this app", comment: ""),
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: NSLocalizedString("Abort", comment: ""), style: .cancel)
        let defaultAction = UIAlertAction(title: NSLocalizedString("Delete", comment: ""),
                                          style: .destructive,
                                          handler:{ action in
                                            DispatchQueue.global().async {
                                                self.doDelete {
                                                    DispatchQueue.main.async {
                                                        CloudFactory.shared.initializeDatabase()
                                                        self.navigationController?.popToRootViewController(animated: true)
                                                        (self.navigationController?.viewControllers.first as? TableViewControllerRoot)?.reload()
                                                    }
                                                }
                                            }
        })
        alert.addAction(cancelAction)
        alert.addAction(defaultAction)

        present(alert, animated: true)
    }
    
    func doDelete(onFinish: @escaping ()->Void) {
        defer {
            onFinish()
        }
        CloudFactory.shared.removeAllAuth()
        
        print(UserDefaults.standard.dictionaryRepresentation().keys.count)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        print(UserDefaults.standard.dictionaryRepresentation().keys.count)
        
        CloudFactory.shared.cache.deleteAllCache()
    }

}

extension TableViewControllerSetting: UIPopoverPresentationControllerDelegate {

    // for iPhone
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

class SizePickerViewController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {
    
    let sizeKey = [
        0: NSLocalizedString("Not use", comment: ""),
        1*1000*1000: "1 MB",
        5*1000*1000: "5 MB",
        10*1000*1000: "10 MB",
        50*1000*1000: "50 MB",
        100*1000*1000: "100 MB",
        200*1000*1000: "200 MB",
        500*1000*1000: "500 MB",
        1000*1000*1000: "1 GB",
        2*1000*1000*1000: "2 GB",
        3*1000*1000*1000: "3 GB",
        5*1000*1000*1000: "5 GB",
        10*1000*1000*1000: "10 GB",
        15*1000*1000*1000: "15 GB",
        20*1000*1000*1000: "20 GB",
        25*1000*1000*1000: "25 GB",
        30*1000*1000*1000: "30 GB",
        40*1000*1000*1000: "40 GB",
        50*1000*1000*1000: "50 GB",
    ]
    
    var initalValue = 0
    var onSelect: ((Int)->Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        let pickerView = UIPickerView()
        pickerView.delegate = self
        pickerView.dataSource = self
        view.addSubview(pickerView)
        
        pickerView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor).isActive = true
        pickerView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor).isActive = true
        pickerView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor).isActive = true
        pickerView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor).isActive = true
        
        let val = sizeKey.keys.sorted()
        if let idx = val.firstIndex(where: { $0 >= initalValue }) {
            pickerView.selectRow(idx, inComponent: 0, animated: false)
        }
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return sizeKey.count
    }
    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {

        let pickerLabel: UILabel
        if let v = view as? UILabel {
            pickerLabel = v
        }
        else {
            pickerLabel = UILabel()
        }
        pickerLabel.textAlignment = .center
        if #available(iOS 13.0, *) {
            pickerLabel.font = .monospacedSystemFont(ofSize: 24, weight: .regular)
        }
        else {
            pickerLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
        }
        let key = sizeKey.keys.sorted()[row]
        pickerLabel.text = sizeKey[key]
        return pickerLabel
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let val = sizeKey.keys.sorted()[row]
        onSelect?(val)
    }
}


