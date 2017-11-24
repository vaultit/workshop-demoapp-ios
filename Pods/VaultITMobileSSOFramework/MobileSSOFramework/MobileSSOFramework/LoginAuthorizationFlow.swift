//
//  LoginAuthorizationFlow.swift
//  VITMobileSSOFramework
//
//  Created by Testi on 31/05/2017.
//  Copyright © 2017 Nixu. All rights reserved.
//

import Foundation
import AppAuth
import UIKit
import SafariServices

/// Errors that can occur while logging in.
enum LoginFlowError: Error {
    /// Safari services not available (on iOS <= 8.0). This is not supported.
    case safariServicesNotAvailableError
    /// OAuth error.
    case oauthError
    /// Response state does not match request state. The OAuth response cannot be accepted.
    case stateMismatchError
    /// The login was cancelled.
    case cancelled
    /// The login url could not be loaded.
    case loginUrlLoadError
    /// Auth flow error.
    case authFlowError
    /// The BankID resume url was malformed and could not be interpreted.
    case invalidResumeURL
}

/// The callback function of the login flow.
typealias LoginFlowCallback = (OIDAuthorizationResponse?, LoginFlowError?) -> Void

/// Login flow implementation. Will handle presenting the Safari and will react to any valid redirect URIs.
class LoginAuthorizationFlow: NSObject, OIDAuthorizationFlowSession, SFSafariViewControllerDelegate {

    // MARK: Properties
    
    /// The authorization request data used to perform the flow.
    private var request: OIDAuthorizationRequest!
    
    /// The completion listener. Will be notified of auth flow result.
    private var completionCallback: LoginFlowCallback?
    
    /// Used for performing the authorization flow with iOS 10 or lower.
    /// With iOS 11 we must use SFAuthenticationSession to access system-wide cookies.
    private var safariVC: SFSafariViewController?
    
    /// Used for performing the authorization flow with iOS 11.
    /// With iOS 10 or older we must use the SFSafariViewController because SFAuthenticationSession is not available.
    /// For the same reason this must be stored as NSObject (or Any) because we cannot target below iOS 11 otherwise.
    private var authSession: NSObject?
    
    /// Used for performing the second phase of BankID same device authentication in iOS 11.
    /// Cannot declare as SFAuthenticationSession because it is only available in iOS 11+
    private var authSessionBankIdContinue: NSObject?
    
    /// When using Safari to perform the auth flow, this flag is used to detect if user has manually dismissed the SFSafariViewController
    /// instance.
    private var safariAutoDismissed: Bool = false
    
    /// The view that should present the SFSafariViewController. ONLY used with SFSafariViewController (up to iOS 10) based flow.
    /// The SFAuthenticationSession (iOS 11) will present itself modally without a presenter.
    private var presentingVC: UIViewController?
    
    /// ONLY used with SFSafariViewController (up to iOS 10) based flow. SFAuthenticationSession will always animate (there is no way to affect this).
    private var presentWithAnimation: Bool = true
    
    // MARK: Methods
    
    /// Present the Safari ViewController to the logout URL.
    func present(authRequest: OIDAuthorizationRequest, in viewController: UIViewController, animated: Bool = true, completion: LoginFlowCallback? = nil) -> OIDAuthorizationFlowSession {
        
        let barTint = VITMobileSSO.safariBrandingBackgroundColor
        let controlTint = VITMobileSSO.safariBrandingActionColor
        
        self.presentingVC = viewController
        self.presentWithAnimation = animated
        
        self.request = authRequest
        self.completionCallback = completion
        
        let requestURL = authRequest.authorizationRequestURL()
        
        if #available(iOS 9.0, *) {
            let requiredScheme = VITMobileSSO.loginRedirectUri.scheme
            
            if #available(iOS 11.0, *) {
                let sfAuthSession = SFAuthenticationSession(url: requestURL, callbackURLScheme: requiredScheme, completionHandler: { url, error in
                    if let receivedUrl = url {
                        let _ = self.resumeAuthorizationFlow(with: receivedUrl)
                    }
                    else if let error = error {
                        loge(error)
                        let errorCode = (error as NSError).code
                        
                        if errorCode == 1 {
                            completion?(nil, .cancelled)
                        }
                        else {
                            completion?(nil, .authFlowError)
                        }
                    }
                })
                
                sfAuthSession.start()
                
                self.authSession = sfAuthSession
            } else {
                // Fallback on earlier versions
                safariVC = SFSafariViewController(url: requestURL)
                safariVC?.delegate = self
            }
            
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
            
