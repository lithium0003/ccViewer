//
//  UITimePickerView.swift
//  ccViewer
//
//  Created by rei8 on 2019/11/07.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class TimePickerKeyboard: UIControl {
    var hour: Int = 0 {
        didSet {
            if hour < 0 {
                hour = 0
            }
            if hour >= 24 {
                hour = 23
            }
            setTextFromTime()
        }
    }
    var min: Int = 0 {
        didSet {
            if min < 0 {
                min = 0
            }
            if min >= 60 {
                min = 59
            }
            setTextFromTime()
        }
    }
    var sec: Int = 0 {
        didSet {
            if sec < 0 {
                sec = 0
            }
            if sec >= 60 {
                sec = 59
            }
            setTextFromTime()
        }
    }
    private var textStore: UILabel!
    private var pickerView: UIPickerView!
    private var inputPosition = 0
    
    private var onFinishEdit: ((Int)->Void)?
    
    func setTextFromTime() {
        if inputPosition == 0 {
            textStore.text = String(format: "%02d:%02d:%02d", hour, min, sec)
        }
        else if inputPosition > 0 && inputPosition <= 6 {
            var str = String(format: "%02d:%02d:%02d", hour, min, sec)
            for i in inputPosition..<6 {
                if i < 2 {
                    let start = str.index(str.startIndex, offsetBy: i)
                    str.replaceSubrange(start...start, with: " ")
                }
                else if i < 4 {
                    let start = str.index(str.startIndex, offsetBy: i+1)
                    str.replaceSubrange(start...start, with: " ")
                }
                else {
                    let start = str.index(str.startIndex, offsetBy: i+2)
                    str.replaceSubrange(start...start, with: " ")
                }
            }
            textStore.text = str
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        localinit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        localinit()
    }
    
    func localinit() {
        textStore = UILabel()
        if #available(iOS 13.0, *) {
            textStore.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        }
        else {
            textStore.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        }
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        addSubview(textStore)
        textStore.translatesAutoresizingMaskIntoConstraints = false
        textStore.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        textStore.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        textStore.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        textStore.heightAnchor.constraint(equalTo: self.heightAnchor).isActive = true
        pickerView = UIPickerView()
        pickerView.delegate = self
        setTextFromTime()
    }
    
    func setValue(time: Int, onFinish: ((Int)->Void)? = nil) {
        onFinishEdit = onFinish
        hour = time / 3600
        min = (time - hour * 3600) / 60
        sec = time - hour * 3600 - min * 60
        setTextFromTime()
    }
    
    @objc func didTap(sender: TimePickerKeyboard) {
        becomeFirstResponder()
    }

    @objc func didTapDone(sender: UIButton) {
        let _ = resignFirstResponder()
    }
    
    @objc func didTapClear(sender: UIButton) {
        hour = 0
        min = 0
        sec = 0
        pickerView.selectRow(hour+60*240, inComponent: 0, animated: true)
        pickerView.selectRow(min+60*240, inComponent: 2, animated: true)
        pickerView.selectRow(sec+60*240, inComponent: 4, animated: true)
    }
    
    override func resignFirstResponder() -> Bool {
        inputPosition = 0
        setTextFromTime()
        onFinishEdit?(hour * 3600 + min * 60 + sec)
        return super.resignFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var inputView: UIView? {
        pickerView.selectRow(hour+60*240, inComponent: 0, animated: false)
        pickerView.selectRow(min+60*240, inComponent: 2, animated: false)
        pickerView.selectRow(sec+60*240, inComponent: 4, animated: false)
        return pickerView
    }
    
    override var inputAccessoryView: UIView? {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.bounds.width, height: 44))
        let spacelItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        let doneItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        let clearItem = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(didTapClear))
        toolbar.setItems([clearItem, spacelItem, doneItem], animated: false)
        return toolbar
    }
}

extension TimePickerKeyboard: UIKeyInput {
    var hasText: Bool {
        return true
    }
    
    func insertText(_ text: String) {
        let text = text.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression, range: text.range(of: text))
        if text.isEmpty {
            inputPosition = 0
        }
        else {
            for c in text {
                let v = Int(String(c)) ?? 0
                inputPosition += 1
                switch inputPosition {
                case 1:
                    hour = v * 10 + hour % 10
                case 2:
                    hour = (hour / 10)*10 + v
                case 3:
                    min = v * 10 + min % 10
                case 4:
                    min = (min / 10)*10 + v
                case 5:
                    sec = v * 10 + sec % 10
                case 6:
                    sec = (sec / 10)*10 + v
                default:
                    break
                }
            }
            if inputPosition > 5 {
                inputPosition = 0
            }
        }
        setTextFromTime()
        if inputPosition == 0 {
            let _ = resignFirstResponder()
        }
    }

    func deleteBackward() {
        inputPosition -= 1
        if inputPosition <= 4 {
            sec = 0
        }
        if inputPosition <= 2 {
            min = 0
        }
        if inputPosition <= 0 {
            hour = 0
            inputPosition = 0
        }
        setTextFromTime()
        if inputPosition == 0 {
            let _ = resignFirstResponder()
        }
    }
}

