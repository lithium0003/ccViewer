//
//  ViewControllerText.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/12.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

import RemoteCloud

class ViewControllerText: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource, UITextFieldDelegate {
    
    let activityIndicator = UIActivityIndicatorView()

    @IBOutlet weak var filenameLabel: UILabel!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var offsetTextField: UITextField!
    @IBOutlet weak var pickerView: UIPickerView!
    @IBOutlet weak var scrollView: UIScrollView!
    var textView: UITextView?
    
    var remoteData: RemoteStream?
    var remoteItem: RemoteItem?
    let decode = ["ascii", "hex", "utf8", "shift-JIS", "EUC", "unicode"]
    var offset: Int64 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        pickerView.delegate = self
        offsetTextField.delegate = self
        
        textView = UITextView()
        textView?.frame.size = scrollView.bounds.size
        textView?.translatesAutoresizingMaskIntoConstraints = true
        textView?.isSelectable = false
        textView?.isEditable = false
        scrollView.addSubview(textView!)
        
        activityIndicator.center = view.center
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
        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        remoteData?.isLive = false
        remoteItem?.cancel()
    }
    
    func convertAscii(c: UInt8) -> String {
        switch c {
        case 0x09, 0x0a, 0x0d, 0x20..<0x7f:
            return String(bytes: [c], encoding: .ascii)!
        default:
            return "."
        }
    }
    
    func setData(data: RemoteItem) {
        self.remoteItem = data
        self.remoteData = data.open()
        DispatchQueue.main.async {
            self.filenameLabel.text = data.name
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.groupingSize = 3
            let sStr = formatter.string(from: data.size as NSNumber) ?? "0"
            self.infoLabel.text = "\(sStr) bytes\t\(String(format: "0x%08x", data.size))"
            self.activityIndicator.startAnimating()
        }
        self.remoteData?.read(position: 0, length: 64*1024, onProgress: nil) { data in
            if let data = data {
                let str = self.convertData(type: 0, data: data)
                DispatchQueue.main.async {
                    self.textView?.font = nil
                    self.textView?.text = str
                    self.textView?.sizeToFit()
                    self.textView?.frame.size.width = self.scrollView.bounds.width
                    self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: self.textView?.frame.maxY ?? 0)
                }
            }
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    func convertData(type: Int, data: Data) -> String {
        switch type {
        case 0:
            return data.map { self.convertAscii(c: $0) }.joined()
        case 1:
            var str = ""
            data.withUnsafeBytes { u8Ptr in
                for ii in 0 ..< data.count {
                    let i = Int64(ii)
                    if i == 0 {
                        str += String(format: "0x%08x : ", i + offset)
                        str += String(repeating: "   ", count: Int((i + offset) % 16))
                    }
                    else if (i + offset) % 16 == 0 {
                        str += String(format: "0x%08x : ", i + offset)
                    }
                    str += String(format: "%02x ", u8Ptr[ii])
                    if (i + offset) % 16 == 15 {
                        str += "\n"
                    }
                }
            }
            return str
        case 2:
            return String(data: data, encoding: .utf8) ?? "failed to convert"
        case 3:
            return String(data: data, encoding: .shiftJIS) ?? "failed to convert"
        case 4:
            return String(data: data, encoding: .japaneseEUC) ?? "failed to convert"
        case 5:
            return String(data: data, encoding: .unicode) ?? "failed to convert"
        default:
            return "invalid"
        }
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return decode.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return decode[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        activityIndicator.startAnimating()
        self.remoteData?.read(position: offset, length: 64*1024, onProgress: nil) { data in
            if let data = data {
                let str = self.convertData(type: row, data: data)
                DispatchQueue.main.async {
                    if row == 1 {
                        self.textView?.font = UIFont.init(name: "Courier", size: 10)
                    }
                    else {
                        self.textView?.font = nil
                    }
                    self.textView?.text = str
                    self.textView?.sizeToFit()
                    self.textView?.frame.size.width = self.scrollView.bounds.width
                    self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: self.textView?.frame.maxY ?? 0)
                    self.scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
                }
            }
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.textView?.sizeToFit()
        self.textView?.frame.size.width = self.scrollView.bounds.width
        self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: self.textView?.frame.maxY ?? 0)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let row = self.pickerView.selectedRow(inComponent: 0)
        activityIndicator.startAnimating()
        
        let newoffset = Int64(textField.text ?? "0", radix: 16) ?? 0
        offset = newoffset
        self.remoteData?.read(position: offset, length: 64*1024, onProgress: nil) { data in
            if let data = data {
                let str = self.convertData(type: row, data: data)
                DispatchQueue.main.async {
                    if row == 1 {
                        self.textView?.font = UIFont.init(name: "Courier", size: 10)
                    }
                    else {
                        self.textView?.font = nil
                    }
                    self.textView?.text = str
                    self.textView?.sizeToFit()
                    self.textView?.frame.size.width = self.scrollView.bounds.width
                    self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: self.textView?.frame.maxY ?? 0)
                    self.scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
                }
            }
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
            }
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