            if let usesSafariVC = safariVC {
                viewController.present(usesSafariVC, animated: presentWithAnimation, completion: nil)
            }
        }
        else {
            // SafariServices are not available - do we need to support iOS 8 and below?
            completion?(nil, .safariServicesNotAvailableError)
        }
        
        return self
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
            cancel()
        }
    }
    
    /// SFSafariViewControllerDelegate method. Will check if the logout URL could be opened successfully.
    public func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool){
        // IMPORTANT: This method cannot be trusted. Returns false when the response is a redirect.
    }
    
    // MARK: OIDAuthorizationFlowSession
    
    /// Cancels the login flow.
    public func cancel() {
        if #available(iOS 11.0, *) {
            (authSession as? SFAuthenticationSession)?.cancel()
            (authSessionBankIdContinue as? SFAuthenticationSession)?.cancel()
        }
        else {
            safariVC?.dismiss(animated: true, completion: {
                self.completionCallback?(nil, .cancelled)
            })
        }
    }
    
    /// This method will handle the login resume / login redirect URL events.
    public func resumeAuthorizationFlow(with url: URL) -> Bool {
        let redirectURL = request.redirectURL
        let resumeURL = VITMobileSSO.loginBankIdResumeUri
        
        if urlEquality(url, resumeURL) {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            guard let urlString = components?.queryItems?.filter({$0.name == "return_url"}).first?.value?.removingPercentEncoding else {
                completionCallback?(nil, .invalidResumeURL)
                return true
            }
            
            guard let returnUrl = URL(string: urlString) else {
                completionCallback?(nil, .invalidResumeURL)
                return true
            }
            
            if authSession != nil {
                return performBankIdContinueWithSFAuthenticationSession(returnUrl: returnUrl)
            }
            else {
                return performBankIdContinueWithSafari(returnUrl: returnUrl)
            }
        }
        
        if urlEquality(url, redirectURL) {
            let query = OIDURLQueryComponent(url: url)
            
            // checks for an OAuth error response as per RFC6749 Section 4.1.2.1
            if query?.dictionaryValue[OIDOAuthErrorFieldError] != nil {
                safariVC?.dismiss(animated: presentWithAnimation, completion: nil)
                completionCallback?(nil, .oauthError)
                return true
            }
            
            // checks state mismatch
            let receivedState = query?.dictionaryValue["state"] as? String
            if request.state != receivedState {
                loge("ERROR: State mismatch. Expected \(String(describing: request.state)) but got \(String(describing: receivedState))")
                safariVC?.dismiss(animated: presentWithAnimation, completion: nil)
                completionCallback?(nil, .stateMismatchError)
                return true
            }
            
            // no error, succesful response
            let response = OIDAuthorizationResponse(request: request, parameters: query?.dictionaryValue ?? [:])
            safariAutoDismissed = true
            safariVC?.dismiss(animated: presentWithAnimation, completion: nil)
            
            logi("INFO: Login was successful, auth session was dismissed.")
            
            if #available(iOS 11.0, *) {
                (authSession as? SFAuthenticationSession)?.cancel()
                (authSessionBankIdContinue as? SFAuthenticationSession)?.cancel()
            }
            
            completionCallback?(response, nil)
            
            return true
        }
        
        return false
    }
    
    /// Will setup SFAuthenticationSession and handle the flow using that (iOS 11 and later)
    private func performBankIdContinueWithSFAuthenticationSession(returnUrl: URL) -> Bool {
        if #available(iOS 11.0, *) {
            let currentAuthSession = authSession as! SFAuthenticationSession
            
            let scheme = VITMobileSSO.loginBankIdResumeUri?.scheme
            let newAuthSession = SFAuthenticationSession(url: returnUrl, callbackURLScheme: scheme, completionHandler: { url, error in
                if let receivedUrl = url {
                    currentAuthSession.cancel()
                    let _ = self.resumeAuthorizationFlow(with: receivedUrl)
                }
                else if let error = error {
                    loge(error)
                    let errorCode = (error as NSError).code
                    
                    if errorCode == 1 {
                        self.completionCallback?(nil, .cancelled)
                    }
                    else {
                        self.completionCallback?(nil, .authFlowError)
                    }
                }
            })
            
            newAuthSession.start()
            authSessionBankIdContinue = newAuthSession
            
            return true
        }
        else {
            return false
        }
    }
    
    /// Will setup SFSafariViewConroller and handle the flow using that (up to iOS 10).
    private func performBankIdContinueWithSafari(returnUrl: URL) -> Bool {
        // Forget the current Safari
        safariVC?.dismiss(animated: false, completion: nil)
        
        // Create the new Safari to the resume URL
        safariVC = SFSafariViewController(url: returnUrl)
        safariVC?.delegate = self
        presentingVC?.present(safariVC!, animated: false, completion: nil)
        
        // Wait for login redirect...
        
        return true
    }
    
    /// Logout failed with a recognized error. Note that not all errors will come through this. If the logout
    /// URL page has errors, then the error is only detected by not seeing the logout redirect event.
    public func failAuthorizationFlowWithError(_ error: Error) {
        loge("ERROR: Logout fail with error: \(error)")
        completionCallback?(nil, .authFlowError)
    }
    
    /// Checks whether an URL event is the login redirect we are looking for.
    private func urlEquality(_ url1: URL?, _ url2: URL?) -> Bool {
        let standardizedUrl1 = url1?.standardized
        let standardizedUrl2 = url2?.standardized
        
        return standardizedUrl1?.scheme == standardizedUrl2?.scheme
            && standardizedUrl1?.user == standardizedUrl2?.user
            && standardizedUrl1?.password == standardizedUrl2?.password
            && standardizedUrl1?.host == standardizedUrl2?.host
            && standardizedUrl1?.port == standardizedUrl2?.port
            && standardizedUrl1?.path == standardizedUrl2?.path
    }
}
