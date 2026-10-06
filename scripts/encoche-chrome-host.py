#!/usr/bin/python3
"""Hôte de messagerie native de l'extension Chrome d'Encoche.

Chrome le lance et lui parle sur son entrée et sa sortie (un entier de 4 octets, puis du JSON).
Il ne fait que relayer, sans rien interpréter, vers l'app Encoche par un socket Unix privé :
une ligne JSON par message. Si l'app est fermée, il garde la main, jette les messages et réessaie
toutes les 3 secondes. Il s'arrête quand Chrome ferme son entrée. Bibliothèque standard seulement.
"""

import os
import select
import socket
import struct
import sys
import time

SOCKET_PATH = os.path.join(os.path.expanduser("~"), "Library/Application Support/Encoche/browser.sock")
MAX_MESSAGE_BYTES = 64 * 1024
RETRY_SECONDS = 3


def connect():
    try:
        link = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        link.connect(SOCKET_PATH)
        return link
    except OSError:
        return None


def split_frames(buffer):
    """Les messages complets du tampon (4 octets de longueur, puis le JSON), et ce qui reste."""
    messages = []
    while len(buffer) >= 4:
        (size,) = struct.unpack("<I", buffer[:4])
        if size > MAX_MESSAGE_BYTES:
            raise ValueError("message trop grand")
        if len(buffer) < 4 + size:
            break
        messages.append(buffer[4 : 4 + size])
        buffer = buffer[4 + size :]
    return buffer, messages


def main():
    stdin_fd = sys.stdin.fileno()
    stdout = sys.stdout.buffer
    link = None
    last_attempt = 0.0
    from_chrome = b""
    from_app = b""

    while True:
        if link is None and time.time() - last_attempt >= RETRY_SECONDS:
            link = connect()
            last_attempt = time.time()

        watched = [stdin_fd] + ([link] if link else [])
        ready, _, _ = select.select(watched, [], [], 1.0)

        for source in ready:
            if source == stdin_fd:
                chunk = os.read(stdin_fd, 65536)
                if not chunk:
                    return
                from_chrome += chunk
                try:
                    from_chrome, messages = split_frames(from_chrome)
                except ValueError:
                    return
                for message in messages:
                    if link is None:
                        continue
                    try:
                        link.sendall(message.replace(b"\n", b" ") + b"\n")
                    except OSError:
                        link.close()
                        link = None
            else:
                try:
                    chunk = link.recv(65536)
                except OSError:
                    chunk = b""
                if not chunk:
                    link.close()
                    link = None
                    from_app = b""
                    continue
                from_app += chunk
                *lines, from_app = from_app.split(b"\n")
                if len(from_app) > MAX_MESSAGE_BYTES:
                    from_app = b""
                for line in lines:
                    if line and len(line) <= MAX_MESSAGE_BYTES:
                        stdout.write(struct.pack("<I", len(line)) + line)
                        stdout.flush()


if __name__ == "__main__":
    main()
