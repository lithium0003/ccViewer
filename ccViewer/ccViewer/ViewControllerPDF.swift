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
        
        pdfView.goToFirstPage(nil)
    }
    
    @IBAction func dismiss(_ sender: Any) {
        let transition: CATransition = CATransition()
        transition.duration = 0.05
        transition.type = .push
        transition.subtype = .fromLeft
        view.window?.layer.add(transition, forKey: "transition")
        dismiss(animated: false, completion: nil)
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
                if pdfView.canGoToNextPage() {
                    pdfView.goToNextPage(nil)
                }
            }
            else {
                if pdfView.canGoToPreviousPage() {
                    pdfView.goToPreviousPage(nil)
                }
            }
        }
    }
    
    @objc func leftSwipe(_ sender: Any) {
        if !UserDefaults.standard.bool(forKey: "PDF_continuous") {
            if UserDefaults.standard.bool(forKey: "PDF_RTL") {
                if pdfView.canGoToPreviousPage() {
                    pdfView.goToPreviousPage(nil)
                }
            }
            else {
                if pdfView.canGoToNextPage() {
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

    @objc func downSwipe(_ sender: Any) {
        thumbnailView.isHidden = !thumbnailView.isHidden
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

