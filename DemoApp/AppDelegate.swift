//
//  AppDelegate.swift
//  DemoApp
//
//  Created by Testi on 15/11/2017.
//  Copyright © 2017 Nixu. All rights reserved.
//

import UIKit
import VaultITMobileSSOFramework
import AppAuth

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, VITMobileSSOAppDelegate {

    var window: UIWindow?
    var currentAuthFlow: OIDAuthorizationFlowSession?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        
        // We recommend you call initializeSDK here.
        // This will read any persisted sessions and check their validity, and
        // also refresh access tokens.
        VITMobileSSO.initializeSDK(resortToOfflineTimeout: 5.0)
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // NOTE: Calling willEnterForeground here is optional but recommended.
        // It will refresh the session state since we don't know how long the
        // app have been in the background (might be days if the phone is not
        // used much).
        //
        // Any noticed changes to session state will be sent to the registered
        // VITSessionManagerDelegates.
        VITMobileSSO.willEnterForeground()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        
    }

    func applicationWillTerminate(_ application: UIApplication) {
        
    }
    
    // NOTE: This method is only required for iOS versions 9 and 10 that use
    // SafariViewController for login.
    // From iOS 11 the SDK uses a different approach with SFAuthenticationSession.
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        // Sends the URL to the current authorization flow (if any) which will process it if it relates to an authorization response.
        if currentAuthFlow?.resumeAuthorizationFlow(with: url) ?? false {
            currentAuthFlow = nil
            return true
        }
        
        // Your additional URL handling (if any) goes here.
        
        return false
    }


}

