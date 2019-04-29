//
//  TableViewControllerSetting.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/09.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

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
            //print("保存失敗")
        }

        if itemAddStatus == errSecSuccess {
            //print("正常終了")
        } else {
            //("保存失敗")
        }
    }
    
    let sections = [NSLocalizedString("Protect on Lanch", comment: ""),
                    NSLocalizedString("Tutorial", comment: ""),
                    NSLocalizedString("Viewer", comment: ""),
                    NSLocalizedString("Software decode", comment: ""),
                    NSLocalizedString("Save play position", comment: ""),
                    NSLocalizedString("PlayList", comment: ""),
                    NSLocalizedString("Help", comment: "")
                    ]
    let settings = [["Password"],
                    [NSLocalizedString("Run one more", comment: "")],
                    [NSLocalizedString("Use Image viewer", comment: ""),
                     NSLocalizedString("Use PDF viewer", comment: ""),
                     NSLocalizedString("Use Media viewer", comment: ""),
                     NSLocalizedString("Lock rotation in Media viewer", comment: "")],
                    [NSLocalizedString("Use FFmpeg Media viewer", comment: ""),
                     NSLocalizedString("Prior Media viewer is FFmpeg", comment: "")],
                    [NSLocalizedString("Save last play position", comment: ""),
                     NSLocalizedString("Resume play at last position", comment: ""),
                     NSLocalizedString("Synchronize on devices", comment: "")],
                    [NSLocalizedString("Synchronize on devices", comment: "")],
                    [NSLocalizedString("View online help", comment: ""),
                     NSLocalizedString("View privacy policy", comment: ""),
                     NSLocalizedString("Version", comment: "")]
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
        
        cell.backgroundColor = .white
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
                if UIDevice.current.userInterfaceIdiom == .phone {
                    aSwitch.isOn = UserDefaults.standard.bool(forKey: "MediaViewerRotation")
                }
                else {
                    aSwitch.isOn = false
                    cell.backgroundColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
                }
                aSwitch.tag = 4
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
            case 0...1:
                cell.accessoryType = .detailButton
            case 2:
                cell.detailTextLabel?.text = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            default:
                break;
            }
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
            if UIDevice.current.userInterfaceIdiom == .phone {
                UserDefaults.standard.set(value, forKey: "MediaViewerRotation")
            }
            else {
                mySwitch.isOn = false
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
        default:
            break
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.tableView.deselectRow(at: indexPath, animated: true)
        self.view.endEditing(true)
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        switch indexPath.section {
        case 1:
            switch indexPath.row {
            case 0:
                let next = storyboard!.instantiateViewController(withIdentifier: "Tutorial")
                self.present(next, animated: false)
            default:
                break
            }
        case 6:
            switch indexPath.row {
            case 0:
                let url = URL(string: NSLocalizedString("Online help URL", comment: ""))!
                UIApplication.shared.open(url)
            case 1:
                let url = URL(string: NSLocalizedString("Privacy policy URL", comment: ""))!
                UIApplication.shared.open(url)
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

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
