//
//  RequestReplyChannel.swift
//  NotchDrop
//
//  Renvoie la réponse de l'utilisateur (« allow », « deny » ou des numéros d'étapes) au script qui attend, par un tube nommé privé :
//  le script le crée dans le dossier réservé à l'utilisateur, l'app y écrit une ligne.
//

import Foundation

enum RequestReplyChannel {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Encoche/replies")
    }

    /// Vrai si la réponse a été remise. Faux si le script n'attend plus (délai passé, session fermée),
    /// si l'identifiant n'est pas valide ou si le fichier n'est pas un tube à nous : rien n'est alors écrit.
    static func send(_ reply: RequestReply, replyID: String, in directory: URL = defaultDirectory) -> Bool {
        guard isValidReplyID(replyID) else { return false }
        let path = directory.appendingPathComponent(replyID).path

        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFIFO, info.st_uid == getuid() else { return false }

        // Sans lecteur, l'ouverture échoue tout de suite au lieu d'attendre.
        let descriptor = open(path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        let line = Array((reply.line + "\n").utf8)
        return write(descriptor, line, line.count) == line.count
    }
}
