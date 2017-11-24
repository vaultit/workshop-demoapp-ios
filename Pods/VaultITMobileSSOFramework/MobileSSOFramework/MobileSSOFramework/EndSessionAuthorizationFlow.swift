//
//  EndSessionAuthorizationService.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 23/02/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation
import AppAuth
import SafariServices

/// All possible cases recognized by this AuthorizationFlow implementation.
enum EndSessionResolution {
    /// Logout redirect URL was called and logout was successful.
    case success
    
    /// The logout browser was manually dismissed with the "Done" button. This can be because of couple of reasons:
    /// 
    /// - The user did not wait for the logout URL loading to finish.
    /// - The logout caused a server error, which will not trigger the redirect.
    ///
    /// In all cases the session might or might not be valid. The session status need to be validated 
    /// before coming to a conclusion about the login state.
    case manuallyDismissed
    
    /// The user cancelled the logout flow. This case is currently not supported by VITMobileSSOFramework.
    case cancelled
    
    /// The logout URL failed to load. This might be a network or a URL config issue.
    case logoutUrlLoadError
    
    /// This is an error within the AppAuth SDK.
    case authorizationFlowError
    
    /// SafariServices is available in iOS 9.0+, currently this error will be thrown if the framework is run 
    /// in iOS 8 or lower (not supported).
    case safariServicesNotAvailableError
}

/// Type alias for the completion callback.
typealias EndSessionFlowCallback = (_ resolution: EndSessionResolution) -> Void

/// The implementation of end session logic. This is currently missing from AppAuth SDK.
/// If it later is implemented at the SDK level, consider removing this class.
class EndSessionAuthorizationFlow: NSObject, OIDAuthorizationFlowSession, SFSafariViewControllerDelegate {
    
    // MARK: Private properties
    
    /// The SFSafariViewController used to present the logout flow.
    private var safariVC: SFSafariViewController?
    
    /// The SFAuthenticationSession for alternative logout for iOS 11+ devices.
    /// Cannot mark type as SFAuthenticationSession because it is only available in iOS 11.
    private var authSession: NSObject?
    
    /// The redirect URI that should be used in case of logout is successful.
    private var redirectURI: URL?
    
    /// Completion handler from the present method.
    private var completionCallback: EndSessionFlowCallback?
    
    /// Whether or not the Safari was auto-dismissed. Manual dismissal might indicate an error in the 
    /// logout process and the logout state must be verified.
    private var safariAutoDismissed: Bool = false
    
    // MARK: Methods
    
    /// Present the Safari ViewController to the logout URL.
    ///
    /// Parameters:
    /// - url: The logout url.
    /// - idToken: The id token of the active session.
    /// - viewController: The UIViewController that will present the SFSafariViewController.
    /// - barTint (Optional) The background tint color for the Safari toolbars.
    /// - controlTint (Optional) The action button text & icon color in the Safari toolbars.
    /// - completion The completion handler.
    func present(in viewController: UIViewController, url: URL, idToken: String, redirectURI: URL, completion: EndSessionFlowCallback? = nil) -> OIDAuthorizationFlowSession {
        self.redirectURI = redirectURI
        self.completionCallback = completion
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id_token_hint", value: idToken),
            URLQueryItem(name: "post_logout_redirect_uri", value: redirectURI.absoluteString)
        ]
        
