//
//  VITSessionStorage.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 23/02/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation
import SwiftKeychainWrapper
import AppAuth
import ObjectMapper

/// A class for handling the session persisting and restoration logic.
class VITSessionStorage {
    
    /// Key for storing the AuthState object.
    private static let AuthStateKey = "VITMobileSSOAuthState"
    /// Key for storing the UserProfile json.
    private static let UserProfileKey = "VITMobileSSOUserProfile"
    
    /// Convenience access to the keychain wrapper.
    private static var keychain: KeychainWrapper {
        if let serviceName = VITMobileSSO.keychainServiceName {
            return KeychainWrapper(serviceName: serviceName, accessGroup: VITMobileSSO.keychainAccessGroup)
        }
        else {
            return KeychainWrapper.standard
        }
    }
    
    /// Persists a session or deletes it if nil was passed. VITSession is persisted with .whenUnlocked accessibility level
    ///
    /// - Returns True, if the operation was successful, nil otherwise.
    public static func persist(session: VITSession?) -> Bool {
        if session == nil {
            return deleteSession()
        }
        else {
            // NOTE: Default accessibility level is KeychainItemAccessibility.whenUnlocked.
            let success = keychain.set(session!.oidAuthState, forKey: AuthStateKey)
            
            if !success {
                let _ = deleteSession()
            }
            
            return success
        }
    }
    
    /// Tries to load a persisted session.
    ///
    /// - Returns The session if one had been persisted, nil otherwise.
    public static func loadSession() -> VITSession? {
        if let authState = keychain.object(forKey: AuthStateKey) as? OIDAuthState {
            return VITSession(authState: authState)
        }
        else {
            return nil
        }
    }
    
    /// Delete a session from the keychain. This is equivalent for calling persist(session: nil).
    public static func deleteSession() -> Bool {
        let keychain = self.keychain // Only create the keychain wrapper once.
        let _ = keychain.removeObject(forKey: UserProfileKey)
        return keychain.removeObject(forKey: AuthStateKey)
    }
    
}
