//
//  ViewControllerImage.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/13.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class ViewControllerImage: UIViewController, UIScrollViewDelegate {

    @IBOutlet weak var scrollView: UIScrollView!

    @IBOutlet weak var doubleTapGesture: UITapGestureRecognizer!
    @IBOutlet weak var singleTapGesture: UITapGestureRecognizer!
    
    
    var imageView: UIImageView!
    var imagedata: UIImage!
    
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
    
    @IBAction func dissmiss(_ sender: Any) {
        let transition: CATransition = CATransition()
        transition.duration = 0.1
        transition.type = .moveIn
        transition.subtype = .fromLeft
        view.window?.layer.add(transition, forKey: "transition")
        dismiss(animated: false, completion: nil)
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
