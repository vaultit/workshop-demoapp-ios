//
//  VITSession.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 21/02/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation
import AppAuth
import Alamofire
import ObjectMapper
import ReachabilitySwift

/// Your AppDelegate must implement this protocol in order to make the login and logout flows work.
/// Simply add the currentAuthFlow property to the AppDelegate with an initial value of nil.
@objc public protocol VITMobileSSOAppDelegate: UIApplicationDelegate {
    
    /// The authorization flow used to present and handle the login process.
    /// Access is needed within the AppDelegate, which is why this needs to be in the 
    /// UIApplicationDelegate of the host app.
    var currentAuthFlow: OIDAuthorizationFlowSession? { get set }
    
}

/// Implement this protocol to get notified of changes to the session.
@objc public protocol VITSessionManagerDelegate: NSObjectProtocol {
    
    /// Will be called when the session state has been resolved. You should wait for this event before
    /// presenting the login screen to an user to see if a valid session already exists.
    ///
    /// - Parameter session: Will hold a valid session if one was resumed. If nil, then no session exists 
    ///                      and you must present a login screen to the user with the *presentLogin* method.
    func initialized(session: VITSession?)
    
    /// A session has been resumed succesfully. This will be called when the application returns to 
    /// foreground and a session refresh has been made.
    @objc optional func didResumeSession(session: VITSession)
    
    /// Informs the delegate that reachability is regained for the session. This does not guarantee a 
    /// network connection that actually works, only that the phone is connected to one.
    @objc optional func didRegainNetworkConnectionForSession(session: VITSession)
    
    /// Informs the delegate that reachability is lost for the session. This guarantees no network operations 
    /// will succeed and the app should resort to offline operation.
    @objc optional func didLoseNetworkConnectionForSession(session: VITSession)
    
    /// A session has been lost. This can either happen when returning the app to foreground and detecting an 
    /// unrefreshable session (refresh token has expired) or, when requesting a fresh session with getFreshSession() 
    /// and failing to get or refresh one. You need to use presentLogin to get a new session initialized.
    @objc optional func didLoseSession()
    
    /// User has completed the login flow succesfully and is now logged in.
    ///
    /// - Parameter session: The session that started with the login.
    @objc optional func didCompleteLogin(session: VITSession)
    
    /// A session was refreshed with a refresh token.
    ///
    /// - Parameter session: The new refreshed session.
    @objc optional func didRefreshSession(session: VITSession)
    
    /// User has completed the logout process succesfully. Any session data will be invalid.
    @objc optional func didLogout()
    
}

/// The error domain of VITSessionManager. All errors from this class will use this string.
public let VITSessionManagerErrorDomain = "VITSessionManager"

/// All possible errors that can occur while managing sessions.
@objc public enum VITSessionManagerErrorCode: Int {
    /// The app's AppDelegate is not compliant with VITMobileSSO. The AppDelegate must implement 
    /// VITMobileSSOAppDelegate.
    case invalidAppDelegateError
    
    /// The service configuration could not be loaded.
    case serviceConfigLoadError
    
    /// Token exchange request could not be created. This indicates a bug in VITMobileSSO framework.
    case tokenRequestError
    
    /// The ID token did not validate.
    case idTokenValidateError
    
    /// The session could not be refreshed because no session exists.
    case sessionRefreshNoSessionError
    
    /// The server rejected the refresh token. The refresh token is most probably expired.
    /// To re-login the user, use the *presentLogin* method of VITSessionManager.
    case sessionRefreshOauthError
    
    /// Network error occurred (e.g. no internet connection) while refreshing the session.
    case sessionRefreshNetworkError
    
    /// Server returned an error while refreshing the session. This might indicate a server issue.
    case sessionRefreshServerError
    
    /// The service configuration did not contain an URL for ending the session.
    case logoutErrorNoEndSessionURL
    
    /// Network error occurred (e.g. no internet connection) while trying to log out.
    case logoutErrorNetworkError
    
