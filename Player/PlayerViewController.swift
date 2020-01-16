//
//  PlayerViewController.swift
//  Player
//
//  Created by Алексей Лысенко on 16.01.2020.
//  Copyright © 2020 Syrup Media Group. All rights reserved.
//

import UIKit

protocol PlayerViewControllerDelegate: AnyObject {
    func playerViewControllerWantDismiss(_ playerVC: PlayerViewController)
}

class PlayerViewController: UIViewController {
    typealias Track = URL
    
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var progressSlider: UISlider!
    @IBOutlet private weak var expandMinifyButton: UIButton!

    private var isCompact: Bool {
        return compactVC == nil
    }
    private var compactVC: PlayerViewController?
    private var playerLayerView: PlayerLayerView = PlayerLayerView()
    private var currentTrack: Track?
    
    // State
    private var firstPlayDone: Bool = false
    private var readyToPlay: Bool = false
    private var isBuffering: Bool = false
    
    weak var delegate: PlayerViewControllerDelegate?
    
    convenience init(_ trackToStartWith: Track) {
        self.init()
        self.currentTrack = trackToStartWith
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        attachPlayer()
        
        if isCompact {
            expandMinifyButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        } else {
            expandMinifyButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
        }
        
        
        if let trackToStartWith = currentTrack, presentingViewController == nil, !firstPlayDone {
            setTrack(trackToStartWith)
            firstPlayDone = true
        }
    }
    
    func setTrack(_ track: Track) {
        self.currentTrack = track
        playerLayerView.playURL(url: track)
        adjustUI()
    }
    
    private func adjustUI() {
        if readyToPlay {
            activityIndicator.stopAnimating()
        } else {
            if isBuffering {
                activityIndicator.startAnimating()
            } else {
                activityIndicator.stopAnimating()
            }
        }
    }
    
    private func attachPlayer() {
        view.insertSubview(playerLayerView, at: 0)
        playerLayerView.translatesAutoresizingMaskIntoConstraints = false
        playerLayerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0).isActive = true
        playerLayerView.topAnchor.constraint(equalTo:  view.topAnchor, constant: 0).isActive = true
        playerLayerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0).isActive = true
        playerLayerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true
        playerLayerView.delegate = self
    }
    
    @IBAction private func closePressed() {
        if let compactVC = compactVC {
            dismiss(animated: true, completion: { [weak compactVC] in
                compactVC?.delegate?.playerViewControllerWantDismiss(compactVC!)
            })
            compactVC.attachPlayer()
        } else {
            self.delegate?.playerViewControllerWantDismiss(self)
        }
    }
    
    @IBAction private func expandPressed() {
        if let compactVC = compactVC {
            dismiss(animated: true, completion: nil)
            compactVC.attachPlayer()
        } else {
            let expandedPlayer = PlayerViewController()
            expandedPlayer.playerLayerView = playerLayerView
            expandedPlayer.currentTrack = currentTrack
            expandedPlayer.compactVC = self
            expandedPlayer.modalPresentationStyle = .overFullScreen
            expandedPlayer.modalTransitionStyle = .crossDissolve
            present(expandedPlayer, animated: true, completion: nil)
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.landscapeLeft, .landscapeRight]
    }
    
    override var shouldAutorotate: Bool { return true }
}

extension PlayerViewController: PlayerLayerViewDelegate {
    func player(player: PlayerLayerView, playerStateDidChange state: PlayerState) {
        switch state {
        case .bufferFinished:
            isBuffering = false
        case .buffering:
            isBuffering = true
        case .error:
            isBuffering = false
            readyToPlay = false
        case .notSetURL:
            isBuffering = false
            readyToPlay = false
        case .playedToTheEnd:
            ()
        case .readyToPlay:
            readyToPlay = true
        }
        adjustUI()
    }
    
    func player(player: PlayerLayerView, loadedTimeDidChange loadedDuration: TimeInterval, totalDuration: TimeInterval) {
        ()
    }
    
    func player(player: PlayerLayerView, playTimeDidChange currentTime: TimeInterval, totalTime: TimeInterval) {
        if !progressSlider.isTracking {
            progressSlider.setValue(Float(currentTime / totalTime), animated: true)            
        }
    }
    
    func player(player: PlayerLayerView, playerIsPlaying playing: Bool) {
        
    }
    
    func player(player: PlayerLayerView, bitrateChangedFrom oldBitrate: Double, to newBitrate: Double) {
        
    }
}

extension UIViewController {
    func show(playerVC: PlayerViewController, inContainer container: UIView) {
        self.addChild(playerVC)
        container.addSubview(playerVC.view)
        
        playerVC.view.translatesAutoresizingMaskIntoConstraints = false
        playerVC.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 0).isActive = true
        playerVC.view.topAnchor.constraint(equalTo:  container.topAnchor, constant: 0).isActive = true
        playerVC.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 0).isActive = true
        playerVC.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: 0).isActive = true
    }
}
