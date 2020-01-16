//
//  ViewController.swift
//  Player
//
//  Created by Алексей Лысенко on 16.01.2020.
//  Copyright © 2020 Syrup Media Group. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet private weak var containerView: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    @IBAction private func startPressed() {
        let contentUrl = URL(string: "https://bitdash-a.akamaihd.net/content/MI201109210084_1/m3u8s/f08e80da-bf1d-4e3d-8899-f0f6155f6efa.m3u8")!
        
        let playerVC = PlayerViewController(contentUrl)
        playerVC.delegate = self
        show(playerVC: playerVC, inContainer: containerView)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let presentedViewController = presentedViewController, !presentedViewController.isBeingDismissed {
            return .all
        } else {
            return .portrait
        }
    }
}

extension ViewController: PlayerViewControllerDelegate {
    func playerViewControllerWantDismiss(_ playerVC: PlayerViewController) {
        playerVC.view.removeFromSuperview()
        playerVC.removeFromParent()
    }
}
