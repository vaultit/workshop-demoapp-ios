//
//  VITSessionCheckUICoordinator.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 15/08/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation
import UIKit

/// A public protocol to allow customizing the UI effort needed to perform the Safari-based session check.
@objc public protocol VITSessionCheckUICoordinator: NSObjectProtocol {
    
    /// This method will be called before any other UI action will take place. Here you can decide how to inform the user 
    /// about the Safari that is about to pop into the screen. The check will not continue until you call the provided 
    /// completion block.
    ///
    /// Parameter completion: Call this function block when you are ready to continue the session checking process.
    func willBeginSessionCheck(completion: @escaping () -> Void)
    
    /// This method will be called when the SDK will begin downloading the GLUU discovery document to find out all the 
    /// required login authorization endpoints and other configuration. This might be a very fast or very slow process 
    /// depending on the network connection. Here you can show some sort of spinner or something.
    func willDownloadDiscoveryDocument()
    
    /// This method is called when the discovery doc is downloaded and before the Safari is presented.
    func willPresentSafariViewController()
    
    /// This method is called when the session check finishes. The success parameter is true if a session was found, 
    /// false otherwise. The VITSessionManagerDelegate will only be called after you call the provided completion block.
    ///
    /// - Parameter completion: Call this function block when you are ready to provide the result with the VITSessionManagerDelegate.
    func didFinishWithResult(success: Bool, completion: @escaping () -> Void)
    
    /// The UIViewController instance that should present the required SFSafariViewController.
    var safariPresentingViewController: UIViewController { get }
    
}

/// The default VITSessionCheckUICoordinator used by the SDK.
@objc public class DefaultVITSessionCheckUICoordinator: NSObject, VITSessionCheckUICoordinator {
    
    /// The UIViewController in which to present the UI elements.
    private var parentVC: UIViewController?
    /// The overlay view that holds all subviews.
    private var overlay: UIView!
    /// The effect view that blurs the view below the session check UI.
    private var blurredEffectView: UIVisualEffectView!
    /// The label to show info messages to the user.
    private var label: UILabel!
    
    /// Returns the parent view controller given at initialize time.
    public var safariPresentingViewController: UIViewController {
        return parentVC!
    }
    
    /// Constructor.
    init(viewController: UIViewController? = nil) {
        parentVC = viewController ?? UIApplication.shared.keyWindow?.rootViewController
    }
    
    /// Protocol implementation - will display the blur effect and the initial info label.
    public func willBeginSessionCheck(completion: @escaping () -> Void) {
        guard let parentVC = self.parentVC else {
            completion()
            return
        }
        
        overlay = UIView(frame: parentVC.view.bounds)
        
        let blurEffect = UIBlurEffect(style: .dark)
        
        blurredEffectView = UIVisualEffectView()
        blurredEffectView.frame = overlay.bounds
        
        parentVC.view.addSubview(overlay)
        parentVC.view.addSubview(blurredEffectView)
        
        overlay.bindFrameToSuperviewBounds()
        blurredEffectView.bindFrameToSuperviewBounds()
        
        label = UILabel(frame: overlay.bounds)
        label.textColor = UIColor.white
        label.font = UIFont.systemFont(ofSize: 20.0)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = NSLocalizedString("vaultITMobileSSODefaultLoginExpiredMessage", comment: "")
        
        parentVC.view.addSubview(label)
        
        label.bindFrameToSuperviewBounds(insetBy: UIEdgeInsets(top: 0, left: 40, bottom: 0, right: 40))
        
        UIView.animate(withDuration: 1.0, animations: {
            self.blurredEffectView.effect = blurEffect
        }, completion: { _ in
            completion()
        })
    }
    
    /// Protocol implementation - does nothing.
    public func willDownloadDiscoveryDocument() {
        
    }
    
    /// Protocol implementation - does nothing.
    public func willPresentSafariViewController() {
        
    }
    
    /// Protocol implementation - will display the result label and fade out the UI after a small delay.
    public func didFinishWithResult(success: Bool, completion: @escaping () -> Void) {
        var resultLabelText = NSLocalizedString("vaultITMobileSSODefaultSessionCheckFailedMessage", comment: "")
        
        if success {
            resultLabelText = NSLocalizedString("vaultITMobileSSODefaultSessionCheckSuccessMessage", comment: "")
        }
        
        let resultLabel = UILabel()
        resultLabel.text = resultLabelText
        resultLabel.font = UIFont.systemFont(ofSize: 20.0)
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 0
        resultLabel.textColor = UIColor.white
        
        self.parentVC!.view.addSubview(resultLabel)
        
        resultLabel.bindFrameToSuperviewBounds(insetBy: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
        resultLabel.transform = CGAffineTransform.identity.scaledBy(x: 0.01, y: 0.01)
        
        UIView.animate(withDuration: 0.6, animations: {
            self.label.transform = CGAffineTransform.identity.scaledBy(x: 0.01, y: 0.01)
            self.label.alpha = 0
            
            resultLabel.alpha = 1
            resultLabel.transform = CGAffineTransform.identity
        }, completion: { _ in
            self.label.removeFromSuperview()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                UIView.animate(withDuration: 0.5, animations: {
                    self.blurredEffectView.effect = nil
                    self.overlay.alpha = 0
                    resultLabel.alpha = 0
                    resultLabel.transform = CGAffineTransform.identity.scaledBy(x: 0.01, y: 0.01)
                }, completion: { _ in
                    self.blurredEffectView.removeFromSuperview()
                    self.overlay.removeFromSuperview()
                    resultLabel.removeFromSuperview()
                    
                    completion()
                })
            })
        })
    }
    
}

/// A small UIView extension to programmatically generate autolayout constraints.
/// Keep it private so it does not pollute any larger namespaces.
fileprivate extension UIView {
    
    /// IMPORTANT: Call AFTER the view has been added to view hierarchy.
    /// Creates autolayout constraints to bind the view to the size and edges of its superview.
    func bindFrameToSuperviewBounds(insetBy: UIEdgeInsets = UIEdgeInsets.zero) {
        guard let superview = self.superview else {
            print("Error! `superview` was nil – call `addSubview(view: UIView)` before calling `bindFrameToSuperviewBounds()` to fix this.")
            return
        }
        
        let left = insetBy.left
        let right = insetBy.right
        let top = insetBy.top
        let bottom = insetBy.bottom
        
        self.translatesAutoresizingMaskIntoConstraints = false
        superview.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-\(left)-[subview]-\(right)-|", options: .directionLeadingToTrailing, metrics: nil, views: ["subview": self]))
        superview.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-\(top)-[subview]-\(bottom)-|", options: .directionLeadingToTrailing, metrics: nil, views: ["subview": self]))
    }
}
