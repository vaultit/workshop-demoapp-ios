//
//  VITSession.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 21/02/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation
import ObjectMapper
import AppAuth

/// All possible values for session status.
@objc public enum VITSessionStatus: UInt {
    /// No session is available.
    case noSession
    
    /// The session has expired and needs refresh.
    case expired
    
    /// The session is valid.
    case valid
}

/// A class that holds information about the current session and its tokens (access, refresh, id tokens). 
/// Also automatically parses the profile information out of the id token.
@objc public class VITSession: NSObject {

    /// Is true if the user is authorized.
    open var isAuthorized: Bool {
        return oidAuthState.isAuthorized
    }
    
    /// The current session status.
    open var sessionStatus: VITSessionStatus {
        if let expirationTime = idTokenPayload?.expirationTime {
            let now = Date()
            
            if now >= expirationTime {
                return .expired
            }
            else {
                return .valid
            }
        }
        else {
            return .noSession
        }
    }
    
    /// The online state of the session. If a session refresh fails because of a network error, 
    /// the session will go into an offline state.
    private(set) open var isOnline: Bool = true
    
    /// The current access token if a session exists.
    open var accessToken: String {
        return oidAuthState.lastTokenResponse!.accessToken!
    }
    
    /// The refresh token to refresh a session (you should not need to use this manually, see
    /// VITSessionManager.shared.refreshSession instead).
    open var refreshToken: String {
        return oidAuthState.refreshToken!
    }
    
    /// The raw string containing all the authorization scopes for the session.
    open var scope: String {
        return oidAuthState.scope!
    }
    
    /// The raw id token (in JWT format). The payload data is automatically parsed to the profile property.
    open var idToken: String {
        return oidAuthState.lastTokenResponse!.idToken!
    }
    
    /// The payload part of the JWT token in a more convenient format.
    open var idTokenPayload: IDTokenPayload? {
        if let decodedJson = decodeJWTToken(token: idToken) {
            return Mapper<IDTokenPayload>().map(JSONString: decodedJson)
        }
        
        return nil
    }
    
    /// The underlying AppAuthSDK auth state.
    open var oidAuthState: OIDAuthState
    
    /// Constructor. OIDAuthState is the minimum requirement.
    init(authState: OIDAuthState) {
        self.oidAuthState = authState
    }
    
    /// Validates the session object.
    ///
    /// - Parameter result: The result callback. The Bool parameter indicates whether or not the VITSession did validate.
    ///
    func validate(result: (Bool) -> Void) {
        validateAuthState(authState: oidAuthState, completion: result)
    }
    
    /// Framework-scoped setter for the online status.
    func setOnline(_ online: Bool) {
        self.isOnline = online
    }
    
}

/// A model that holds the profile payload data parsed from the JWT payload of the id token.
@objc public class IDTokenPayload: NSObject, Mappable {
    
    /// The raw name string.
    open var name: String?
    
    /// The family ("last") name.
    open var familyName: String?
    
    /// The fiven ("first") name.
    open var givenName: String?
    
    /// The raw unix timestamp of the token issue time. See issuedAtTime for a Date version.
    open var iatRaw: Int!
    
    /// The raw unix timestamp of the session expire time. See expirationTime for a Date version.
    open var expRaw: Int!
    
    /// The raw unix timestamp of the time of authentication.
    open var authTimeRaw: Int!
    
    /// The time of authentication.
    public var authTime: Date {
        return Date(timeIntervalSince1970: Double(authTimeRaw))
    }
    
    /// The token issue time.
    public var issuedAtTime: Date {
        return Date(timeIntervalSince1970: Double(iatRaw))
    }
    
    /// The session expiration time.
    public var expirationTime: Date {
        return Date(timeIntervalSince1970: Double(expRaw))
    }
    
    /// Client identificator.
    open var inum: String?
    
    /// The issuer URL.
    open var iss: String!
    
    /// Audience. This will be the client id string.
    open var aud: String!
    
    /// The access token hash. Can be used to validate the access token.
    open var atHash: String!
    
    /// "Authentication Context Class Reference", the authentication context used to initiate the session.
    open var acr: String?
    
    /// OpenID connect version of the OX auth.
    open var oxOpenIDConnectVersion: String!
    
    /// The validation URI of OX auth.
    open var oxValidationURI: String!
    
    /// Convenience accessor for the person resource id. This is the same as the sub claim.
    open var personResourceId: String? {
        return sub
    }
    
    /// The subject of the authentication. The contained string is the person resource id.
    open var sub: String!
    
    /// Internal - used for JSON mapping.
    public required init?(map: Map) {
        
    }
    
    /// Internal - used for JSON mapping.
    public func mapping(map: Map) {
        
        name <- map["name"]
        familyName <- map["family_name"]
        givenName <- map["given_name"]
        
        iatRaw <- map["iat"]
        expRaw <- map["exp"]
        authTimeRaw <- map["auth_time"]
        
        inum <- map["inum"]
        iss <- map["iss"]
        aud <- map["aud"]
        atHash <- map["at_hash"]
        acr <- map["acr"]
        
        oxOpenIDConnectVersion <- map["oxOpenIDConnectVersion"]
        oxValidationURI <- map["oxValidationURI"]
        sub <- map["sub"]
    }
    
}

/// JWT token decoding function. Will parse a JSON string out of the base64 encoded token.
fileprivate func decodeJWTToken(token: String) -> String? {
    let components = token.components(separatedBy: ".")
    
    if components.count > 1 {
        var payloadBase64Str = components[1]
        
        if payloadBase64Str.characters.count % 4 != 0 {
            // Add padding if token is not a valid Base64 string.
            let padlen = 4 - payloadBase64Str.characters.count % 4
            payloadBase64Str += String(repeating: "=", count: padlen)
        }
        
        if let data = Data(base64Encoded: payloadBase64Str, options: []) {
            if let str = String(data: data, encoding: String.Encoding.utf8) {
                return str
            }
        }
    }
    
    return nil
}

/// The auth state validator. Will check that all parameters are valid.
/// TODO: Currently incomplete, the JWKS keys are not validated.
fileprivate func validateAuthState(authState: OIDAuthState, completion: (Bool) -> Void) {
    guard let idToken = authState.lastTokenResponse?.idToken else {
        completion(false)
        return
    }
    
    guard let tokenJson = decodeJWTToken(token: idToken) else {
        completion(false)
        return
    }
    
    guard let tokenPayload = Mapper<IDTokenPayload>().map(JSONString: tokenJson) else {
        completion(false)
        return
    }
    
    let clockSkewToleranceSeconds = VITMobileSSO.clockSkewTolerance
    
    if (!VITMobileSSO.issuerUrl.absoluteString.hasPrefix(tokenPayload.iss) ||   // Wrong issuer
        tokenPayload.aud != VITMobileSSO.clientId ||                   // Wrong client id
        tokenPayload.expirationTime.timeIntervalSince(Date()) < -clockSkewToleranceSeconds || // Expiration time in the past
        tokenPayload.issuedAtTime.timeIntervalSince(Date()) > clockSkewToleranceSeconds) {     // Issue time in the future
        
        completion(false)
        return
    }
    
    // TODO: Validate JWKS keys
    
    completion(true)
}
