//
//  AppleScriptRunner.swift
//  NotchDrop
//
//  Lance un script AppleScript et rend sa réponse. À appeler depuis une file à part : un script peut durer.
//

import Foundation

enum AppleScriptRunner {
    /// Refus de macOS : l'utilisateur n'a pas autorisé le contrôle de cette application.
    static let notAuthorizedErrorNumber = -1743

    static func run(_ source: String) -> (descriptor: NSAppleEventDescriptor?, errorNumber: Int?) {
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (descriptor, error?[NSAppleScript.errorNumber] as? Int)
    }
}
