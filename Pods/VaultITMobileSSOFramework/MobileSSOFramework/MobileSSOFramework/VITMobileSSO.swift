//
//  BuildConfig.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 22/02/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation

/// The logging level of the VITMobileSSO framework. A good value for application development is
/// ".warning" and a good value for production is ".none".
@objc public enum VITMobileSSOLoggingLevel: Int {
    /// All log messages are printed to the console.
    case info
    
    /// Warning level messages are printed to the console. This is recommended for application 
    /// development, as the framework will warn you when doing things in a non-optimal way.
    case warning
    
    /// Error level messages are printed to the console. These messages indicate either a direct misuse
    /// of APIs or fatal errors that occurred when using the API.
    case error
    
    /// No messages will be printed from VITMobileSSOFramework.
    case none
}

/// A class that allows global access to all build variables and has the methods for initial 
/// initialisation of the framework.
@objc public class VITMobileSSO: NSObject {
    
    /// The logging level of the VITMobileSSOFramework. When doing application development, a good value
    /// is .warning, and while doing framework development a good value is .info.
    public static var loggingLevel: VITMobileSSOLoggingLevel = .info
    
    /// Whether or not the file that generated the log message should be included.
    public static var logFilename: Bool = true
    
    /// Whether or not the function name that generated the log message should be included.
    public static var logFunctionName: Bool = false
    
    /// The color for the SFSafariViewController background.
    public static var safariBrandingBackgroundColor: UIColor?
    
    /// The color for the SFSafariViewController action buttons (text, icons).
    public static var safariBrandingActionColor: UIColor?
    
    /// The client id string of this application.
    public static var clientId: String {
        return forceRead(key: "MobileSSOClientId")
    }
    
    /// The client secret of this application.
    public static var clientSecret: String {
        return forceRead(key: "MobileSSOClientSecret")
    }
    
    /// The authentication server (token issuer) URL.
    public static var issuerUrl: URL {
        return forceReadUrl(key: "MobileSSOIssuerURL")
    }
    
    /// The URL where the system browser will redirect after a successful login. 
    /// Will be used in the app to capture the event.
    public static var loginRedirectUri: URL {
        return forceReadUrl(key: "MobileSSOLoginRedirectURI")
    }
    
    /// Used for BankId login flow. The login page uses this URL to resume auth flow and self-redirect 
    /// to wanted landing page (this is required to properly trigger loginRedirectUri).
    public static var loginBankIdResumeUri: URL? {
        return URL(string: Bundle.main.infoDictionary?["MobileSSOBankIdResumeURI"] as? String ?? "")
    }
    
    /// The URL where the system browser will redirect after a successful logout.
    /// Will be used in the app to capture the event.
    public static var logoutRedirectUri: URL {
        return forceReadUrl(key: "MobileSSOLogoutRedirectURI")
    }
    
    /// The shared keychain service name.
    public static var keychainServiceName: String? {
        return Bundle.main.infoDictionary?["MobileSSOKeychainServiceName"] as? String
    }
    
    /// The shared keychain access group.
    public static var keychainAccessGroup: String? {
        return Bundle.main.infoDictionary?["MobileSSOKeychainAccessGroup"] as? String
    }
    
    /// The allowed clock skew tolerance when validating the id token. Default is 120 seconds, 
    /// but you can configure this in the Info.plist by setting "VITMobileSSOClockSkewTolerance" key (Number type) as
    /// seconds.
    public static var clockSkewTolerance: Double {
        return Bundle.main.infoDictionary?["MobileSSOClockSkewTolerance"] as? Double ?? 120.0
    }
    
    /// The entry point of the framework. This must be called before using any methods of the VITSessionManager.
    /// Add the call to the didFinishLaunchingWithOptions method of your AppDelegate.
    public static func initializeSDK(resortToOfflineTimeout: Double = 5.0) {
        VITSessionManager.shared.initialize(resortToOfflineTimeout: resortToOfflineTimeout)
    }
    
    /// Will delete all data stored by this framework. Not intended for normal use but can be useful for testing 
    /// purposes.
    public static func deleteAllData() {
        VITSessionManager.shared.deleteAllData()
    }
    
    /// When the application returns from an inactive state, this method should be called to ensure the 
    /// session state is properly updated.
    public static func willEnterForeground() {
        VITSessionManager.shared.initialize()
    }
    
    /// The method that will read an Info.plist key from a bundle (main bundle by default) and log an error message if the
    /// key is missing. Finally will either return with the value or crash the app by force-unwrapping the value.
    private static func forceRead<T>(key: String, bundle: Bundle = Bundle.main) -> T {
        let value = bundle.infoDictionary?[key] as? T
        
        if value == nil {
            loge("ERROR: \(key) is not configured. You must set this property in the Info.plist of the main bundle.")
        }
        
        return value!
    }

    /// Convenience reader for URL types. Will auto-convert String keys to the URL type.
    private static func forceReadUrl(key: String, bundle: Bundle = Bundle.main) -> URL {
        let urlString: String = forceRead(key: key)
        let url = URL(string: urlString)
        
        if url == nil {
            loge("ERROR: \(key) could not be converted into an URL object. Raw value was \(urlString)")
        }
        
        return url!
    }
    
    
}
