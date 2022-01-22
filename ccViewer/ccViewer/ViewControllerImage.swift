//
//  ViewControllerImage.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import RemoteCloud
import MapKit

/* Placeholder - this one does not work as UIImage strips most meta data. */
extension UIImage {

    func getExifData() -> CFDictionary? {
        var exifData: CFDictionary? = nil
        if let data = self.jpegData(compressionQuality: 1.0) {
            data.withUnsafeBytes {
                let bytes = $0.baseAddress?.assumingMemoryBound(to: UInt8.self)
                if let cfData = CFDataCreate(kCFAllocatorDefault, bytes, data.count),
                    let source = CGImageSourceCreateWithData(cfData, nil) {
                    exifData = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                }
            }
        }
        return exifData
    }
}

class ViewControllerImage: UIViewController, UIScrollViewDelegate, UIDocumentInteractionControllerDelegate {

    @IBOutlet weak var scrollView: UIScrollView!
   
    @IBOutlet weak var exifDigitalizedDate: UILabel!
    @IBOutlet weak var mapView: MKMapView!
    
    @IBOutlet weak var doubleTapGesture: UITapGestureRecognizer!
    @IBOutlet weak var singleTapGesture: UITapGestureRecognizer!
    
    let activityIndicator = UIActivityIndicatorView()
    var documentInteractionController: UIDocumentInteractionController?
    var sending: [URL] = []
    var gone = true

    var imageView: UIImageView!
    var imagedata: UIImage!
    var items: [RemoteItem] = []
    var data: [Data?] = []
    var images: [UIImage?] = []
    var itemIdx = 0
    var errorIdx: [Int] = []
    
    var isIconShowen = true
    var button_close: UIButton!
    
    var isDownloading = false
    
    lazy var downloadProgress: DownloadProgressViewController = {
        let d = DownloadProgressViewController()
        d.modalPresentationStyle = .custom
        d.transitioningDelegate = self
        return d
    }()
    
