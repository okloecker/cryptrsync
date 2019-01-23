# cryptrsync
Encrypted directory synchronization scripts for gocryptfs, rsync and rclone.

Tested on Linux but should work wherever bash, gocryptfs/cppcryptfs, rsync and/or rclone are available.

dependencies
---
- bash
- gocryptfs
- rsync or rclone
- notify-send

gnome-keyring
---
Instead of reading passwords from command line every time, cryptrsync.sh can
read passwords from gnome-keyring through "secret-tool".

First they have to be stored.
When running the following commands, secret-tool will prompt for password.
Enter command and arguments as-is because the script will lookup by the
attributes and values.

For gocryptfs

    $ secret-tool store --label=Cryptrsync gocryptfs password

For rclone:

    $ secret-tool store --label=Cryptrsync rclone config 

To verify the passwords, they will be printed in plain with these commands:

    $ secret-tool lookup gocryptfs password

    $ secret-tool lookup rclone config