    /// Server returned an error while logging out. This might indicate a server issue.
    case logoutErrorServerError
    
    /// No idea what happened.
    case unknownError
}

/// Objective-C workaround for errors.
@objc public class VITMobileSSOError: NSObject, Error {
    /// The error code of this error. Will match one of the values in "VITSessionManagerErrorCode".
    var errorCode: Int {
        return (self as! NSError).code
    }
}

/// Intermediate login states for UI flow management.
@objc public enum LoginState: Int {
    /// The discovery configuration was loaded.
    case configurationLoaded
    /// The SFSafariViewController will appear and fill the screen.
    case safariWillAppear
    /// The SFSafariViewController was dismissed.
    case safariDidDisappear
    /// Tokens were succesfully exchanged.
    case tokenExchangeCompleted
    /// Will validate the claims in the ID token payload.
    case idTokenWillValidate
}

/// Typealias for most session method completion listeners. Either the session or the error parameter will be non-nil.
public typealias VITSessionCompletionListener = (_ session: VITSession?, _ error: NSError?) -> Void

/// Some scope constants used by the SDK. This is not an exhaustive list and the server might support more scopes.
@objc public enum OAuthScopes: Int {
    /// The "open_id" scope.
    case openId
    /// The "profile" scope.
    case profile
    
    /// Convert the enum value to the actual scope string.
    func toString() -> String {
        switch self {
        case .openId:
            return "open_id"
        case .profile:
            return "profile"
        default:
            return ""
        }
    }
}

/// All currently supported modes for the acr_values parameter of presentLogin.
@objc public enum AcrValues: Int {
    /// Internal login method (username and password)
    case acrInternal
    
    /// BankID login with Swedish bank credentials.
    case acrBankId
    
    /// Tupas login with Finnish bank credentials.
    case acrTupas
    
    /// Convert the enum value to the actual "acr_values" compliant string.
    func toString() -> String {
        switch self {
        case .acrInternal:
            return "internal"
        case .acrBankId:
            return "bankid"
        case .acrTupas:
            return "tupas"
        }
    }
}

/// The main class for handling session status.
/// The class follows a normal singleton pattern, so you should use it via the VITSessionManager.shared static instance.
open class VITSessionManager {
    
    // MARK: Properties
    
    /// The singleton instance
    public static let shared = VITSessionManager()
    
    /// Weak reference array using NSHashTable. Will always contain VITSessionManagerDelegate objects, so use 
    /// the "delegates" property directly instead of this one when only accessing the delegate list.
    private var delegateRefs = NSHashTable<AnyObject>.weakObjects()
    
    /// All registered delegates. Note that the references are stored with weak strongness.
    public var delegates: [VITSessionManagerDelegate] {
        return delegateRefs.allObjects.filter({$0 != nil}).map({$0 as! VITSessionManagerDelegate})
    }
    
    /// Add a delegate to the VITSessionManager.
    public func addDelegate(_ delegate: VITSessionManagerDelegate) {
        delegateRefs.add(delegate)
        
        if initialized {
            delegate.initialized(session: currentSession)
        }
    }
    
    /// Remove a delegate from the VITSessionManager. You will only need to call this if you want to
    /// end the delegacy before the delegate's lifecycle ends.
    public func removeDelegate(_ delegate: VITSessionManagerDelegate) {
        delegateRefs.remove(delegate)
    }
    
    /// The VITSessionManager status. You should not use the methods of this class until this property is true 
    /// (doing so will print a warning to the log).
    /// Implement the VITSessionManagerDelegate to get notified of the initialization change.
    public private(set) var initialized: Bool = false
    
    /// The current session, if any. Use the framework initialization method (VITMobileSSO.initialize()) to try to 
    /// initially restore the session. Use presentLogin to create a new session if none has been created yet.
    public private(set) var currentSession: VITSession?
    
    /// Convenience: the client secret parameter will not change so store it here directly.
    private let tokenRequestParameters: [String:String] = ["client_secret": VITMobileSSO.clientSecret]
    
