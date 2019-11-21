//
//  playerView.swift
//  fftest
//
//  Created by rei8 on 2019/10/18.
//  Copyright © 2019 lithium03. All rights reserved.
//

import Foundation
import UIKit

final class FrameworkResource {
    static func getImage(name: String) -> UIImage? {
        return UIImage(named: name, in: Bundle(for: self), compatibleWith: nil)
    }
    static func getLocalized(key: String) -> String {
        return Bundle(for: self).localizedString(forKey: key, value: nil, table: nil)
    }
}

public class FFPlayerViewController: UIViewController {
    public static var inFocus = true
    
    var captionText: UILabel!
    var popupText: UILabel!
    var posText: UILabel!
    var progressView: UIProgressView!
    var slider: UISlider!
    var imageView: UIImageView!
    var artworkView: UIImageView!
    var button_close: UIButton!
    var play_image: UIImage!
    var pause_image: UIImage!
    var button_play: UIButton!
    var button_next00: UIButton!
    var button_prev00: UIButton!
    var button_nextp: UIButton!
    var button_prevp: UIButton!
    var button_video: UIButton!
    var button_sound: UIButton!
    var button_subtitle: UIButton!
    var label_title: UILabel!
    var indicator: UIActivityIndicatorView!
    
    var seeking = false
    var seekingDone = false
    var playing = false
    var soundOnly = false
    
    var lastTap: Date?
    var iconIsShown = true
    
    var imageWidth: CGFloat = 0
    var imageHeight: CGFloat = 0

    var possition = 0.0
    var totalTime = 1.0
    var onSeek: ((Double) -> Void)?
    var onSeekChapter: ((Int) -> Void)?
    var onClose: ((Bool)->Void)?
    var getPause: (()->Bool)?
    var onPause: ((Bool)->Void)?
    var onCycleCh: ((Int)->Void)?
    var skip_nextsec = 30
    var skip_prevsec = 30
    
    var video_title = ""
    var cache_ccText = ""
    var cache_ccOrgText = ""

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        
        let fsec = UserDefaults.standard.integer(forKey: "playSkipForwardSec")
        if fsec > 0 {
            skip_nextsec = fsec
        }
        let bsec = UserDefaults.standard.integer(forKey: "playSkipBackwardSec")
        if bsec > 0 {
            skip_prevsec = bsec
        }

        artworkView = UIImageView()
        artworkView.contentMode = .scaleAspectFit
        view.addSubview(artworkView)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        artworkView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        artworkView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        artworkView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        imageView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        imageView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        captionText = UILabel()
        captionText.font = .systemFont(ofSize: 28)
        captionText.numberOfLines = 0
        captionText.lineBreakMode = .byWordWrapping
        captionText.textAlignment = .left
        captionText.backgroundColor = UIColor(white: 0, alpha: 0.5)
        captionText.tintColor = .white
        view.addSubview(captionText)

