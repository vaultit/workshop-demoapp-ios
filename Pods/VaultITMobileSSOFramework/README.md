# VaultITMobileSSOFramework

## Table of contents

1. [Configuration](#configuration)
    * [Requirements](#requirements)
    * [Download and install](#download-and-install)
    * [Add client secret in the build script](#add-client-secret-in-the-build-script)
    * [Required config to Info.plist](#required-config-to-info-plist)
    * [Enable Keychain sharing (optional)](#enable-keychain-sharing-optional)
    * [Modify your AppDelegate](#modify-your-appdelegate)
2. [Basic framework usage](#basic-framework-usage)
    * [Application startup](#application-startup)
    * [Check if a valid session already exists](#check-if-a-valid-session-already-exists)
    * [Additional session check with Safari](#additional-session-check-with-safari)
    * [Starting a login procedure](#starting-a-login-procedure)
    * [Step-up authentication](#step-up-authentication)
    * [Logging out](#logging-out)
    * [Always accessing fresh session tokens](#always-accessing-fresh-session-tokens)
    * [Manually refreshing the session](#manually-refreshing-the-session)
3. [VITSession data](#session-data)
    * [ID token payload](#id-token-payload)

## Configuration

### Requirements

This version of the VaultITMobileSSO SDK requires you to build the project with *Xcode 9*, which supports iOS 11 and Swift 4.

### Download and install

#### Add to a new project or to a project not using CocoaPods

The framework is distributed via CocoaPods. If your project does not already use CocoaPods for dependency management
(most projects do), install it with RubyGems:

```bash
sudo gem install cocoapods
```

Then in your project's root folder run:

```bash
pod init
```

Modify the newly created Podfile by adding the private Pod source to it. Put these two lines at the top of your Podfile:  

```ruby
source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/vaultit/mobilesso-ios-podspec.git'
```

and by adding the following line inside your app target in the Podfile:

```ruby
target 'YourApp' do
    pod 'VaultITMobileSSOFramework', '~> 0.4.7'
    # Your other pods here
end
```

If you want to support older iOS versions, uncomment the generated line:

```ruby
platform :ios, '9.0'
```

Since using iOS 11 for the app target will drop 32-bit build support, defining a lower version is required to build the project for e.g. iPhone 5. The minimum supported version for the framework is 9.0.

Finally, run:

```bash
pod update
```

This will download all dependencies and create a workspace file called "YourProject.xcworkspace", which ties all the
dependencies together. Open it up and build your project.

#### Add to a project already using CocoaPods

First add these two lines to the top of your Podfile (the first one is the default Pod repository, but it must be listed if there is more than one):

```ruby
source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/vaultit/mobilesso-ios-podspec.git'
```

Then simply add the line

```ruby
pod 'VaultITMobileSSOFramework', '~> 0.4.7'
```

to your Podfile inside your app target. Then run `pod update`. If your Pod repositories are up-to-date, a simple `pod install` might be enough instead.

### Add client secret in the build script

To avoid saving sensitive keys to a git repository, you should create a file (named e.g. ClientSecret.env) file in the
root folder of the application and add the following "Run script" phase to your project:

```bash
INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
CLIENT_SECRET=`cat ${SCRIPT_INPUT_FILE_0}`
/usr/libexec/Plistbuddy -c "Set :MobileSSOClientSecret ${CLIENT_SECRET}" $INFO_PLIST
```

Also, add the file with the key as an input file to the script.

### Required config to Info.plist

| Key                          	| Description                                                                                                                                                                                                                                                                                                                                                                                                                    	| Example value                                                          	|
|------------------------------	|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------	|------------------------------------------------------------------------	|
| MobileSSOClientId            	| The client id string.                                                                                                                                                                                                                                                                                                                                                                                                          	|                                                                        	|
| MobileSSOIssuerURL           	| The URL of the GLUU authentication server.                                                                                                                                                                                                                                                                                                                                                                                     	|                                                                        	|
| CFBundleURLTypes                     | This describes the custom URL schemes used by your app (should match the login and logout redirect URLs). | URL Types: An array with one value: CFBundleURLSchemes (type array). CFBundleURLSchemes is again an array with the schemes (string type). Just put ${PRODUCT_BUNDLE_IDENTIFIER} here so it auto-resolves to match your app. |
| MobileSSOLoginRedirectURI    	| A custom-schemed login redirect URI that will be captured  by your app and handled by VaultITMobileSSOFramework.  This is the URL the system Safari browser will redirect when login is successful  and it will be used to capture the event and dismiss the browser. Easiest way is to prefix all the URLs with ${PRODUCT_BUNDLE_IDENTIFIER} so they auto-resolve to match your app. 	| ${PRODUCT_BUNDLE_IDENTIFIER}://oidc_login                                     	|
| MobileSSOLogoutRedirectURI   	| A custom-schemed redirect URI that will be captured by your app and  handled by VaultITMobileSSOFramework.This is the URL the system Safari  browser will redirect when logout is successful and it will be used to capture the  event and dismiss the browser. Easiest way is to prefix all the URLs with ${PRODUCT_BUNDLE_IDENTIFIER} so they auto-resolve to match your app.  	| ${PRODUCT_BUNDLE_IDENTIFIER}://oidc_logout                                    	|
| MobileSSOBankIdResumeURI | If you use bankid you must set this redirect URI as well. Logging in with BankID from the same device requires an intermediate redirect from the BankID app back to your application. The VaultITMobileSSOFramework will handle all this automatically as long as this parameter is supplied. The scheme must match your app's bundle id so just use ${PRODUCT_BUNDLE_IDENTIFIER}. | ${PRODUCT_BUNDLE_IDENTIFIER}://bankid_continue |
| MobileSSOKeychainServiceName 	| You can leave this out (do not include in Info.plist) if you don't need keychain sharing. If you want to use keychain sharing however, this value needs to be same across all your apps sharing data. | "a_common_name_for_all_apps"                                                                                                       	|                                	|
| MobileSSOKeychainAccessGroup 	| You can leave this out if you don't need keychain sharing. Sessions stored in the keychain can be shared with other apps in the same keychain access group. Go to the "Capabilities" tab of your project settings, enable keychain sharing and enter an access group name that is shared between all your apps. Then set this property as:$(AppIdentifierPrefix)group_namewhere "group_name" is the access group name you chose. The $(AppIdentifierPrefix) will resolve to your team id. 	| $(AppIdentifierPrefix)example_group_name                                                                       	|
| MobileSSOClientSecret        	| This should be left empty in the Info.plist file. It will be added in the build phase.                                                                                                                                                                                                                                                                                                                                         	|                                                                        	|

For a better example of a Info.plist file, see the demo app project.

### Enable Keychain sharing (optional)

If you want to share keychain data (in this case, sessions) between apps you should also enable Keychain sharing for your app. This is easiest done by going to the *"Capabilities"* tab of your app project, and then enabling Keychain sharing. Set the access group to the same name as the *MobileSSOKeychainAccessGroup* parameter in your Info.plist.

### Modify your AppDelegate

To make single sign-on flow work, you must make some changes to your AppDelegate.
First, make your *AppDelegate* implement the [VITMobileSSOAppDelegate](Protocols/VITMobileSSOAppDelegate.html) protocol. FIrst import the VaultITMobileSSOFramework and AppAuth libraries

```swift
import VaultITMobileSSOFramework
import AppAuth
```

Then make your AppDelegate conform to the VITMobileSSOAppDelegate protocol, and add the following property:

```swift
var currentAuthFlow: OIDAuthorizationFlowSession?
```

Additionally, you will need to implement the login and logout redirect URL handling. Add the following method to your AppDelegate:

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
    // Sends the URL to the current authorization flow (if any) which will process it if it relates to
    // an authorization response.
    if currentAuthFlow?.resumeAuthorizationFlow(with: url) ?? false {
        currentAuthFlow = nil
        return true
    }

    // Your additional URL handling (if any) goes here.

    return false
}
```

## Basic framework usage

*NOTE: Code examples are in Swift (syntax compatible with Swift 3 and 4). The library also fully supports Objective-C for legacy projects. XCode is able to translate the API method declarations to Objective-C if the host project uses it.*

### Application startup

During application startup (preferably in didFinishLaunchingWithOptions) you should call [VITMobileSSO.initialize()](Classes/VITMobileSSO.html):

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    // Initialize the VITMobileSSOFramework
    VITMobileSSO.initialize()

    // Your other initialize code

    return true
}
```

### Application resume

When the app comes to foreground the framework will want to check for the session validity and update its state. Add [VITMobileSSO.willEnterForeground](Classes/VITMobileSSO.html) to the applicationWillEnterForeground method:

```swift
func applicationWillEnterForeground(_ application: UIApplication) {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    VITMobileSSO.willEnterForeground()
}
```

### Check if a valid session already exists

The main class for handling sessions is the [VITSessionManager](Classes/VITSessionManager.html).
It is recommended that you implement a [VITSessionManagerDelegate](Protocols/VITSessionManagerDelegate.html) and set it to the [VITSessionManager](Classes/VITSessionManager.html) to stay updated of the
session status. The protocol is:

```swift
/// Implement this protocol to get notified of changes to the session.
public protocol VITSessionManagerDelegate: class {

    /// Will be called when the session state has been resolved. You should wait for this event before
    /// presenting the login screen to an user to see if a valid session already exists.
    ///
    /// - Parameter session: Will hold a valid session if one was resumed. If nil, then no session exists
    ///                      and you must present a login screen to the user with the *presentLogin* method.
    func initialized(session: VITSession?)

    /// User has completed the login flow succesfully and is now logged in.
    ///
    /// - Parameter session: The session that started with the login.
    func didCompleteLogin(session: VITSession)

    /// A session was refreshed with a refresh token.
    ///
    /// - Parameter session: The new refreshed session.
    func didRefreshSession(session: VITSession)

    /// User has completed the logout process succesfully. Any session data will be invalid.
    func didLogout()
}
```

You should wait for the *initialized* callback before initiating a manual login procedure. If a valid session exists (the user has logged in either previously with this app or any other app in the same authorisation group), it will be passed as the *"session"* parameter. If no valid session exists or if one could not be refreshed, the *"session"* parameter will be nil.

### Additional session check with Safari

Even if a session is not stored in the keychain of your app or any other app that shares the same keychain, you can still use SSO based on valid system browser cookies. This requires the Safari to appear, and it cannot be obstructed or hidden in any way as that will get your app rejected from the App Store. For this reason this is not done automatically at SDK initialization, but rather left at your discretion when to perform this action. To do this, call the [VITSessionManager.shared.presentSessionCheck](Classes/VITSessionManager.html) method. The simplest (while not necessarily the best) way to do this is 

```swift
func initialized(session: VITSession?) {
    if session == nil {
        // Choose to check if Safari holds a session.
        VITSessionManager.shared.presentSessionCheck(in: self) { safariSession in
            if safariSession != nil {
                // There was a session in Safari, yea!
            }
        }
    }
    else {
        // the normal keychain-based session initialization
    }
}
```

The above code uses the default UI for coordinating the session check, and there are 3 localizable strings that you can set to your liking, e.g. to:

```swift
// Displayed before the session-checking Safari will pop into view. 
vaultITMobileSSODefaultLoginExpiredMessage = "Logging in...";

// Displayed if the Safari check did not yield a session.
vaultITMobileSSODefaultSessionCheckFailedMessage = "Could not log in.";

// Displayed if a session was found with Safari.
vaultITMobileSSODefaultSessionCheckSuccessMessage = "Logged in!";
```

If you would like to customize how this UI operation is handled, you can implement your own [VITSessionCheckUICoordinator](Protocols/VITSessionCheckUICoordinator.html) to do this. The protocol is:

```swift
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
    
    /// The UIViewController instance that should present the required SFSafariViewController (iOS 9 & 10) / SFAuthenticationSession (iOS 11).
    var safariPresentingViewController: UIViewController { get }
}
```

### Starting a login procedure

If the session did not already exist, you make the user log in by calling the [VITSessionManager.shared.presentLogin](Classes/VITSessionManager.html) method. You must pass a presenting ViewController and optionally pass a number of OpenID scopes depending on your needs. The *openid* and *profile* scopes are automatically included. Below is an example of a simple login call without any additional scopes:

```swift
VITSessionManager.shared.presentLogin(in: self) { session, error in
    // If successful, session will be non-nil.
    // If an error occurred, session will be nil and the error will be non-nil describing the error.
}
```

For a more fine-grained control, a number of optional parameters can be supplied:

```swift
let extraScopes = ["my_custom_backend_scope1", "my_custom_backend_scope2"]

VITSessionManager.shared.presentLogin(in: self, extraScopes: extraScopes, stateCompletion: { state in
        /// This optional callback can be used to stay up-to-date with what is happening with the login process.
        /// The login requires heavy network and UI involvement from the SDK, so using this might be necessary to properly 
        /// handle everything in your app.
        switch state {
        case .configurationLoaded:
            print("State complete: Discovery config loaded")
        case .safariWillAppear:
            print("State complete: Safari will appear")
        case .safariDidDisappear:
            print("State complete: Safari did disappear")
        case .tokenExchangeCompleted:
            print("State complete: Tokens exchanged")
        case .idTokenWillValidate:
            print("State complete: ID token will validate")
        }
    },
    completion: { session, error in
        if error != nil {
            print(error!)
        }
        else {
            print("Login succesful!")
        }
    }
)
```

The *presentLogin* method will open up a browser and present the login screen to the user. After a successful login, the [VITSessionManagerDelegate](Classes/VITSessionManagerDelegate.html) method *didCompleteLogin* will be called with the fresh session.

### Step-up authentication

If you want to support multi-level authentication with different access level with different *acr_values*, it is possible with the *presentLogin* method of [VITSessionManager](Classes/VITSessionManager.html). If the *presentLogin* is called again with different *acr_values*, the login is presented again and the 
session will be re-established with the new login method.

### Logging out

Logging out is done with the *VITSessionManager.shared.logout* method of the shared [VITSessionManager](Classes/VITSessionManager.html). You must supply a presenting ViewController as a parameter. There is also an optional completion listener. Note that calling the logout method will flash the browser on the screen, which may be distracting to the user.

### Always accessing fresh session tokens

When you log in, you probably want to make authenticated calls afterwards. For this purpose you should always use the
[VITSessionManager.shared.getFreshSession()] method. This ensures that for each call the access token will be auto-refreshed
if needed. Also, in case of lost session the [VITSessionManagerDelegate](Protocols/VITSessionManagerDelegate.html) gets called and the app can respond appropriately.

### Manually refreshing the session

The VITMobileSSO framework will keep the session refreshed when necessary, but you can also automatically request a token refresh by simply calling the [VITSessionManager.shared.refreshSession](Classes/VITSessionManager.html).

## VITSession data

### ID token payload

Session data is stored within a [VITSession](Classes/VITSession.html) object. The object, in addition to raw token and
expiration information, will parse the ID token (JWT token) into an easy to access [IDTokenPayload](Classes/IDTokenPayload.html) object.

NOTE #1: VITSession objects will get invalid after time, so you should not hold references to them after accessing the data.
Instead, you are best of by simply calling either [VITSessionManager.shared.getFreshSession()](Classes/VITSessionManager.html) or
[VITSessionManager.shared.currentSession](Classes/VITSessionManager.html) depending on your needs. You should always prefer the *getFreshSession* approach if you plan on using the access token.



