//
//  VITSessionCheckCoordinator.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 17/08/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation
import UIKit

/// The class that handles the additional browser check to see if session cookies exists for 
/// the gluu client.
class VITSessionCheckCoordinator {
    
    /// The UI coordinator to use.
    private let uiCoordinator: VITSessionCheckUICoordinator
    
    /// Constructor.
    init(uiCoordinator: VITSessionCheckUICoordinator) {
        self.uiCoordinator = uiCoordinator
    }
    
    /// Starts the session check.
    func begin(completion: VITSessionCompletionListener?) {
        uiCoordinator.willBeginSessionCheck {
            VITSessionManager.shared.presentLogin(
                in: self.uiCoordinator.safariPresentingViewController,
                extraScopes: [],
                acrValues: [],
                prompt: "none",
                stateCompletion: { state in
                    if state == .configurationLoaded {
                        self.uiCoordinator.willDownloadDiscoveryDocument()
                    }
                    else if state == .safariWillAppear {
                        self.uiCoordinator.willPresentSafariViewController()
                    }
            }, completion: { session, error in
                self.uiCoordinator.didFinishWithResult(success: session != nil) {
                    completion?(session, error)
                }
            })
        }
    }
    
}