        captionText.translatesAutoresizingMaskIntoConstraints = false
        captionText.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor).isActive = true
        captionText.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -5).isActive = true
        captionText.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -5).isActive = true
        captionText.isHidden = true
        
        label_title = UILabel()
        label_title.text = video_title
        label_title.numberOfLines = 0
        label_title.lineBreakMode = .byWordWrapping
        label_title.textAlignment = .center
        label_title.backgroundColor = UIColor(white: 0, alpha: 0.5)
        label_title.tintColor = .white
        view.addSubview(label_title)
        
        label_title.translatesAutoresizingMaskIntoConstraints = false
        label_title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
        label_title.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor, constant: 20).isActive = true
        label_title.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -60).isActive = true

        let close_image = FrameworkResource.getImage(name: "close")
        button_close = UIButton()
        button_close.setImage(close_image, for: .normal)
        button_close.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_close.layer.cornerRadius = 10
        button_close.addTarget(self, action: #selector(closebuttonEvent), for: .touchUpInside)
        view.addSubview(button_close)
                
        button_close.translatesAutoresizingMaskIntoConstraints = false
        button_close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10).isActive = true
        button_close.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 10).isActive = true
        button_close.widthAnchor.constraint(equalToConstant: 30).isActive = true;
        button_close.heightAnchor.constraint(equalToConstant: 30).isActive = true;

        play_image = FrameworkResource.getImage(name: "play")
        pause_image = FrameworkResource.getImage(name: "pause")
        button_play = UIButton()
        button_play.setImage(play_image, for: .normal)
        button_play.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_play.layer.cornerRadius = 10
        button_play.addTarget(self, action: #selector(playbuttonEvent), for: .touchUpInside)
        view.addSubview(button_play)
        
        button_play.translatesAutoresizingMaskIntoConstraints = false
        button_play.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor).isActive = true
        button_play.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100).isActive = true

        let play_next00 = FrameworkResource.getImage(name: "next00")
        button_next00 = UIButton()
        button_next00.setImage(play_next00, for: .normal)
        button_next00.setTitle(String(format: "%02d", skip_nextsec), for: .normal)
        button_next00.setTitleColor(.systemGreen, for: .normal)
        button_next00.titleEdgeInsets = UIEdgeInsets(top: 0, left: -50, bottom: -25, right: 0)
        button_next00.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_next00.layer.cornerRadius = 10
        button_next00.addTarget(self, action: #selector(next00buttonEvent), for: .touchUpInside)
        view.addSubview(button_next00)
        
        button_next00.translatesAutoresizingMaskIntoConstraints = false
        button_next00.leftAnchor.constraint(equalTo: button_play.rightAnchor, constant: 30).isActive = true
        button_next00.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100).isActive = true
        button_next00.widthAnchor.constraint(equalToConstant: 50).isActive = true

        let play_nextp = FrameworkResource.getImage(name: "nextp")
        button_nextp = UIButton()
        button_nextp.setImage(play_nextp, for: .normal)
        button_nextp.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_nextp.layer.cornerRadius = 10
        button_nextp.addTarget(self, action: #selector(nextpbuttonEvent), for: .touchUpInside)
        view.addSubview(button_nextp)
        
        button_nextp.translatesAutoresizingMaskIntoConstraints = false
        button_nextp.leftAnchor.constraint(equalTo: button_next00.rightAnchor, constant: 30).isActive = true
        button_nextp.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100).isActive = true
 
        let play_prev00 = FrameworkResource.getImage(name: "prev00")
        button_prev00 = UIButton()
        button_prev00.setImage(play_prev00, for: .normal)
        button_prev00.setTitle(String(format: "%02d", skip_prevsec), for: .normal)
        button_prev00.setTitleColor(.systemGreen, for: .normal)
        button_prev00.titleEdgeInsets = UIEdgeInsets(top: 0, left: -50, bottom: -25, right: 0)
        button_prev00.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_prev00.layer.cornerRadius = 10
        button_prev00.addTarget(self, action: #selector(prev00buttonEvent), for: .touchUpInside)
        view.addSubview(button_prev00)
        
        button_prev00.translatesAutoresizingMaskIntoConstraints = false
        button_prev00.rightAnchor.constraint(equalTo: button_play.leftAnchor, constant: -30).isActive = true
        button_prev00.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100).isActive = true
        button_prev00.widthAnchor.constraint(equalToConstant: 50).isActive = true

        let play_prevp = FrameworkResource.getImage(name: "prevp")
        button_prevp = UIButton()
        button_prevp.setImage(play_prevp, for: .normal)
        button_prevp.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_prevp.layer.cornerRadius = 10
        button_prevp.addTarget(self, action: #selector(prevpbuttonEvent), for: .touchUpInside)
        view.addSubview(button_prevp)
        
        button_prevp.translatesAutoresizingMaskIntoConstraints = false
        button_prevp.rightAnchor.constraint(equalTo: button_prev00.leftAnchor, constant: -30).isActive = true
        button_prevp.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100).isActive = true
 
        let play_video = FrameworkResource.getImage(name: "video")
        button_video = UIButton()
        button_video.setImage(play_video, for: .normal)
        button_video.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_video.layer.cornerRadius = 10
        button_video.tag = 0
        button_video.addTarget(self, action: #selector(cyclebuttonEvent), for: .touchUpInside)
        view.addSubview(button_video)
        
        button_video.translatesAutoresizingMaskIntoConstraints = false
        button_video.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor).isActive = true
        button_video.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 30).isActive = true

        let play_sound = FrameworkResource.getImage(name: "sound")
        button_sound = UIButton()
        button_sound.setImage(play_sound, for: .normal)
        button_sound.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_sound.layer.cornerRadius = 10
        button_sound.tag = 1
        button_sound.addTarget(self, action: #selector(cyclebuttonEvent), for: .touchUpInside)
        view.addSubview(button_sound)
        
        button_sound.translatesAutoresizingMaskIntoConstraints = false
        button_sound.topAnchor.constraint(equalTo: button_video.bottomAnchor, constant: 30).isActive = true
        button_sound.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 30).isActive = true

        let play_subtile = FrameworkResource.getImage(name: "subtitle")
        button_subtitle = UIButton()
        button_subtitle.setImage(play_subtile, for: .normal)
        button_subtitle.backgroundColor = UIColor(white: 0, alpha: 0.5)
        button_subtitle.layer.cornerRadius = 10
        button_subtitle.tag = 2
        button_subtitle.addTarget(self, action: #selector(cyclebuttonEvent), for: .touchUpInside)
        view.addSubview(button_subtitle)
        
        button_subtitle.translatesAutoresizingMaskIntoConstraints = false
        button_subtitle.bottomAnchor.constraint(equalTo: button_video.topAnchor, constant: -30).isActive = true
        button_subtitle.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 30).isActive = true

        progressView = UIProgressView()
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapAction))
        progressView.addGestureRecognizer(tapRecognizer)
        view.addSubview(progressView)
        
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor).isActive = true
        progressView.heightAnchor.constraint(equalToConstant: 20).isActive = true
        progressView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true

        slider = UISlider()
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderDone), for: .touchUpInside)
        slider.addTarget(self, action: #selector(sliderDone), for: .touchUpOutside)
        view.addSubview(slider)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor).isActive = true
        slider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        slider.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        slider.isHidden = true
        
        posText = UILabel()
        posText.font = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .regular)
        posText.backgroundColor = UIColor(white: 0, alpha: 0.5)
        view.addSubview(posText)
        
        posText.translatesAutoresizingMaskIntoConstraints = false
        posText.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        posText.bottomAnchor.constraint(lessThanOrEqualTo: progressView.topAnchor).isActive = true
        posText.bottomAnchor.constraint(lessThanOrEqualTo: slider.topAnchor).isActive = true
        
        let swipeDown = UISwipeGestureRecognizer()
        swipeDown.addTarget(self, action: #selector(downGesture))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)
        
        indicator = UIActivityIndicatorView()
        indicator.layer.cornerRadius = 10
        if #available(iOS 13.0, *) {
            indicator.style = .large
        } else {
            indicator.style = .whiteLarge
        }
        indicator.color = .white
        indicator.backgroundColor = UIColor(white: 0, alpha: 0.8)
        indicator.hidesWhenStopped = true
        indicator.startAnimating()
        view.addSubview(indicator)
        
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        indicator.widthAnchor.constraint(equalToConstant: 100).isActive = true
        indicator.heightAnchor.constraint(equalToConstant: 100).isActive = true
        
        popupText = UILabel()
        popupText.font = .systemFont(ofSize: 28)
        popupText.numberOfLines = 0
        popupText.lineBreakMode = .byWordWrapping
        popupText.textAlignment = .left
        popupText.backgroundColor = UIColor(white: 0, alpha: 0.5)
        popupText.tintColor = .white
        view.addSubview(popupText)

        popupText.translatesAutoresizingMaskIntoConstraints = false
        popupText.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor).isActive = true
        popupText.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor).isActive = true
        popupText.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -5).isActive = true
        popupText.isHidden = true
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGesture))
        tapGestureRecognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGestureRecognizer)
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lastTap = Date()
        hideTest()
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override public var prefersStatusBarHidden: Bool {
        return !iconIsShown
    }
    
    override open var shouldAutorotate: Bool {
        if UserDefaults.standard.bool(forKey: "MediaViewerRotation") {
            return false
        }
        return true
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UserDefaults.standard.bool(forKey: "ForceLandscape") {
            return .landscapeLeft
        }
        return .all
    }

    @objc func tapGesture(gestureRecognizer: UITapGestureRecognizer){
        lastTap = Date()
        if !iconIsShown {
            showIcons()
        }
        hideTest()
    }
    
    func hideTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if let lastTap = self.lastTap {
                if self.iconIsShown, lastTap.timeIntervalSinceNow < -4 {
                    if !self.soundOnly {
                        self.hideIcons()
                    }
                    self.lastTap = nil
                }
            }
        }
    }
    
    func updatePosition(t: Double) {
        possition = t
        let p = getPause?() ?? false
        DispatchQueue.main.async {
            if self.soundOnly && !self.iconIsShown {
                self.showIcons()
            }
            if !self.seeking || self.seekingDone {
                self.setPosition()
            }
            if p != !self.playing {
                if p {
                    self.button_play.setImage(self.play_image, for: .normal)
                }
                else {
                    self.button_play.setImage(self.pause_image, for: .normal)
                }
                self.playing = !p
            }
        }
    }
    
    func displayImage(image: UIImage, t: Double) {
        updatePosition(t: t)
        DispatchQueue.main.async {
            self.imageView.image = image
        }
    }
    
    func convertLanguageText(lang: String, media: Int, idx: Int) -> String {
        let mediaStr: String
        switch media {
        case 0:
            mediaStr = FrameworkResource.getLocalized(key: "Video") + " : "
        case 1:
            mediaStr = FrameworkResource.getLocalized(key: "Audio") + " : "
        case 2:
            mediaStr = FrameworkResource.getLocalized(key: "Subtitles") + " : "
        default:
            mediaStr = ""
        }
        if idx < 0 {
            return mediaStr + "off"
        }
        return mediaStr + FrameworkResource.getLocalized(key: lang) + "(\(idx))"
    }
    
    func changeLanguage(lang: String, media: Int, idx: Int) {
        DispatchQueue.main.async {
            self.popupText.text = self.convertLanguageText(lang: lang, media: media, idx: idx);
            self.popupText.isHidden = false
            DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                self.popupText.isHidden = true
                self.popupText.text = nil
            }
        }
    }
    
    func convertText(text: String, ass: Bool) -> String {
        let txtArray = text.components(separatedBy: .newlines)
        if ass {
            var ret = ""
            for assline in txtArray {
                guard let p1 = assline.firstIndex(of: ":") else {
                    continue
                }
                var asstext = assline[p1...].dropFirst()
                var invalid = false
                for _ in 0..<9 {
                    guard let p2 = asstext.firstIndex(of: ",") else {
                        invalid = true
                        break
                    }
                    asstext = asstext[p2...].dropFirst()
                }
                if invalid {
                    continue
                }
                let cmdremoved = asstext.replacingOccurrences(of: "{\\.*}", with: "", options: .regularExpression, range: asstext.range(of: asstext))
                let result = cmdremoved.replacingOccurrences(of: "\\\\[Nn]", with: "\n", options: .regularExpression, range: cmdremoved.range(of: cmdremoved))
                ret += result
            }
            return ret
        }
        else {
            return txtArray.joined(separator: "\n")
        }
    }
    
    func displayCCtext(text: String?, ass: Bool) {
        if let text = text {
            let ftxt: String
            if text == cache_ccOrgText {
                ftxt = cache_ccText
            }
            else {
                ftxt = convertText(text: text, ass: ass)
                cache_ccText = ftxt
                cache_ccOrgText = text
            }
            DispatchQueue.main.async {
                self.captionText.text = ftxt
                self.captionText.sizeToFit()
                self.captionText.isHidden = false
            }
        }
        else {
            DispatchQueue.main.async {
                self.captionText.text = nil
                self.captionText.isHidden = true
            }
        }
    }
    
    func hideIcons() {
        iconIsShown = false
        label_title.isHidden = true
        posText.isHidden = true
        button_close.isHidden = true
        button_play.isHidden = true
        button_next00.isHidden = true
        button_prev00.isHidden = true
        button_nextp.isHidden = true
        button_prevp.isHidden = true
        button_video.isHidden = true
        button_sound.isHidden = true
        button_subtitle.isHidden = true
        progressView.isHidden = true
        setNeedsStatusBarAppearanceUpdate()
    }

    func showIcons() {
        iconIsShown = true
        label_title.isHidden = false
        posText.isHidden = false
        button_close.isHidden = false
        button_play.isHidden = false
        button_next00.isHidden = false
        button_prev00.isHidden = false
        button_nextp.isHidden = false
        button_prevp.isHidden = false
        button_video.isHidden = false
        button_sound.isHidden = false
        button_subtitle.isHidden = false
        progressView.isHidden = false
        setNeedsStatusBarAppearanceUpdate()
    }

    func seek(ratio: Float) {
        let pos = Double(ratio) * totalTime
        DispatchQueue.global().async {
            self.onSeek?(pos)
        }
    }

    func waitStop() {
        DispatchQueue.main.async {
            self.indicator.stopAnimating()
        }
    }
    
    func waitStart() {
        DispatchQueue.main.async {
            self.indicator.startAnimating()
        }
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        imageWidth = imageView.frame.width
        imageHeight = imageView.frame.height
    }
    
    func seekDone(pos: Float) {
        slider.isHidden = true
        progressView.isHidden = false
        progressView.setProgress(pos, animated: false)
        indicator.startAnimating()
        seekingDone = true
        seek(ratio: pos)
    }
    
    override public var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    @objc func tapAction(_ sender:UITapGestureRecognizer) {
        lastTap = Date()
        hideTest()
        slider.isHidden = false
        progressView.isHidden = true
        seeking = false
        seekingDone = false
        DispatchQueue.main.asyncAfter(deadline: .now()+3) {
            if !self.seeking {
                self.slider.isHidden = true
                self.progressView.isHidden = false
            }
        }
    }
    
    @objc func sliderChanged(_ sender: UISlider) {
        lastTap = Date()
        seeking = true
        posText.text = getSeekText(ratio: sender.value)
    }

    @objc func sliderDone(_ sender: UISlider) {
        lastTap = Date()
        hideTest()
        seekDone(pos: sender.value)
    }
    
    @objc func closebuttonEvent(_ sender: UIButton) {
        DispatchQueue.global().async {
            self.onClose?(true)
        }
        dismiss(animated: true, completion: nil)
    }
    
    @objc func downGesture(_ sender: UISwipeGestureRecognizer) {
        guard FFPlayerViewController.inFocus else {
            return
        }
        DispatchQueue.global().async {
            self.onClose?(true)
        }
        dismiss(animated: true, completion: nil)
    }
    
    func getTimeText(t: Double) -> String {
        var t1 = t
        let hour = Int(t1 / 3600)
        t1 -= Double(hour * 3600)
        let min = Int(t1 / 60)
        t1 -= Double(min * 60)
        let sec = Int(t1)
        t1 -= Double(sec)
        let usec = Int(t1 * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hour, min, sec, usec)
    }
    
    func getTimeText() -> String {
        return getTimeText(t: possition) + " / " + getTimeText(t: totalTime)
    }
    
    func getSeekText(ratio: Float) -> String {
        let target = Double(ratio) * totalTime
        return "Seeking to \(getTimeText(t: target)) (\(String(format: "%05.2f%%", ratio * 100)))"
    }
    
    func setPosition() {
        posText.text = getTimeText()
        let pos = Float(possition / totalTime)
        progressView.setProgress(pos, animated: false)
        slider.value = pos
    }

    @objc func next00buttonEvent(_ sender: UIButton) {
        lastTap = Date()
        hideTest()
        indicator.startAnimating()
        DispatchQueue.global().async {
            self.onSeek?(self.possition + Double(self.skip_nextsec))
        }
    }

    @objc func prev00buttonEvent(_ sender: UIButton) {
        lastTap = Date()
        hideTest()
        indicator.startAnimating()
        DispatchQueue.global().async {
            self.onSeek?(self.possition - Double(self.skip_prevsec))
        }
    }

    @objc func nextpbuttonEvent(_ sender: UIButton) {
        lastTap = Date()
        hideTest()
        indicator.startAnimating()
        DispatchQueue.global().async {
            self.onSeekChapter?(1)
        }
    }

    @objc func prevpbuttonEvent(_ sender: UIButton) {
        lastTap = Date()
        hideTest()
        indicator.startAnimating()
        DispatchQueue.global().async {
            self.onSeekChapter?(-1)
        }
    }

    @objc func cyclebuttonEvent(_ sender: UIButton) {
        lastTap = Date()
        hideTest()
        indicator.startAnimating()
        let tag = sender.tag
        DispatchQueue.global().async {
            self.onCycleCh?(tag)
        }
    }

    @objc func playbuttonEvent(_ sender: UIButton) {
        lastTap = Date()
        hideTest()
        let p = getPause?() ?? false
        if !p {
            button_play.setImage(play_image, for: .normal)
        }
        else {
            button_play.setImage(pause_image, for: .normal)
        }
        DispatchQueue.global().async {
            self.onPause?(!p)
        }
    }
}
