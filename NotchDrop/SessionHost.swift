//
//  SessionHost.swift
//  NotchDrop
//
//  Retrouve l'application (terminal, fenêtre) qui héberge un processus Claude Code,
//  en remontant la chaîne des parents. Limite connue : on active l'application, pas l'onglet.
//

import AppKit

enum SessionHost {
    /// Borne contre une chaîne anormalement longue ou cyclique.
    private static let maxAncestors = 16

    static func owningApplication(ofProcess pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0 ..< maxAncestors {
            if let application = NSRunningApplication(processIdentifier: current),
               application.activationPolicy == .regular
            {
                return application
            }
            guard let parent = parentProcess(of: current) else { return nil }
            current = parent
        }
        return nil
    }

    static func parentProcess(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&request, UInt32(request.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }
}
