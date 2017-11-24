//
//  VITMobileSSOLogging.swift
//  VITMobileSSOFramework
//
//  Created by Antti Laitinen on 22/02/2017.
//  Copyright © 2017 VaultIT. All rights reserved.
//

import Foundation

/// Log an info level message.
func logi(_ message: Any, file: String = #file, function: String = #function) {
    if VITMobileSSO.loggingLevel.rawValue <= VITMobileSSOLoggingLevel.info.rawValue {
        doLog(message: message, file: file, function: function)
    }
}

/// Log a warning level message.
func logw(_ message: Any, file: String = #file, function: String = #function) {
    if VITMobileSSO.loggingLevel.rawValue <= VITMobileSSOLoggingLevel.warning.rawValue {
        doLog(message: message, file: file, function: function)
    }
}

/// Log a error level message.
func loge(_ message: Any, file: String = #file, function: String = #function) {
    if VITMobileSSO.loggingLevel.rawValue <= VITMobileSSOLoggingLevel.error.rawValue {
        doLog(message: message, file: file, function: function)
    }
}

/// The actual logging code.
fileprivate func doLog(message: Any, file: String, function: String) {
    var intro: String = ""
    
    if VITMobileSSO.logFilename {
        if let filename = URL(string: file)?.lastPathComponent {
            intro += filename + ":"
        }
    }
    if VITMobileSSO.logFunctionName {
        if VITMobileSSO.logFilename {
            intro += "::"
        }
        
        intro += function + ":"
    }
    
    print(intro, message)
}
