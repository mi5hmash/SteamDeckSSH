#!/bin/bash

### STYLES
echo_E() { zenity --error --width="${2:-100}" --text="$1" 2> /dev/null; }
echo_W() { zenity --warning --width="${2:-100}" --text="$1" 2> /dev/null; }
echo_I() { zenity --info --width="${2:-100}" --text="$1" 2> /dev/null; }


### FUNCTIONS

## Random password generator
# $1-Password length
_randomPasswordGen() { tr -dc 'A-Za-z0-9!"#%&$'\''()*+,-./:;<>=?@[]\^_`|{}~' </dev/urandom | head -c "${1:-16}"; echo; }

## Checks if user exists
# $1-Username
_userExists() { [ "$(id -u "$1" 2> /dev/null)" ]; }

## Checks if user has its password set
# $1-Username
_userHasPassword() { [ "$(passwd -S "$1" | cut -d " " -f 2)" = "P" ]; }

## Returns current user sudo status
_sudoStatus() {
local _t; _t=$(sudo -nv 2>&1)
if [ -z "$_t" ]; then
	echo 2 # has_sudo__pass_set
elif echo "$_t" | grep -q '^sudo:'; then
	echo 1 # has_sudo__needs_pass
else
	echo 0 # no_sudo
fi
}

## Returns current ssh state
_sshdState() {
local _t; _t=$(systemctl is-enabled sshd)
if [ "$_t" == "enabled" ]; then
	echo 2
elif [ "$_t" == "disabled" ]; then
	echo 1
else
	echo 0 # no_sshd_service_available
fi
}

## AES-256 (DE/EN)CRYPTION
# $1-Input string
# Reference: https://www.howtogeek.com/734838/how-to-use-encrypted-passwords-in-bash-scripts/
_encrypt() {
local _p; _p=${2:-$SESSION_GUID} # set default password
echo "$1" | openssl enc -aes-256-cbc -md sha512 -a -pbkdf2 -iter 100000 -salt -pass "pass:$_p"
}
_decrypt() {
local _p; _p=${2:-$SESSION_GUID} # set default password
echo "$1" | openssl enc -aes-256-cbc -md sha512 -a -d -pbkdf2 -iter 100000 -salt -pass "pass:$_p"
}

## Get password variable
_getPassword() { _decrypt "$passWord"; }
## Set password variable
_setPassword() { passWord=$(_encrypt "$1"); }

_readUserSec() { _decrypt "$(cat $UserSecPath)" "$SEC_KEY"; }
_writeUserSec() { _encrypt "$1" "$SEC_KEY" > $UserSecPath; }

## Validate Sudo Password and claim root rights
_validateSudoPassword() {
local _t; _t=$(echo "$1" | sudo -Svp '' 2>&1) # test
local _vo; _vo=${2:-0} # validate_only flag
if [ -z "$_t" ]; then
	echo 1 # sudo_pswd_valid
	[ "$_vo" = 1 ] && sudo -k # Invalidate user's cached credentials
fi
}

## Read password from user input if it does have one set
_readExistingUserPassword() {
local _p; _p=$(_getPassword)
local _f=0 # helps to omit the encryption on the first try (when the script tries out a default password)
while true; do
	# if given password is valid then encrypt it
	echo "Trying out the given password..."
	if [ "$(_validateSudoPassword "$_p")" = 1 ]; then
		[ $_f = 1 ] && _setPassword "$_p" && 
		[ "$REMEMBER_PASSWORD" = "1" ] && _writeUserSec "$_p"
		break
	fi
	_f=1
	# If user didn't got password set and now the default password isn't working it means that it has been changed and shouldn't be removed on finalization
	[ "$DEF_USR_HAS_PASSWD" = 0 ] && USR_CHANGED_PASSWD=1
	# Prompt user for a valid password
	echo_W "Invalid password!\nPlease, enter a correct sudo password in the next window." "270"
	_p="$(zenity --password 2> /dev/null)"
	local _err="$?"; [ "$_err" != 0 ] && exit
done
clear
}

## Set password for user account
# $1-Username; $2-Password
_setUserPassword() {
passwd "$1" << EOD &> /dev/null
$2
$2
EOD
}

## Try to set password for user account
# $1-Username; $2-Password
setUserPassword() {
local _userName; _userName=${1:-$userName}
local _passWord; _passWord=${2:-$(_getPassword)}
# Check if user exists
if ! _userExists "$_userName"; then
	echo_E "User '$_userName' does not exist!"
	return
fi
# Check if user already has its password set
if _userHasPassword "$_userName"; then
	echo_I "User '$_userName' already has its password set." "200"
else
	# Try to set user password
	_setUserPassword "$_userName" "$_passWord"
	# Check if password has been set
	if ! _userHasPassword "$_userName"; then
		echo_E "Password couldn't be set!"
		return
	fi
fi
}

## Remove password from user account
# $1-Username
_removeUserPassword() { sudo -S passwd -d "$1" &> /dev/null; }

## Remove password from the user account
# $1-Username
removeUserPassword() {
local _userName; _userName=${1:-$userName}
# Check if user exists
if ! _userExists "$_userName"; then
	echo_E "User '$_userName' does not exist!"
	return
fi
# Check if user already has its password set
if ! _userHasPassword "$_userName"; then
	echo_I "User '$_userName' does not have a password set."
else
	# Try to remove user password
	_removeUserPassword "$_userName"
	# Check if password has been removed
	if ! _userHasPassword "$_userName"; then
		sudo -k # Invalidate user's cached credentials
	else
		echo_E "Password couldn't be removed!"
		return
	fi
fi
}

## Check user's sudo rights and elevate it if possible
checkSudo() {
# Check if user is a sudoer
local _t; _t="$(_sudoStatus)"
if [ "$_t" = 1 ]; then
	# Check if user has its password set
	if _userHasPassword "$userName"; then
		_readExistingUserPassword
	else
		setUserPassword "$userName"
	fi
	_validateSudoPassword "$(_getPassword)" &> /dev/null
else
	sudo -v # Extend current sudo session
fi
}

## Removes user password if user didn't have one set on script launch
sudoTaskFinalize() {
[ "$DEF_USR_HAS_PASSWD" = 0 ] && [ "$USR_CHANGED_PASSWD" = 0 ] && removeUserPassword "$userName"
}

## Refreshes org.kde.Solid.PowerManagement config status
_refreshPlasmaConfigStatus() {
qdbus org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement.refreshStatus
}

_sshdQuestion() {
zenity --question \
--title="$TOOL_NAME $TOOL_VERSION" \
--width="300" \
--text="$1" 2> /dev/null

case $? in
	0) echo 1;;
	*) exit;;
esac
}

_sshdEnable() {
# Remember if user had password set 
[ "$FIRST_LAP" = 1 ] && echo "$DEF_USR_HAS_PASSWD" > "$PflPath"
# Ask user using zenity
_sshdQuestion "SSH Server Status: DISABLED\n\nWould you like to ENABLE it?" &> /dev/null
# Become sudo
checkSudo
# Make backup of files and overwrite original ones with the modified files
(sudo cp -f "$SshdConfigPath" "$BackupSshdConfigPath"
sudo cp -f "$PatchedSshdConfigPath" "$SshdConfigPath"
sudo cp -f "$MotdPath" "$BackupMotdPath"
sudo cp -f "$PatchedMotdPath" "$MotdPath"
sudo cp -f "$WarningNetPath" "$BackupWarningNetPath"
sudo cp -f "$PatchedWarningNetPath" "$WarningNetPath") &> /dev/null
[ "$KEY_AUTH" = 1 ] && (sudo cp -f "$AuthorizedKeysPath" "$BackupAuthorizedKeysPath"
sudo cp -f "$PatchedAuthorizedKeysPath" "$AuthorizedKeysPath") &> /dev/null
[ "$DISABLE_SUSPENSION" = 1 ] && (cp -f "$PowerManProfilePath" "$BackupPowerManProfilePath"
cp -f "$PatchedPowerManProfilePath" "$PowerManProfilePath"
_refreshPlasmaConfigStatus) &> /dev/null
# Enable the sshd service
sudo systemctl enable --now sshd
# Finalize
[ "$KEY_AUTH" = 1 ] && sudoTaskFinalize
}

_sshdDisable() {
local _ip; _ip="$(ip route get 1.2.3.4 | cut -d ' ' -f 7):$(grep ^Port $SshdConfigPath | cut -d ' ' -f 2)"
_sshdQuestion "SSH Server Status: ENABLED\nServer is running at: $_ip\n\nWould you like to DISABLE it?" &> /dev/null
# Become sudo
checkSudo
# Disable the sshd service
sudo systemctl disable --now sshd
# Restore backups of the original files
(rm -f "$SshdConfigPath"
sudo mv -f "$BackupSshdConfigPath" "$SshdConfigPath"
rm -f "$MotdPath"
sudo mv -f "$BackupMotdPath" "$MotdPath"
rm -f "$WarningNetPath"
sudo mv -f "$BackupWarningNetPath" "$WarningNetPath") &> /dev/null
[ "$KEY_AUTH" = 1 ] && (sudo rm -f "$AuthorizedKeysPath"
sudo mv -f "$BackupAuthorizedKeysPath" "$AuthorizedKeysPath") &> /dev/null
[ "$DISABLE_SUSPENSION" = 1 ] && (rm -f "$PowerManProfilePath"
mv -f "$BackupPowerManProfilePath" "$PowerManProfilePath"
_refreshPlasmaConfigStatus) &> /dev/null
# Finalize
sudoTaskFinalize
}

_sshdUnavailable() {
echo_E "Couldn't find sshd service." "200"
exit
}

_sshdScenario() {
local _t; _t="$(_sshdState)"
case "$_t" in
	0) _sshdUnavailable;; # unavailable
	1) _sshdEnable;; # disabled
	2) _sshdDisable;; # enabled
esac
}


### SETTINGS

declare -r settingsJson="settings.json" # Settings fileName
declare -r settingsNames=("KEY_AUTH" "SEC_KEY" "REMEMBER_PASSWORD" "DISABLE_SUSPENSION") # Settings Names
declare -r settingsFormats=("i" "s" "i" "i") # Settings Formats (i - integer; s - string)
declare -r settingsDefaults=("0" "$(_randomPasswordGen "32")" "0" "1") # Settings Default Values

## Reads settings from a 'settingsJson' config file
_readSettingsJson() {
_jq() { jq -r ".$1" "$settingsJson"; }
local _t;
# Settings to read
for (( i=0; i<"${#settingsNames[@]}"; i++ ))
do
	_t="$(_jq "${settingsNames[$i]}")"
	_t=$([ -z "$_t" ] || [ "$_t" = "null" ] && echo "${settingsDefaults[$i]}" || echo "$_t")
	printf -v "${settingsNames[$i]}" -- "%${settingsFormats[$i]}" "$_t"
done
}

## Writes settings to a 'settingsJson' config file
_writeSettingsJson() {
local _n;
local _q;
# Settings to write
for (( i=0; i<"${#settingsNames[@]}"; i++ ))
do
	_n=${settingsNames[$i]}
	[ "$i" -gt 0 ] && _q="$_q | "
	_q="$_q.$_n=\"${!_n}\""
done
jq -n "$_q" > "$settingsJson";
}

## Loads Settings from an existing 'settingsJson' config file or creates a new one
loadSettingsJson() {
local _s="$settingsJson"
if ! [ -e "./$_s" ]; then
	touch "$_s"
	_readSettingsJson # in this case it sets the default settings
	_writeSettingsJson # write new settings file
else
	_readSettingsJson # load settings from the existing file
fi
}


### GLOBAL VARIABLES

## MAIN VARIABLES
SESSION_GUID="$(uuidgen | tr "[:lower:]" "[:upper:]")"; readonly SESSION_GUID
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd); readonly ROOT_DIR
declare -r TOOL_NAME="SteamDeckSSH"
declare -r TOOL_VERSION="v1.0.0"

## PATHS
declare -r PflPath="./.pfl" # previous first launch
declare -r UserSecPath="./.user.sec"
declare -r SshdConfigPath="/etc/ssh/sshd_config"
# PatchedSshdConfigPath will be declared after the values from 'settings.json' file are loaded
declare -r BackupSshdConfigPath="/etc/ssh/sshd_config_original"
declare -r MotdPath="/etc/motd"
declare -r BackupMotdPath="/etc/motd_original"
declare -r PatchedMotdPath="./data/motd"
declare -r WarningNetPath="/etc/ssh/warning.net"
declare -r BackupWarningNetPath="/etc/ssh/warning.net_original"
declare -r PatchedWarningNetPath="./data/warning.net"
declare -r AuthorizedKeysPath="/etc/ssh/authorized_keys"
declare -r BackupAuthorizedKeysPath="/etc/ssh/authorized_keys_original"
declare -r PatchedAuthorizedKeysPath="./data/authorized_keys"
declare -r PowerManProfilePath="/home/$USER/.config/powermanagementprofilesrc"
declare -r BackupPowerManProfilePath="/home/$USER/.config/powermanagementprofilesrc_original"
declare -r PatchedPowerManProfilePath="./data/powermanagementprofilesrc"

## Username and temporary password
userName="$USER" # real username (deck)
declare -r tempPasswd="GabeNewell#1"

## FLAGS
FIRST_LAP=1
USR_CHANGED_PASSWD=0
DEF_USR_HAS_PASSWD=$( ([ "$(_sshdState)" = 2 ] && cat "$PflPath") || (_userHasPassword "$userName" && echo 1 || echo 0) ); readonly DEF_USR_HAS_PASSWD


### MAIN (ENTRY POINT)

## Check sudo
if [ "$(_sudoStatus)" = 0 ]; then
	echo_E "Sorry, but it seems that a current user hasn't got root rights. Please, contact the adminstrator of your device." "450"
	exit
fi

cd -- "$ROOT_DIR" || return

loadSettingsJson
_setPassword "$( ([ -e $UserSecPath ] && "_readUserSec") || echo "$tempPasswd" )"

get_sshd_config() {
case "$KEY_AUTH" in 
	1) echo "sshd_config-ka";; 
	*) echo "sshd_config-pa";; 
esac
} 
PatchedSshdConfigPath="./data/$(get_sshd_config)"; readonly PatchedSshdConfigPath

while true
do
	_sshdScenario
	FIRST_LAP=0
done