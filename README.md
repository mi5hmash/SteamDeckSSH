[![License: MIT](https://img.shields.io/badge/License-MIT-blueviolet.svg)](https://opensource.org/licenses/MIT)
[![Release Version](https://img.shields.io/github/v/tag/mi5hmash/SteamDeckSSH?label=Tool%20Version)](https://github.com/mi5hmash/SteamDeckSSH/releases/latest)
[![Visual Studio Code](https://custom-icon-badges.demolab.com/badge/Visual%20Studio%20Code-27313C.svg?logo=visual-studio-code)](https://code.visualstudio.com/)

> [!IMPORTANT]
> **Scripts from this repo are free and open source. If someone asks you to pay for them, it's likely a scam.**

# :interrobang: SteamDeckSSH - What is it?
<p float="left">
  <img src="https://github.com/mi5hmash/SteamDeckSSH/blob/main/.resources/images/cover.png" alt="cover" width="460" />
  <img src="https://github.com/mi5hmash/SteamDeckSSH/blob/main/.resources/images/iconart.png" alt="icon" width="256" />
</p>

It's a shell script for lazy people like me who want to use SSH on their decks, but don't want to type many commands into a command line. If you're one of us, worry no more as I got you covered.

**Despite that it's simple, you're still <mark>using it at your own risk</mark>. I've tried my best to make it foolproof and I always run tests before release until I consider my tool stable, but some things may show up only after a long time of use. You've been warned.**
# :tipping_hand_person: How does it work?
First, the script tries to obtain the root rights. If you've already set your custom password, the script will ask you to type it. The password will be stored as an encrypted variable for the time of running the script or it will be saved in an encrypted file. 

By default, remembering the user's custom password is disabled. You can change it by setting the **"REMEMBER_PASSWORD"** flag to **"1"** in the ***"settings.json"*** file. After the change, the script will remember the next entered password and save it in the encrypted ***".user.sec"*** file.

If you don't have a password set then the script will set the default password, which is **"GabeNewell#1"**. 

Unless you're using your password, it will be removed as soon as it's no longer needed and it depends on the scenario you pick. When you are using password authentication the password is needed for as long as the SSH server is enabled. In the case of key authentication, the password is needed only to enable or disable the server, but not between those steps. 

No matter which scenario you choose, the current SSH config will be backed up and then the script will insert a temporary configuration prepared by me.

When the service is enabled, you will see a window with a local IP address of your SteamDeck and Port. You can use it in Terminal, WinSCP, or any other client to make a connection.

<img src="https://github.com/mi5hmash/SteamDeckSSH/blob/main/.resources/images/ssh_enabled.png" alt="ssh_enabled" width="350" />

After you're done using the server, you can disable the SSH service. The backed-up SSH config will get restored and the script will clean up after itself.

In short, that's all. It's as simple as that.

If you do not want to use the key authentication or know more details then skip the next chapter.

# 🏋 Advanced stuff

### SSH configurations
In your local home network, where you trust everyone, the password authentication should be safe enough, but if you're planning to enable the SSH service while being connected to the public network then it's risky. The key authentication is more secure. 

I did some research and prepared two configurations that I consider reasonable:  
  
| sshd_config-pa (Password Authentication)    |
|---------------------------------------------|
| **AllowUsers** deck                         |
| **Banner** /etc/ssh/warning.net             |
| **ClientAliveInterval** 120                 |
| **ClientAliveCountMax** 0                   |
| **PermitEmptyPasswords** no                 |
| **PermitRootLogin** no                      |
| **Port** 2122                               |
| **PrintMotd** yes                           |
| **Protocol** 2                              |
| **AuthorizedKeysFile** .ssh/authorized_keys |
| **KbdInteractiveAuthentication** no         |
| **Subsystem** sftp /usr/lib/ssh/sftp-server |
| **UsePAM** yes                              |

| sshd_config-ka (Key Authentication)             |
|-------------------------------------------------|
| **AllowUsers** deck                             |
| **AuthorizedKeysFile** /etc/ssh/authorized_keys |
| **Banner** /etc/ssh/warning.net                 |
| **ChallengeResponseAuthentication** no          |
| **ClientAliveInterval** 120                     |
| **ClientAliveCountMax** 0                       |
| **PasswordAuthentication** no                   |
| **PermitEmptyPasswords** no                     |
| **PermitRootLogin** no                          |
| **Port** 2122                                   |
| **PrintMotd** yes                               |
| **Protocol** 2                                  |
| **UsePAM** no                                   |
| **KbdInteractiveAuthentication** no             |
| **Subsystem** sftp /usr/lib/ssh/sftp-server     |

Notice that I've changed the default port from '22' to '2122', but you can pick any other unoccupied number to make it even less obvious.

### Setting up a key authentication

To use the key authentication, change the value of **"KEY_AUTH"** flag to **"1"** in the ***"settings.json"*** file.

Next, you need to generate SSH keys on the client device from which you want to access the SSH server on SteamDeck.

I use the following console command:  
```markdown
ssh-keygen -t rsa -b 4096
```

The above line will generate two keys: private (**id_rsa**) and public (**id_rsa.pub**). You shouldn't make copies of your private key. You should store it on the client device that generated it.
The public key is more of a lock than a key. You can safely publish it or get it compromised. It can be opened with your private key but not the other way.

During the process, it will ask you where to save the keys and if you would like to add a passphrase. The passphrase is optional protection. Think of it as your fingerprint that activates the key. Without it, the key is useless to the thief who stole the key from you. Decide if you need additional protection or not.

A final step is to copy the content of ***id_rsa.pub*** inside ***./data/authorized_keys*** on your SteamDeck.

> [!TIP]
> You can add more than one key. Just paste every next key in the new line.

Now, when you enable the SSH service on your SteamDeck, you'll be able to access it only from the device that has a matching private key.

### Preventing connection loss

While working on the battery, the device will suspend ongoing tasks after some time on idle. I know of two ways to prevent KDE Plasma from putting your device to sleep. The first one is to run the script from another script with the ***systemd-inhibit*** command. This will register a new lock for the time that the script is running. You can examine the implementation of this method in the ***"_Caffeine Launcher.sh"*** file. The downside of this method is that the device screen stays on all the time, so I went another way. I've modified power management settings in the ***"/home/deck/.config/powermanagementprofilesrc"*** file. 

By default, the script backups current power management settings and overwrites the original with the modified one. Then it refreshes the **org.kde.Solid.PowerManagement** config status. In this state, the device will first dim the screen and then turn it off, but won't suspend anything. This is pretty cool, right? After you choose to disable SSH it will restore the previous settings.

If you don't want this feature then you can disable it by changing the value of **"DISABLE_SUSPENSION"** flag to **"0"** in the ***"settings.json"*** file.

# 🧑‍🔧 Installing the script
There are two ways to install this tool: Automatic or Manual [PRO].

### A) Automatic installation
The automatic installation script will download and install the latest version of this tool in the ***'DOCUMENTS'*** directory and create a shortcut on ***'DESKTOP'***.

To install this way, open a new Konsole window and paste one of the following lines of code depending on what you want to do:
#### Install
```bash
curl -sSL https://raw.githubusercontent.com/mi5hmash/SteamDeckSSH/main/_Installer.sh | bash
```

#### Uninstall
```bash
curl -sSL https://raw.githubusercontent.com/mi5hmash/SteamDeckSSH/main/_Installer.sh | bash -s -- -u
```
### B) Manual installation
Grab the [latest release](https://github.com/mi5hmash/SteamDeckSSH/releases/latest) and unpack it on your Steam Deck.
Then right-click on the ***'_Create a Shortcut on Desktop.sh'*** and select *"Properties"*. Navigate to the "Permissions" tab and make sure that an "Is executable" checkbox is ticked.

<img src="https://github.com/mi5hmash/SteamDeckSSH/blob/main/.resources/images/permissions.png" alt="permissions" width="415"/>

Then click **OK** and once again right-click on the ***'_Create a Shortcut on Desktop'***, but this time select *"Run in Konsole"*.
You can also click twice and execute that script. 

<img src="https://github.com/mi5hmash/SteamDeckSSH/blob/main/.resources/images/run.png" alt="run" width="415"/>

A desktop shortcut will be created.

<img src="https://github.com/mi5hmash/SteamDeckSSH/blob/main/.resources/images/desktop_icon.png" alt="desktop_icon" width="280"/>

# :runner: Running the script
Regardless of which installation method you choose, you should end up with a shortcut on your desktop. Run the script with it.

**Do not attempt to execute 'SteamDeckSSH.sh' by clicking twice on it, because this will run the script in a hidden window.**

**Do not click on 'Add to Steam' and try to execute 'SteamDeckSSH.sh' from the Gaming Mode. It's meant to be run from the desktop.**

# :fire: Issues
All the problems I've encountered during my tests have been fixed on the go. If you find any other issue (hope you won't) then please, feel free to report it [there](https://github.com/mi5hmash/SteamDeckSSH/issues).
