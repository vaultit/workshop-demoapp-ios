//
//  ViewController.swift
//  DemoApp
//
//  Created by Testi on 15/11/2017.
//  Copyright © 2017 Nixu. All rights reserved.
//

import UIKit
import VaultITMobileSSOFramework

class ViewController: UIViewController, VITSessionManagerDelegate {

    @IBOutlet weak var loginActionsContainer: UIStackView!
    @IBOutlet weak var sessionStatusContainer: UIStackView!
    
    @IBOutlet weak var userNameLabel: UILabel!
    @IBOutlet weak var loggedInHeader: UILabel!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var logoutButton: UIButton!
    
    @IBOutlet weak var sessionStatusLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Register a delegate to listen to SDK events.
        VITSessionManager.shared.addDelegate(self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func didClickRestoreSession(_ sender: Any) {
        print("Present session check")
        VITSessionManager.shared.presentSessionCheck(in: self)
    }
    
    @IBAction func didClickLogin(_ sender: Any) {
        print("Present login")
        VITSessionManager.shared.presentLogin(in: self, acrValues: ["internal"])
    }
    
    @IBAction func didClickLogout(_ sender: Any) {
        print("Present logout")
        VITSessionManager.shared.logout(in: self)
    }
    
    // Implement some VITSessionManagerDelegate methods to monitor session state.
    
    func initialized(session: VITSession?) {
        updateState(session: session)
    }
    
    func didLoseNetworkConnectionForSession(session: VITSession) {
        updateState(session: session)
    }
    
    func didRegainNetworkConnectionForSession(session: VITSession) {
        updateState(session: session)
    }
    
    func didCompleteLogin(session: VITSession) {
        updateState(session: session)
    }
    
    func didLogout() {
        updateState(session: nil)
    }
    
    private func updateState(session: VITSession?) {
        let loggedIn = session != nil
        
        // All of these visible when logged in
        loggedInHeader.isHidden = !loggedIn
        userNameLabel.isHidden = !loggedIn
        logoutButton.isHidden = !loggedIn
        sessionStatusContainer.isHidden = !loggedIn
        
        // All of this visible when logged out
        loginActionsContainer.isHidden = loggedIn
        
        userNameLabel.text = session?.idTokenPayload?.name
        sessionStatusLabel.text = session?.isOnline ?? false ? "ONLINE" : "OFFLINE"
    }
    
}