        if let queryUrl = components?.url {
            if #available(iOS 9.0, *) {
                if #available(iOS 11.0, *) {
                    performLogoutWithSFAuthenticationSession(queryUrl: queryUrl)
                }
                else {
                    performLogoutWithSafari(in: viewController, queryUrl: queryUrl)
                }
            }
            else {
                // SafariServices are not available - do we need to support iOS 8 and below?
                completion?(.safariServicesNotAvailableError)
            }
        }
        
        return self
    }
    
    @available(iOS 11.0, *)
    private func performLogoutWithSFAuthenticationSession(queryUrl: URL) {
        let scheme = VITMobileSSO.logoutRedirectUri.scheme
        
        let logoutSession = SFAuthenticationSession(url: queryUrl, callbackURLScheme: scheme, completionHandler: { url, error in
            if let receivedUrl = url {
                let _ = self.resumeAuthorizationFlow(with: receivedUrl)
            }
            else if let error = error {
                loge(error)
                let errorCode = (error as NSError).code
                
                if errorCode == 1 {
                    self.completionCallback?(.manuallyDismissed)
                }
                else {
                    self.completionCallback?(.authorizationFlowError)
                }
            }
        })
        
        logoutSession.start()
        authSession = logoutSession
    }
    
    private func performLogoutWithSafari(in viewController: UIViewController, queryUrl: URL) {
        let barTint = VITMobileSSO.safariBrandingBackgroundColor
        let controlTint = VITMobileSSO.safariBrandingActionColor
        
        safariVC = SFSafariViewController(url: queryUrl)
        safariVC?.delegate = self
        
        if #available(iOS 10.0, *) {
            if barTint != nil {
                safariVC?.preferredBarTintColor = barTint!
            }
            if controlTint != nil {
                safariVC?.preferredControlTintColor = controlTint!
            }
        } else {
            // Just ignore this visual feature on iOS 9.
        }
        
        viewController.present(safariVC!, animated: true, completion: nil)
    }
    
    // MARK: SFSafariViewController
    
    /// SFSafariViewControllerDelegate method. Not used.
    public func safariViewController(_ controller: SFSafariViewController, activityItemsFor URL: URL, title: String?) -> [UIActivity] {
        return []
    }
    
    /// SFSafariViewControllerDelegate method. Will check whether or not the Safari was successfully auto-dismissed 
    /// or if an error occurred.
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        logi("SFSafariViewController did finish")
        
        if !safariAutoDismissed {
            logi("-- the SFSafariViewController finish was user-initiated!")
            
            // The user has been forced to manually press the "Done" button. This might indicate an error 
            // in the process, but not necessarily.
            completionCallback?(.manuallyDismissed)
        }
    }
    
    /// SFSafariViewControllerDelegate method. Will check if the logout URL could be opened successfully.
    public func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool){
        if !didLoadSuccessfully {
            // The logout url loading failed -> the logout cannot have completed.
            completionCallback?(.logoutUrlLoadError)
        }
    }
    
    // MARK: OIDAuthorizationFlowSession
    
    /// Cancels the logout flow.
    public func cancel() {
        completionCallback?(.cancelled)
    }
    
    /// This method will handle the logout redirect URL event.
    public func resumeAuthorizationFlow(with URL: URL) -> Bool {
        if !shouldHandleURL(URL) {
            return false
        }
        
        safariAutoDismissed = true
        
        if #available(iOS 11.0, *) {
            (self.authSession as? SFAuthenticationSession)?.cancel()
            self.completionCallback?(.success)
        }
        else {
            safariVC?.dismiss(animated: true, completion: {
                self.completionCallback?(.success)
            })
        }
        
        return true
    }
    
    /// Logout failed with a recognized error. Note that not all errors will come through this. If the logout 
    /// URL page has errors, then the error is only detected by not seeing the logout redirect event.
    public func failAuthorizationFlowWithError(_ error: Error) {
        loge("ERROR: Logout fail with error: \(error)")
        completionCallback?(.authorizationFlowError)
    }
    
    /// Checks whether an URL event is the logout redirect we are looking for.
    private func shouldHandleURL(_ url: URL) -> Bool {
        let standardizedUrl = url.standardized
        let standardizedRedirectUrl = redirectURI?.standardized
        
        return standardizedUrl.scheme == standardizedRedirectUrl?.scheme
            && standardizedUrl.user == standardizedRedirectUrl?.user
            && standardizedUrl.password == standardizedRedirectUrl?.password
            && standardizedUrl.host == standardizedRedirectUrl?.host
            && standardizedUrl.port == standardizedRedirectUrl?.port
            && standardizedUrl.path == standardizedRedirectUrl?.path
    }
}
