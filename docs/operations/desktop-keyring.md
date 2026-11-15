# Desktop keyring

The desktop uses GNOME Keyring for the Secret Service API, PKCS#11, and the
GCR SSH agent. It intentionally does not enable oo7: oo7 only replaces the
Secret Service part, while this desktop also relies on GNOME Keyring's GCR
integration. More importantly, both providers require a password supplied by
PAM to unlock an encrypted persistent keyring.

## Normal login

The graphical greeter requires the account password before starting Hyprland.
PAM passes that password to GNOME Keyring to unlock the encrypted Login keyring.
Hyprlock also uses the account password when unlocking an existing session.

Changing the account password with `passwd` also updates the Login keyring
through PAM. Do not change this account's password with a method that bypasses
PAM unless the Login keyring password is changed at the same time.

## Repairing the existing Login keyring

If the password Helium prompts for is rejected, the Login keyring was encrypted
with a different password. This can happen when the account password was
changed through a path that bypassed PAM. The encryption is intentional:
there is no safe way to recover its contents without the former keyring
password.

After deploying this configuration:

1. Close Helium and other applications that may write credentials.
2. Open **Passwords and Keys** (`seahorse`). If the previous keyring password

   is known, select **Login**, choose **Change Password**, and set it to the
   current account password. Reboot afterward so the new password is supplied
   to the keyring by the first graphical login.
3. If the former password is unknown, first save a private encrypted-data
  backup:

   ```sh
   install -d -m 700 "$HOME/keyring-backup"
   cp -a "$HOME/.local/share/keyrings/." "$HOME/keyring-backup/"
   ```

4. In Seahorse, delete the inaccessible Login keyring, then reboot. A new

   Login keyring will be created and matched to the current account password
   when Hyprlock first unlocks the headless session.

The last option permanently makes secrets encrypted with the old keyring
unavailable. In particular, browser passwords stored through that old keyring
may need to be re-entered or restored from a browser/password-manager backup.