    /// The reachability monitor (from SwiftReachability).
    private let reachability: Reachability? = Reachability()
    
    private var sessionCheckCoordinator: VITSessionCheckCoordinator?
    
    // MARK: Methods
    
    /// The initialization method. This is only available at module scope, so initialization needs to be done via the 
    /// VITMobileSSO.initialize() method.
    func initialize(resortToOfflineTimeout: Double = 5.0, completion: VITSessionCompletionListener? = nil) {
        initReachabilityMonitoring()
        
        logi("Restoring session from keychain...")
        
        if let storedSession = VITSessionStorage.loadSession() {
            self.currentSession = storedSession
            
            logi(".. loaded session from keychain. Needs refresh? Expiration is at \(storedSession.idTokenPayload?.expirationTime)")
            
            switch storedSession.sessionStatus {
            case .valid:
                logi(".. session should still be valid, but will try to refresh tokens.")
                fallthrough
            case .expired:
                logi(".. Will refresh tokens.")
                
                var refreshedInTime: Bool = false
                var lateRefresh: Bool = false
                
                // If session is expired, refresh it
                refreshSession { refreshedSession, error in
                    refreshedInTime = true
                    var initializedSession: VITSession?
                    
                    if error == nil {
                        logi("Tokens refreshed. VITSession has been restored succesfully!")
                        initializedSession = refreshedSession
                    }
                    else if error?.code == VITSessionManagerErrorCode.sessionRefreshNetworkError.rawValue {
                        logi("Could not refresh tokens. A network error occurred. Resort to offline data.")
                        initializedSession = refreshedSession
                    }
                    else {
                        logi("Could not refresh tokens. Refresh token might have expired.")
                        initializedSession = nil
                    }
                    
                    // If we could not gain an online session with a late refresh, there is no need to continue with it.
                    if lateRefresh && initializedSession != nil && !initializedSession!.isOnline {
                        logi("Refresh was late and also failed with a network error => continue using offline session.")
                        return
                    }
                    
                    self.callDelegateOnInitializeResult(session: initializedSession, lateRefresh: lateRefresh)
                    
                    // If we gained an online session after resorting to an offline session, also inform the delegate that the session became online.
                    if lateRefresh && initializedSession != nil && initializedSession!.isOnline {
                        logi("Refresh was late but succeeded => change to an online session.")
                        self.delegates.forEach({$0.didRegainNetworkConnectionForSession?(session: initializedSession!)})
                    }
                    
                    // The initial completion has already been called if this was a late refresh.
                    if !lateRefresh {
                        completion?(refreshedSession, error)
                    }
                }
                
                if resortToOfflineTimeout >= 0.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + resortToOfflineTimeout, execute: {
                        if !refreshedInTime {
                            logi("Could not refresh session in time. Resort to offline while waiting for the token refresh.")
                            
                            // Resort to offline data for now
                            storedSession.setOnline(false)
                            self.callDelegateOnInitializeResult(session: storedSession)
                            self.delegates.forEach({$0.didLoseNetworkConnectionForSession?(session: storedSession)})
                            completion?(storedSession, nil)
                            
                            lateRefresh = true
                        }
                    })
                }
            case .noSession:
                logi(".. not a valid session. Continue without it.")
                callDelegateOnInitializeResult(session: nil)
            }
        }
        else {
            logi(".. no session has been saved to keychain. Continue without session.")
            callDelegateOnInitializeResult(session: nil)
        }
    }
    
    private func callDelegateOnInitializeResult(session: VITSession?, lateRefresh: Bool = false) {
        if !initialized {
            initialized = true
            self.delegates.forEach({$0.initialized(session: session)})
        }
        else {
            if session != nil && !lateRefresh {
                self.delegates.forEach({$0.didResumeSession?(session: session!)})
            }
            else if session != nil && lateRefresh {
                self.delegates.forEach({$0.didRefreshSession?(session: session!)})
            }
            else {
                self.delegates.forEach({$0.didLoseSession?()})
            }
        }
    }
    
    private func initReachabilityMonitoring() {
        do {
            try reachability?.startNotifier()
        }
        catch {
            loge("ERROR: Could not start reachability monitoring")
        }
        
        reachability?.whenReachable = { reachability in
            DispatchQueue.main.async {
                if let session = self.currentSession {
                    session.setOnline(true)
                    self.delegates.forEach({$0.didRegainNetworkConnectionForSession?(session: session)})
                }
            }
        }
        
        reachability?.whenUnreachable = { reachability in
            DispatchQueue.main.async {
                if let session = self.currentSession {
                    session.setOnline(false)
                    self.delegates.forEach({$0.didLoseNetworkConnectionForSession?(session: session)})
                }
            }
        }
    }
    
    /// Will call completion listener with a fresh session. Auto-refreshes the tokens if necessary.
    open func getFreshSession(completion: VITSessionCompletionListener?) {
        if let session = currentSession {
            switch session.sessionStatus {
            case .valid:
                // Can use the same session
                completion?(session, nil)
            case .expired:
                // Will need to refresh the session.
                refreshSession() { refreshedSession, error in
                    // The result is the same as in refresh session.
                    completion?(refreshedSession, error)
                    
                    if error != nil {
                        self.delegates.forEach({$0.didLoseSession?()})
                    }
                }
            default:
                completion?(nil, createError(code: .unknownError, message: "VITSession was present but its state was invalid. This is a bug in VITMobileSSOFramework."))
                
                self.currentSession = nil
                let _ = VITSessionStorage.persist(session: nil)
                self.delegates.forEach({$0.didLoseSession?()})
            }
        }
        else {
            completion?(nil, createError(code: .sessionRefreshNoSessionError, message: "No session."))
        }
    }
    
    /// Present the browser that will allow the user to log in and create a session.
    ///
    /// NOTE: This method can also be used for step-up authentication. If you present a login again with a changed acrValues parameter, the
    ///       new login prompt will be displayed and the current session is replaced.
    ///
    /// - Parameter viewController: The host UIViewController that will present the Safari browser.
    /// - Parameter extraScopes: You should set this to all scopes you need beyond the basic .openId and .profile scopes,
    ///                        which are automatically used.
    /// - Parameter acrValues: This parameter is directly passed as the "acr_values" query parameter as described in the
    ///                        OpenID Connect specification. The "acr" is an abbreviation of "Authentication Context 
    ///                        Class Reference", and is used to give authentication hints to the authorizing server.
    ///                        The default backend currently supports the methods defined in the AcrValues enumeration type.
    /// - Parameter stateCompletion An optional callback that is called when intermediate login states complete. 
    ///                             This is useful to display an indication to the user. Any errors while loading are 
    ///                             supplied normally with the completion callback.
    /// - Parameter completion: The completion block. Will be called with the established session or an error if the login 
    ///                         did not succeed.
    open func presentLogin(in viewController: UIViewController, extraScopes: [String] = [], acrValues: [String] = [], prompt: String? = nil, stateCompletion: ((LoginState) -> Void)? = nil, completion: VITSessionCompletionListener? = nil) {
        
        // TODO: This function does way too much. Split into suboperations.
        
        if !initialized {
            logw("Warning: you should wait until VITSessionManager has initialized (implement the VITSessionManagerDelegate protocol to observe this event) before presenting login screen to the user. You might already have a valid session stored.")
        }
        
        OIDAuthorizationService.discoverConfiguration(forIssuer: VITMobileSSO.issuerUrl) { configuration, error in
            stateCompletion?(.configurationLoaded)
            
            guard let configuration = configuration else {
                completion?(nil, self.createError(code: .serviceConfigLoadError, message: "Could not load service configuration from \(VITMobileSSO.issuerUrl)"))
                return
            }
            
            var additionalParameters: [String:String]?
            
            if !acrValues.isEmpty {
                // acr_values is a space-separated list (OpenID connect spec).
                additionalParameters = [
                    "acr_values": acrValues.joined(separator: " ")
                ]
            }
            
            if let promptValue = prompt {
                additionalParameters = additionalParameters ?? [:]
                additionalParameters!["prompt"] = promptValue
            }
            
            // Must check if current session exists and if it has a populated acr claim.
            // If the login method has changed, we must prompt login again. Unless we explicitly
            // want prompt = none of course.
            if let currentLoginAcr = self.currentSession?.idTokenPayload?.acr {
                if !acrValues.contains(currentLoginAcr) && prompt != "none" {
                    additionalParameters = additionalParameters ?? [:]
                    additionalParameters!["prompt"] = "login"
                }
            }
            
            let authRequest = OIDAuthorizationRequest(
                configuration: configuration,
                clientId: VITMobileSSO.clientId,
                scopes: [OIDScopeOpenID, OIDScopeProfile] + extraScopes,
                redirectURL: VITMobileSSO.loginRedirectUri,
                responseType: OIDResponseTypeCode,
                additionalParameters: additionalParameters)
            
            guard let appDelegate = UIApplication.shared.delegate as? VITMobileSSOAppDelegate else {
                // We are stuck using NSError classes for backwards compatibility with Objective-C.
                completion?(nil, self.createError(code: .invalidAppDelegateError, message: "Your AppDelegate should implement the VITMobileSSOAppDelegate protocol."))
                return
            }
            
            stateCompletion?(.safariWillAppear)
            
            let loginFlow = LoginAuthorizationFlow()
            
            appDelegate.currentAuthFlow = loginFlow.present(authRequest: authRequest, in: viewController) { authResponse, error in
                stateCompletion?(.safariDidDisappear)
                
                guard let authResponse = authResponse else {
                    completion?(nil, self.createError(code: .tokenRequestError, message: "Could not log in using Safari."))
                    return
                }
                
                let authState = OIDAuthState(authorizationResponse: authResponse)
                
                guard let tokenRequest = authState.lastAuthorizationResponse.tokenExchangeRequest(withAdditionalParameters: self.tokenRequestParameters) else {
                    completion?(nil, self.createError(code: .tokenRequestError, message: "Could not create OIDTokenRequest from OIDAuthorizationResponse."))
                    return
                }
                
                OIDAuthorizationService.perform(tokenRequest) { tokenResponse, error in
                    if let tokenResponse = tokenResponse {
                        // Initialize VITSession
                        stateCompletion?(.tokenExchangeCompleted)
                        authState.update(with: tokenResponse, error: error)
                        let session = VITSession(authState: authState)
                        
                        stateCompletion?(.idTokenWillValidate)
                        
                        session.validate { success in
                            if success {
                                self.sessionDidEstablish(session: session, completion: completion)
                            }
                            else {
                                completion?(nil, self.createError(code: .idTokenValidateError, message: "The ID token was rejected"))
                            }
                        }
                    }
                    else if let error = error {
                        completion?(nil, error as NSError)
                    }
                }
            }
        }
    }
    
    /// Called after login has established a session.
    private func sessionDidEstablish(session: VITSession, completion: VITSessionCompletionListener?) {
        self.currentSession = session
        let _ = VITSessionStorage.persist(session: session)
        
        completion?(session, nil)
        self.delegates.forEach({$0.didCompleteLogin?(session: session)})
    }
    
    /// Present session check with a custom UI coordinator.
    public func presentSessionCheck(with uiCoordinator: VITSessionCheckUICoordinator, completion: VITSessionCompletionListener? = nil) {
        self.sessionCheckCoordinator = VITSessionCheckCoordinator(uiCoordinator: uiCoordinator)
        self.sessionCheckCoordinator?.begin() { session, error in
            self.sessionCheckCoordinator = nil
            
            if session != nil {
                
            }
            else {
                self.currentSession = nil
                let _ = VITSessionStorage.persist(session: nil)
                self.delegates.forEach({$0.didLoseSession?()})
            }
            
            completion?(session, error)
        }
    }
    
    /// Present a session check.
    public func presentSessionCheck(in viewController: UIViewController, completion: VITSessionCompletionListener? = nil) {
        let uiCoordinator = DefaultVITSessionCheckUICoordinator(viewController: viewController)
        presentSessionCheck(with: uiCoordinator, completion: completion)
    }
    
    /// Try to refresh the session. Will update the currentSession with new tokens.
    open func refreshSession(completion: VITSessionCompletionListener? = nil) {
        let oldSession = currentSession
        
        // refresh with refresh token
        if let refreshRequest = currentSession?.oidAuthState.tokenRefreshRequest(withAdditionalParameters: tokenRequestParameters) {
            OIDAuthorizationService.perform(refreshRequest, callback: { tokenResponse, error in
                let errorCode = (error as? NSError)?.code
                let hadNetworkError = errorCode == OIDErrorCode.networkError.rawValue
                
                if hadNetworkError {
                    loge(".. Error refreshing tokens. Network error. Continue with offline session.")
                    self.currentSession?.setOnline(false)
                    
                    if let session = self.currentSession {
                        self.delegates.forEach({$0.didLoseNetworkConnectionForSession?(session: session)})
                    }
                }
                else if tokenResponse == nil {
                    loge(".. Error refreshing tokens: \(error!)")
                    self.currentSession = nil
                }
                else if tokenResponse != nil {
                    let wasOnline = self.currentSession?.isOnline ?? false
                    
                    self.currentSession?.setOnline(true)
                    self.currentSession?.oidAuthState.update(with: tokenResponse, error: error)
                    
                    if !wasOnline {
                        if let session = self.currentSession {
                            self.delegates.forEach({$0.didRegainNetworkConnectionForSession?(session: session)})
                        }
                    }
                }
                
                let _ = VITSessionStorage.persist(session: self.currentSession)
                
                if self.currentSession != nil {
                    self.delegates.forEach({$0.didRefreshSession?(session: self.currentSession!)})
                    var error: NSError? = nil
                    
                    if hadNetworkError {
                        error = self.createError(code: .sessionRefreshNetworkError, message: "Network error.")
                    }
                    
                    completion?(self.currentSession, error)
                }
                else if let errorCode = (error as? NSError)?.code {
                    switch errorCode {
                    case OIDErrorCode.serverError.rawValue:
                        completion?(nil, self.createError(code: .sessionRefreshServerError, message: "Undefined server error."))
                    default:
                        self.currentSession?.oidAuthState.update(withAuthorizationError: error!)
                        completion?(nil, self.createError(code: .sessionRefreshOauthError, message: "Could not refresh session. Refresh token might have expired."))
                    }
                }
            })
        }
        else {
            completion?(nil, createError(code: .sessionRefreshNoSessionError, message: "There exists no session to refresh."))
        }
    }
    
    /// Logout the user. This method will first check if the session is still valid and then will open a logout URL in 
    /// a SFSafariViewController if it was. All references to the VITSession model will be invalid after a succesful logout.
    ///
    /// - Parameter viewController: The UIViewController that will present the Safari browser.
    /// - Parameter loadingCompletion An optional callback that is called when the auth configuration is loaded from the issuer and before the
    ///                               SFSafariViewController will be presented. This is useful to display a loading indication to the user before
    ///                               the Safari can be presented. Any errors while loading are supplied normally with the completion callback.
    /// - Parameter completion: The completion listener. Will return an error if something happened. See VITSessionManagerErrorCode 
    ///                         enum for possible error codes.
    open func logout(in viewController: UIViewController, loadingCompletion: (() -> Void)? = nil, completion: ((_ error: Error?) -> Void)? = nil) {
        logi("Ending session..")
        
        refreshSession { refreshedSession, error in
            loadingCompletion?()
            
            if let session = refreshedSession {
                logi(".. refreshed the id token")
                
                // Refresh was succesful
                if let endSessionURLStr = session.oidAuthState.lastAuthorizationResponse.request.configuration.discoveryDocument?.discoveryDictionary["end_session_endpoint"] as? String, let endSessionURL = URL(string: endSessionURLStr) {
                    
                    logi(".. opening browser with URL: \(endSessionURLStr)")
                    
                    let logoutFlow = EndSessionAuthorizationFlow()
                    
                    guard let appDelegate = UIApplication.shared.delegate as? VITMobileSSOAppDelegate else {
                        completion?(self.createError(code: .invalidAppDelegateError, message: "Your AppDelegate should implement the VITMobileSSOAppDelegate protocol."))
                        return
                    }
                    
                    appDelegate.currentAuthFlow = logoutFlow.present(in: viewController, url: endSessionURL, idToken: session.idToken, redirectURI: VITMobileSSO.logoutRedirectUri) { resolution in
                        
                        switch resolution {
                        case .success:
                            logi(".. logout successful!")
                            
                            // logged out
                            logi("Logged out!")
                            self.currentSession = nil
                            let _ = VITSessionStorage.deleteSession()
                            
                            self.delegates.forEach({$0.didLogout?()})
                        case .logoutUrlLoadError:
                            completion?(self.createError(code: .logoutErrorNetworkError, message: "Could not load logout URL."))
                        default:
                            // VITSession might or might not exist - will need to check by trying to refresh.
                            self.refreshSession() { session, error in
                                if session == nil {
                                    // Logout has happened.
                                    self.currentSession = nil
                                    let _ = VITSessionStorage.deleteSession()
                                    self.delegates.forEach({$0.didLogout?()})
                                }
                                else {
                                    completion?(self.createError(code: .logoutErrorServerError, message: "Logout could not be completed because of some server error."))
                                }
                            }
                        }
                    }
                }
                else {
                    loge("Logout error! End session URL is unknown.")
                    
                    // Could not resolve the end session URL -> problem with the configuration.
                    completion?(self.createError(code: .logoutErrorNoEndSessionURL, message: "Could not resolve the end session URL from the discovery document."))
                }
            }
            else {
                guard let errorCode = error?.code else {
                    loge("Illegal state error: session was nil and error was nil.")
                    return
                }
                
                switch errorCode {
                case VITSessionManagerErrorCode.sessionRefreshNoSessionError.rawValue:
                    // There is no need to treat this as an error as the end result is desired -> user is logged out.
                    completion?(nil)
                    self.currentSession = nil
                    let _ = VITSessionStorage.deleteSession()
                    self.delegates.forEach({$0.didLogout?()})
                case VITSessionManagerErrorCode.sessionRefreshOauthError.rawValue:
                    // The refresh token is expired.
                    completion?(error)
                case VITSessionManagerErrorCode.sessionRefreshNetworkError.rawValue:
                    completion?(self.createError(code: .logoutErrorNetworkError, message: "Network error occurred while trying to log out. VITSession might still exist."))
                case VITSessionManagerErrorCode.sessionRefreshServerError.rawValue:
                    completion?(self.createError(code: .logoutErrorServerError, message: "Server error occurred. VITSession might still exist."))
                default:
                    completion?(self.createError(code: .unknownError, message: "Unknown error occurred."))
                }
            }
        }
    }
    
    func deleteAllData() {
        self.currentSession = nil
        self.initialized = false
        
        let success = VITSessionStorage.deleteSession()
        
        if success {
            logi("VITSessionManager: Data deletion successful!")
        }
        else {
            loge("VITSessionManager: ERROR! Data deletion not successful")
        }
    }
    
    // MARK: Private

    /// Constructing new instances is disabled. Singleton pattern should be used.
    private init() {
        
    }
    
    /// Convenience function to create ObjC compliant NSError objects.
    private func createError(code: VITSessionManagerErrorCode, message: String) -> NSError {
        return NSError(domain: VITSessionManagerErrorDomain, code: code.rawValue, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
    
}
