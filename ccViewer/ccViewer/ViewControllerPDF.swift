//
//  ViewControllerPDF.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import PDFKit

import RemoteCloud

class ViewControllerPDF: UIViewController, UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate {

    var document: PDFDocument!
    var pdfView: PDFView!
    var thumbnailView: PDFThumbnailView!
    
    @IBOutlet weak var verticalStack: UIStackView!
    @IBOutlet weak var settingView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        pdfView = PDFView()
        pdfView.document = document
        pdfView.backgroundColor = .lightGray
        pdfView.autoScales = true
        pdfView.setContentCompressionResistancePriority(UILayoutPriority.defaultLow, for: .vertical)
        changeSettings()
        verticalStack.addArrangedSubview(pdfView)

        thumbnailView = PDFThumbnailView()
        thumbnailView.backgroundColor = .darkGray
        thumbnailView.layoutMode = .horizontal
        thumbnailView.pdfView = pdfView
        thumbnailView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        verticalStack.addArrangedSubview(thumbnailView)

        let gestureRecognizerRight = UISwipeGestureRecognizer(target: self, action: #selector(rightSwipe))
        gestureRecognizerRight.direction = .right
        pdfView.addGestureRecognizer(gestureRecognizerRight)

        let gestureRecognizerLeft = UISwipeGestureRecognizer(target: self, action: #selector(leftSwipe))
        gestureRecognizerLeft.direction = .left
        pdfView.addGestureRecognizer(gestureRecognizerLeft)

        let gestureRecognizerTap = UITapGestureRecognizer(target: self, action: #selector(tapGesture))
        pdfView.addGestureRecognizer(gestureRecognizerTap)

        let gestureRecognizer2Tap = UITapGestureRecognizer(target: self, action: #selector(doubletapGesture))
        gestureRecognizer2Tap.numberOfTapsRequired = 2;
        pdfView.addGestureRecognizer(gestureRecognizer2Tap)
        
        gestureRecognizerTap.require(toFail: gestureRecognizer2Tap)

        let gestureRecognizerDown = UISwipeGestureRecognizer(target: self, action: #selector(downSwipe))
        gestureRecognizerDown.direction = .down
        pdfView.addGestureRecognizer(gestureRecognizerDown)

        let close_image = UIImage(named: "close")
        let button_close = UIButton()
        button_close.setImage(close_image, for: .normal)
        button_close.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_close.layer.cornerRadius = 10
        button_close.addTarget(self, action: #selector(closebuttonEvent), for: .touchUpInside)
        pdfView.addSubview(button_close)
                
        button_close.translatesAutoresizingMaskIntoConstraints = false
        button_close.topAnchor.constraint(equalTo: pdfView.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
        button_close.leftAnchor.constraint(equalTo: pdfView.safeAreaLayoutGuide.leftAnchor, constant: 10).isActive = true
        button_close.widthAnchor.constraint(equalToConstant: 50).isActive = true;
        button_close.heightAnchor.constraint(equalToConstant: 50).isActive = true;

        let gear_image = UIImage(named: "gear")?.withRenderingMode(.alwaysTemplate)
        let button_config = UIButton()
        button_config.setImage(gear_image, for: .normal)
        button_config.tintColor = .white
        button_config.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_config.layer.cornerRadius = 10
        button_config.addTarget(self, action: #selector(configbuttonEvent), for: .touchUpInside)
        pdfView.addSubview(button_config)
                
        button_config.translatesAutoresizingMaskIntoConstraints = false
        button_config.topAnchor.constraint(equalTo: pdfView.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
        button_config.rightAnchor.constraint(equalTo: pdfView.safeAreaLayoutGuide.rightAnchor, constant: -10).isActive = true
        button_config.widthAnchor.constraint(equalToConstant: 50).isActive = true;
        button_config.heightAnchor.constraint(equalToConstant: 50).isActive = true;
        
        pdfView.goToFirstPage(nil)
    }
        
    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
    }

    func changeSettings() {
        if UserDefaults.standard.bool(forKey: "PDF_continuous") {
            if UserDefaults.standard.bool(forKey: "PDF_twoUp") {
                pdfView.displayMode = .twoUpContinuous
            }
            else {
                pdfView.displayMode = .singlePageContinuous
            }
        }
        else {
            if UserDefaults.standard.bool(forKey: "PDF_twoUp") {
                pdfView.displayMode = .twoUp
            }
            else {
                pdfView.displayMode = .singlePage
            }
        }
        pdfView.displaysRTL = UserDefaults.standard.bool(forKey: "PDF_RTL")
        pdfView.displaysAsBook = UserDefaults.standard.bool(forKey: "PDF_book")
    }
    
    @objc func rightSwipe(_ sender: Any) {
        if !UserDefaults.standard.bool(forKey: "PDF_continuous") {
            if UserDefaults.standard.bool(forKey: "PDF_RTL") {
                if pdfView.canGoToNextPage {
                    pdfView.goToNextPage(nil)
                }
            }
            else {
                if pdfView.canGoToPreviousPage {
                    pdfView.goToPreviousPage(nil)
                }
            }
        }
    }
    
    @objc func leftSwipe(_ sender: Any) {
        if !UserDefaults.standard.bool(forKey: "PDF_continuous") {
            if UserDefaults.standard.bool(forKey: "PDF_RTL") {
                if pdfView.canGoToPreviousPage {
                    pdfView.goToPreviousPage(nil)
                }
            }
            else {
                if pdfView.canGoToNextPage {
                    pdfView.goToNextPage(nil)
                }
            }
        }
    }

    @objc func doubletapGesture(_ sender: Any) {
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.layoutDocumentView()
    }
    
    @objc func tapGesture(_ sender: Any) {
        if thumbnailView.isHidden {
            thumbnailView.isHidden = false
        }
        else {
            settingView.isHidden = !settingView.isHidden
        }
    }

    @objc func configbuttonEvent(_ sender: UIButton) {
        if thumbnailView.isHidden {
            thumbnailView.isHidden = false
        }
        else {
            settingView.isHidden = !settingView.isHidden
        }
    }

    @objc func downSwipe(_ sender: Any) {
        thumbnailView.isHidden = true
    }

    @objc func closebuttonEvent(_ sender: UIButton) {
        dismiss(animated: true, completion: nil)
    }

    var settings = [NSLocalizedString("scroll", comment: ""),
                    NSLocalizedString("twoUp", comment: ""),
                    NSLocalizedString("rightToLeft", comment: ""),
                    NSLocalizedString("frontCover", comment: "")]
    var valuestr = ["PDF_continuous",
                    "PDF_twoUp",
                    "PDF_RTL",
                    "PDF_book"]
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return settings.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PDFsetting", for: indexPath)
        
        // Configure the cell...
        cell.textLabel?.text = settings[indexPath.row]

        let aSwitch = UISwitch()
        aSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        aSwitch.isOn = UserDefaults.standard.bool(forKey: valuestr[indexPath.row])
        aSwitch.tag = indexPath.row+1
        cell.accessoryView = aSwitch
        
        return cell
    }
    
    @objc func switchChanged(mySwitch: UISwitch) {
        let value = mySwitch.isOn
        UserDefaults.standard.set(value, forKey: valuestr[mySwitch.tag-1])
        
        changeSettings()
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.layoutDocumentView()
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

