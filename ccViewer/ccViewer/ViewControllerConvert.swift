//
//  ViewControllerConvert.swift
//  ccViewer
//
//  Created by rei8 on 2019/09/07.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit

import ffconverter
import RemoteCloud

class ConvertPlayerView: NSObject, AVPlayerViewControllerDelegate {
    static var playing = false
    var target: URL!
    var item: RemoteItem!
    var isVideo = false

    lazy var player: AVPlayer = {
        let player = AVPlayer(url: target)
        return player
    }()

    lazy var playerViewController: AVPlayerViewController = {
        var viewController = AVPlayerViewController()
        viewController.delegate = self
        viewController.allowsPictureInPicturePlayback = !CustomPlayerView.pipVideo
        return viewController
    }()
    
    func play(parent: UIViewController) {
        guard !ConvertPlayerView.playing else {
            return
        }
        ConvertPlayerView.playing = true
        playerViewController.player = player
        
        parent.present(playerViewController, animated: true) {
            self.player.addObserver(self, forKeyPath: "timeControlStatus", options: [.old, .new], context: nil)
            
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(self.didPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: self.player.currentItem)
            center.addObserver(forName: .avPlayerViewDisappear, object: self.playerViewController, queue: nil) { notification in
                if !CustomPlayerView.pipVideo {
                    self.finishDisplay()
                }
            }
            
            self.player.play()
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if object as AnyObject? === player {
            if keyPath == "timeControlStatus" {
                if player.timeControlStatus == .playing {
                    ConvertPlayerView.playing = true
                } else {
                    ConvertPlayerView.playing = false
                }
            }
        }
    }
    
    @objc func didPlayToEndTime(_ notification: Notification) {
        print("didPlayToEndTime")
        if !CustomPlayerView.pipVideo {
            finishDisplay()
        }
        ConvertPlayerView.playing = false
    }
    
    func finishDisplay() {
        playerViewController.player?.pause()
        playerViewController.dismiss(animated: true, completion: nil)
    }
    
    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        CustomPlayerView.pipVideo = true
        return true
    }
    
    func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        
        if let currentViewController = UIApplication.topViewController() {
            currentViewController.present(playerViewController, animated: true) {
                completionHandler(true)
            }
        }
    }
    
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        CustomPlayerView.pipVideo = false
        if playerViewController.player?.rate ?? 0 == 0 {
            finishDisplay()
        }
    }
    
    @objc func appMovedToForeground() {
        print("App moved to ForeGround!")
        if !CustomPlayerView.pipVideo && isVideo {
            playerViewController.player = player
        }
    }
    
    @objc func appMovedToBackground() {
        print("App moved to Background!")
        isVideo = player.currentItem?.asset.tracks(withMediaType: .video).count != 0
        if !CustomPlayerView.pipVideo && isVideo {
            playerViewController.player = nil
        }
    }
}