    func getExifData() -> [CFString : Any]? {
        // let data :Data = imagedata.jpegData(compressionQuality: 1.0)!
        // Apple strips most of metadata from UImage for security concern, so raw data it is.
        let data = self.data[itemIdx]!
        let options = [kCGImageSourceShouldCache as String: kCFBooleanFalse]
        if let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) {
            let exifData = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [CFString : Any]
//            debugPrint(exifData ?? nil)
            return exifData
        }
        return nil
    }
    
    func updateViewFromEXIF() {
        var errormsg : String = "Reverse Geo Code..."
        defer {
            self.exifDigitalizedDate.attributedText = NSAttributedString(string: errormsg)
        }
        
        guard let exifData = getExifData() else { errormsg = "No EXIF data"; return}
        guard let exifDict = exifData[kCGImagePropertyExifDictionary] as? [CFString : Any] else { errormsg = "Corrupted EXIF data"; return}
        guard let digitizedDate = exifDict[kCGImagePropertyExifDateTimeDigitized] as? String else { errormsg = "No digitized date"; return}
        guard let exifGPS = exifData[kCGImagePropertyGPSDictionary] as? [CFString : Any] else { errormsg = "No GPS info, \(digitizedDate)"; return}
        guard let longitude = exifGPS[kCGImagePropertyGPSLongitude] as? CLLocationDegrees else { errormsg = "No GPS Longitude, \(digitizedDate)"; return}
        guard let latitude = exifGPS[kCGImagePropertyGPSLatitude] as? CLLocationDegrees else { errormsg = "No GPS Latitude, \(digitizedDate)"; return}
        
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) -> Void in
            defer {
                let annotation = MKPointAnnotation()
                annotation.coordinate = location.coordinate
                let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
                        
                self.mapView.addAnnotation(annotation)
                self.mapView.setRegion(region, animated: false)
                
                self.exifDigitalizedDate.attributedText = NSAttributedString(string: "\(place ?? "") +  \(digitizedDate)" )
            }
            
            var place : String? = ""
            if (error != nil) {return}
            
            let pm = placemarks! as [CLPlacemark]
            if (pm.count > 0){
                place = pm[0].name
            }
        }
    }

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
        
        updateViewFromEXIF()
        
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

        let close_image = UIImage(named: "close")
        button_close = UIButton()
        button_close.setImage(close_image, for: .normal)
        button_close.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_close.layer.cornerRadius = 10
        button_close.addTarget(self, action: #selector(closebuttonEvent), for: .touchUpInside)
        view.addSubview(button_close)
                
        button_close.translatesAutoresizingMaskIntoConstraints = false
        button_close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
        button_close.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 10).isActive = true
        button_close.widthAnchor.constraint(equalToConstant: 50).isActive = true;
        button_close.heightAnchor.constraint(equalToConstant: 50).isActive = true;

        let gestureRecognizerDown = UISwipeGestureRecognizer(target: self, action: #selector(downSwipe))
        gestureRecognizerDown.direction = .down
        view.addGestureRecognizer(gestureRecognizerDown)
    }
    
    func iconShow() {
        button_close.isHidden = false
        isIconShowen = true
    }
    
    func iconHide() {
        button_close.isHidden = true
        isIconShowen = false
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            gone = false
        }
    }
    
    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
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
        if isIconShowen {
            iconHide()
        }
        else {
            iconShow()
        }
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
        #if !targetEnvironment(macCatalyst)
        exportItem(rect: CGRect(origin: location, size: CGSize(width: 0, height: 0)))
        #endif
    }
    
    func presentImage(toLeft: Bool) {
        if let im = images[itemIdx] {
            let newImage = UIImageView(image: im)
            let transition = CATransition()
            transition.duration = 0.1
            transition.type = .moveIn
            transition.subtype = toLeft ? .fromRight : .fromLeft
            view.layer.add(transition, forKey: nil)

            imagedata = im
            imageView.removeFromSuperview()
            scrollView.addSubview(newImage)
            imageView = newImage
            if let image = imageView.image {
                let w_scale = scrollView.frame.width / image.size.width
                let h_scale = scrollView.frame.height / image.size.height
                
                let scale = min(w_scale, h_scale)
                scrollView.setZoomScale(scale, animated: false)
            }
            
            updateViewFromEXIF()
        }
        else {
            transrateData(toLeft: toLeft)
        }
    }
    
    func transrateData(toLeft: Bool) {
        if let d = data[itemIdx] {
            let idx = itemIdx
            activityIndicator.startAnimating()
            DispatchQueue.global().async {
                if let image = UIImage(data: d), let fixedImage = image.fixedOrientation() {
                    self.images[idx] = fixedImage
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                        self.presentImage(toLeft: toLeft)
                    }
                }
                else {
                    self.errorIdx += [idx]
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                    }
                }
            }
        }
        else {
            downloadData(toLeft: toLeft)
        }
    }
    
    func downloadData(toLeft: Bool) {
        let idx = itemIdx
        guard items[idx].size > 0 else {
            errorIdx += [idx]
            return
        }
        downloadProgress.filepos = 0
        downloadProgress.filesize = Int(items[idx].size)
        downloadProgress.isLive = true
        present(downloadProgress, animated: false, completion: nil)

        isDownloading = true
        let stream = items[idx].open()
        stream.read(position: 0, length: Int(items[idx].size), onProgress: { pos in
            DispatchQueue.main.async {
                self.downloadProgress.filepos = pos
            }
            return self.downloadProgress.isLive
        }) { data in
            self.isDownloading = false
            guard self.downloadProgress.isLive else {
                stream.isLive = false
                self.items[idx].cancel()
                return
            }
            DispatchQueue.main.async {
                self.downloadProgress.filepos = Int(self.items[idx].size)
            }
            if let data = data {
                self.data[idx] = data
                DispatchQueue.main.async {
                    self.downloadProgress.dismiss(animated: false, completion: nil)
                    self.transrateData(toLeft: toLeft)
                }
            }
            else {
                DispatchQueue.main.async {
                    self.downloadProgress.dismiss(animated: true, completion: nil)
                }
            }
        }
    }
    
    @IBAction func RightSwipeGesture(_ sender: UISwipeGestureRecognizer) {
        guard !isDownloading else {
            return
        }
        itemIdx -= 1
        while errorIdx.contains(itemIdx), itemIdx >= 0 {
            itemIdx -= 1
        }
        if itemIdx < 0 {
            itemIdx = 0
            return
        }
        presentImage(toLeft: false)
    }
    
    @IBAction func LeftSwipeGesuture(_ sender: UISwipeGestureRecognizer) {
        guard !isDownloading else {
            return
        }
        itemIdx += 1
        while errorIdx.contains(itemIdx), itemIdx < items.count {
            itemIdx += 1
        }
        if itemIdx >= items.count {
            itemIdx = items.count - 1
            return
        }
        presentImage(toLeft: true)
    }
    
    
    @objc func downSwipe(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    @objc func closebuttonEvent(_ sender: UIButton) {
        dismiss(animated: true, completion: nil)
    }

    func exportItem(rect: CGRect) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory()) else {
            return
        }
        let freesize = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        
        if items[itemIdx].size >= freesize {
            let alart = UIAlertController(title: "No storage", message: "item is too big", preferredStyle: .alert)
            let okButton = UIAlertAction(title: "OK", style: .default, handler: nil)
            alart.addAction(okButton)
            present(alart, animated: true, completion: nil)
        }
        guard let url = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(items[itemIdx].name) else {
            return
        }
        
        if let d = data[itemIdx] {
            activityIndicator.startAnimating()
            DispatchQueue.global().async {
                do {
                    try d.write(to: url)
                }
                catch {
                    DispatchQueue.main.async {
                        let alart = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                        let okButton = UIAlertAction(title: "OK", style: .default, handler: nil)
                        alart.addAction(okButton)
                        self.present(alart, animated: true, completion: nil)
                    }
                }
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.documentInteractionController = UIDocumentInteractionController(url: url)
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
        else {
            downloadProgress.filepos = 0
            downloadProgress.filesize = Int(items[itemIdx].size)
            downloadProgress.isLive = true
            present(downloadProgress, animated: false, completion: nil)
            
            let stream = items[itemIdx].open()
            stream.read(position: 0, length: Int(items[itemIdx].size), onProgress: { pos in
                DispatchQueue.main.async {
                    self.downloadProgress.filepos = pos
                }
                return self.downloadProgress.isLive
            }) { data in
                guard self.downloadProgress.isLive else {
                    stream.isLive = false
                    self.items[self.itemIdx].cancel()
                    return
                }
                DispatchQueue.main.async {
                    self.downloadProgress.filepos = Int(self.items[self.itemIdx].size)
                }
                if let data = data {
                    self.data[self.itemIdx] = data
                    DispatchQueue.main.async {
                        self.downloadProgress.dismiss(animated: false, completion: nil)
                        self.activityIndicator.startAnimating()
                    }
                    DispatchQueue.global().async {
                        do {
                            try data.write(to: url)
                        }
                        catch {
                            DispatchQueue.main.async {
                                let alart = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                                let okButton = UIAlertAction(title: "OK", style: .default, handler: nil)
                                alart.addAction(okButton)
                                self.present(alart, animated: true, completion: nil)
                            }
                        }
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            self.documentInteractionController = UIDocumentInteractionController(url: url)
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
                else {
                    DispatchQueue.main.async {
                        self.downloadProgress.dismiss(animated: true, completion: nil)
                    }
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

extension ViewControllerImage: UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return CustomPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

