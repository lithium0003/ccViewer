//
//  ViewControllerImage.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import RemoteCloud

class ViewControllerImage: UIViewController, UIScrollViewDelegate, UIDocumentInteractionControllerDelegate {

    @IBOutlet weak var scrollView: UIScrollView!

    @IBOutlet weak var doubleTapGesture: UITapGestureRecognizer!
    @IBOutlet weak var singleTapGesture: UITapGestureRecognizer!
    
    let activityIndicator = UIActivityIndicatorView()
    var documentInteractionController: UIDocumentInteractionController?
    var sending: [URL] = []
    var gone = true

    var imageView: UIImageView!
    var imagedata: UIImage!
    var item: RemoteItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        singleTapGesture.require(toFail: doubleTapGesture)
        
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.0
        scrollView.maximumZoomScale = 3.0
        
        imageView = UIImageView(image: imagedata)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        
        activityIndicator.center = view.center
        activityIndicator.style = .whiteLarge
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            gone = false
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if let image = imageView.image {
            let w_scale = scrollView.frame.width / image.size.width
            let h_scale = scrollView.frame.height / image.size.height
            
            let scale = min(w_scale, h_scale)
            scrollView.zoomScale = scale
            scrollView.contentSize = imageView.frame.size
            let offset = CGPoint(x: (imageView.frame.width - scrollView.frame.width) / 2, y: (imageView.frame.height - scrollView.frame.height) / 2)
            scrollView.setContentOffset(offset, animated: false)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollView.contentInset = UIEdgeInsets(top: max((scrollView.frame.height - imageView.frame.height) / 2, 0), left: max((scrollView.frame.width - imageView.frame.width) / 2, 0), bottom: 0, right: 0)
    }
    
    @IBAction func doubleTap(_ sender: Any) {
        scrollView.setZoomScale(scrollView.zoomScale * 2, animated: true)
    }

    @IBAction func singleTap(_ sender: Any) {
        if let image = imageView.image {
            let w_scale = scrollView.frame.width / image.size.width
            let h_scale = scrollView.frame.height / image.size.height
            
            let scale = min(w_scale, h_scale)
            scrollView.setZoomScale(scale, animated: true)
        }
    }
    
    @IBAction func longTap(_ sender: UILongPressGestureRecognizer) {
        if sender.state != UIGestureRecognizer.State.began {
            return
        }
        
        let location = sender.location(in: self.view)
        exportItem(item: item, rect: CGRect(origin: location, size: CGSize(width: 0, height: 0)))
    }
    
    @IBAction func dissmiss(_ sender: Any) {
        let transition: CATransition = CATransition()
        transition.duration = 0.1
        transition.type = .moveIn
        transition.subtype = .fromLeft
        view.window?.layer.add(transition, forKey: "transition")
        dismiss(animated: false, completion: nil)
    }
    
    func writeTempfile(file: URL,stream: RemoteStream, pos: Int64, size: Int64, onFinish: @escaping ()->Void) {
        var len = 1024*1024
        guard gone else {
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
        activityIndicator.startAnimating()
        
        let stream = item.open()
        writeTempfile(file: url, stream: stream, pos: 0, size: item.size) {
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                
                self.documentInteractionController = UIDocumentInteractionController.init(url: url)
                self.documentInteractionController?.delegate = self
                if self.documentInteractionController?.presentOpenInMenu(from: rect, in: self.view, animated: true) ?? false {
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
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