extension TimePickerKeyboard: UIPickerViewDelegate, UIPickerViewDataSource {

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 6
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return (component % 2 == 0) ? 120*240: 1
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
        if component % 2 == 0 {
            if #available(iOS 13.0, *) {
                pickerLabel.font = .monospacedSystemFont(ofSize: 24, weight: .regular)
            }
            else {
                pickerLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
            }
        }
        else {
            pickerLabel.font = .systemFont(ofSize: 16)
        }
        
        switch component {
        case 0:
            pickerLabel.text = "\(row % 24)"
        case 1:
            pickerLabel.text = "h"
        case 2:
            pickerLabel.text = "\(row % 60)"
        case 3:
            pickerLabel.text = "m"
        case 4:
            pickerLabel.text = "\(row % 60)"
        case 5:
            pickerLabel.text = "s"
        default:
            pickerLabel.text = nil
        }
        return pickerLabel
    }
    
    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        return (component % 2 == 0) ? 50 : 40
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch component {
        case 0:
            hour = row % 24
        case 2:
            min = row % 60
        case 4:
            sec = row % 60
        default:
            break
        }
        pickerView.selectRow(hour+60*240, inComponent: 0, animated: false)
        pickerView.selectRow(min+60*240, inComponent: 2, animated: false)
        pickerView.selectRow(sec+60*240, inComponent: 4, animated: false)
        setNeedsDisplay()
    }
}


class SecPickerKeyboard: UIControl {
    var sec: Int = 0 {
        didSet {
            if sec < 0 {
                sec = 0
            }
            if sec > 999 {
                sec = 999
            }
            setTextFromTime()
        }
    }
    private var textStore: UILabel!
    private var pickerView: UIPickerView!
    private var inputPosition = 0
    
    private var onFinishEdit: ((Int)->Void)?
    
    func setTextFromTime() {
        if inputPosition == 0 {
            textStore.text = String(format: "%03d", sec)
        }
        else if inputPosition > 0 && inputPosition <= 3 {
            var str = String(format: "%03d", sec)
            for i in inputPosition..<3 {
                if i < 3 {
                    let start = str.index(str.startIndex, offsetBy: i)
                    str.replaceSubrange(start...start, with: " ")
                }
            }
            textStore.text = str
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        localinit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        localinit()
    }
    
    func localinit() {
        textStore = UILabel()
        if #available(iOS 13.0, *) {
            textStore.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        }
        else {
            textStore.font = .monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        }
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        addSubview(textStore)
        textStore.translatesAutoresizingMaskIntoConstraints = false
        textStore.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        textStore.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        textStore.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        textStore.heightAnchor.constraint(equalTo: self.heightAnchor).isActive = true
        pickerView = UIPickerView()
        pickerView.delegate = self
        setTextFromTime()
    }
    
    func setValue(time: Int, onFinish: ((Int)->Void)? = nil) {
        onFinishEdit = onFinish
        sec = time
        setTextFromTime()
    }
    
    @objc func didTap(sender: TimePickerKeyboard) {
        becomeFirstResponder()
    }

    @objc func didTapDone(sender: UIButton) {
        let _ = resignFirstResponder()
    }
    
    @objc func didTapClear(sender: UIButton) {
        sec = 0
        pickerView.selectRow(sec+1, inComponent: 0, animated: true)
    }
    
    override func resignFirstResponder() -> Bool {
        inputPosition = 0
        setTextFromTime()
        onFinishEdit?(sec)
        return super.resignFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override var inputView: UIView? {
        pickerView.selectRow(sec-1, inComponent: 0, animated: false)
        return pickerView
    }
    
    override var inputAccessoryView: UIView? {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.bounds.width, height: 44))
        let spacelItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        let doneItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        toolbar.setItems([spacelItem, doneItem], animated: false)
        return toolbar
    }
}

extension SecPickerKeyboard: UIKeyInput {
    var hasText: Bool {
        return true
    }
    
    func insertText(_ text: String) {
        let text = text.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression, range: text.range(of: text))
        if text.isEmpty {
            inputPosition = 0
        }
        else {
            for c in text {
                let v = Int(String(c)) ?? 0
                inputPosition += 1
                switch inputPosition {
                case 1:
                    sec = v * 100
                case 2:
                    sec = (sec / 100)*100 + v * 10
                case 3:
                    sec = (sec / 10)*10 + v
                default:
                    break
                }
            }
            if inputPosition > 2 {
                inputPosition = 0
            }
        }
        setTextFromTime()
        if inputPosition == 0 {
            let _ = resignFirstResponder()
        }
    }

    func deleteBackward() {
        inputPosition -= 1
        if inputPosition <= 0 {
            sec = 1
            inputPosition = 0
        }
        setTextFromTime()
        if inputPosition == 0 {
            let _ = resignFirstResponder()
        }
    }
}

extension SecPickerKeyboard: UIPickerViewDelegate, UIPickerViewDataSource {

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 2
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return (component % 2 == 0) ? 999: 1
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
        if component % 2 == 0 {
            if #available(iOS 13.0, *) {
                pickerLabel.font = .monospacedSystemFont(ofSize: 24, weight: .regular)
            }
            else {
                pickerLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)
            }
        }
        else {
            pickerLabel.font = .systemFont(ofSize: 16)
        }
        
        switch component {
        case 0:
            pickerLabel.text = "\(row + 1)"
        case 1:
            pickerLabel.text = "sec"
        default:
            pickerLabel.text = nil
        }
        return pickerLabel
    }
    
    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        return (component % 2 == 0) ? 50 : 40
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch component {
        case 0:
            sec = row + 1
        default:
            break
        }
        setNeedsDisplay()
    }
}
