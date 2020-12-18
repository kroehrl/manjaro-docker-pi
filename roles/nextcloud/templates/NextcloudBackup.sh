#!/bin/bash
#
# Bash script for creating backups of Nextcloud.
#
# Version 2.0.0
#
# Usage:
# 	- With backup directory specified in the script:  ./NextcloudBackup.sh
# 	- With backup directory specified by parameter: ./NextcloudBackup.sh <BackupDirectory> (e.g. ./NextcloudBackup.sh /media/hdd/nextcloud_backup)
#
# The script is based on an installation of Nextcloud using nginx and MariaDB, see https://decatec.de/home-server/nextcloud-auf-ubuntu-server-18-04-lts-mit-nginx-mariadb-php-lets-encrypt-redis-und-fail2ban/
# Original Script: https://codeberg.org/DecaTec/Nextcloud-Backup-Restore

#
# IMPORTANT
# You have to customize this script (directories, users, etc.) for your actual environment.
# All entries which need to be customized are tagged with "TODO".
#

#
# Get starttime
#
start=`date +%s`
echo "Start: $(date -d @${start})"

# Variables
backupMainDir=$1

if [ -z "$backupMainDir" ]; then
	# TODO: The directory where you store the Nextcloud backups (when not specified by args)
    backupMainDir='{{ nextcloud_backup_dir }}/nextcloud'
fi

currentDate=$(date +"%Y%m%d_%H%M%S")

# The actual directory of the current backup - this is a subdirectory of the main directory above with a timestamp
backupdir="${backupMainDir}/${currentDate}/"

# TODO: The directory of your Nextcloud installation (this is a directory under your web root)
nextcloudFileDir='{{ nextcloud_config_dir }}/www/nextcloud'

# TODO: The directory of your Nextcloud data directory (outside the Nextcloud file directory)
# If your data directory is located under Nextcloud's file directory (somewhere in the web root), the data directory should not be a separate part of the backup
nextcloudDataDir='{{ nextcloud_data_dir }}'

# TODO: Your web server user
webserverUser='{{ nextcloud_webserver_user }}'

# TODO: The name of the nextcloud container
nextcloudContainer='nextcloud'

# TODO: The name of the database container
databaseContainer='mariadb'

# TODO: Your Nextcloud database name
nextcloudDatabase='nextcloud'

# TODO: Your Nextcloud database user
dbUser='nextcloud'

# TODO: The password of the Nextcloud database user
dbPassword='{{ mysql_password }}'

# TODO: The maximum number of backups to keep (when set to 0, all backups are kept)
maxNrOfBackups=14

# TODO: Ignore updater's backup directory in the data directory to save space
# Set to true to ignore the backup directory
ignoreUpdaterBackups=true

# File names for backup files
# If you prefer other file names, you'll also have to change the NextcloudRestore.sh script.
fileNameBackupFileDir='nextcloud-filedir.tar.gz'
fileNameBackupDataDir='nextcloud-datadir.tar.gz'

fileNameBackupDb='nextcloud-db.sql'

# Function for error messages
errorecho() { cat <<< "$@" 1>&2; }

function DisableMaintenanceMode() {
	echo "Switching off maintenance mode..."
	docker exec --user ${webserverUser} ${nextcloudContainer} php /config/www/nextcloud/occ maintenance:mode --off
	echo "Done"
	echo
}

# Capture CTRL+C
trap CtrlC INT

function CtrlC() {
	read -p "Backup cancelled. Keep maintenance mode? [y/n] " -n 1 -r
	echo

	if ! [[ $REPLY =~ ^[Yy]$ ]]
	then
		DisableMaintenanceMode
	else
		echo "Maintenance mode still enabled."
	fi

	exit 1
}

#
# Print information
#
echo ""
echo "Backup directory: ${backupMainDir}"

#
# Check for root
#
if [ "$(id -u)" != "0" ]
then
	errorecho "ERROR: This script has to be run as root!"
	exit 1
fi

#
# Check if backup dir already exists
#
if [ ! -d "${backupdir}" ]
then
	mkdir -p "${backupdir}"
else
	errorecho "ERROR: The backup directory ${backupdir} already exists!"
	exit 1
fi

#
# Set maintenance mode
#
echo "Set maintenance mode for Nextcloud..."
docker exec --user ${webserverUser} ${nextcloudContainer} php /config/www/nextcloud/occ maintenance:mode --on
echo "Done"
echo

#
# Backup file directory
#
echo "Creating backup of Nextcloud file directory..."
tar -cpzf "${backupdir}/${fileNameBackupFileDir}" -C "${nextcloudFileDir}" .
echo "Done"
echo

#
# Backup data directory
#
echo "Creating backup of Nextcloud data directory..."

if [ "$ignoreUpdaterBackups" = true ] ; then
        echo "Ignoring updater backup directory"
        tar -cpzf "${backupdir}/${fileNameBackupDataDir}"  --exclude="updater-*/backups/*" -C "${nextcloudDataDir}" .
else
        tar -cpzf "${backupdir}/${fileNameBackupDataDir}"  -C "${nextcloudDataDir}" .
fi

echo "Done"
echo

#
# Backup DB
#
echo "Backup Nextcloud database (MariaDB)..."
docker exec ${databaseContainer} /usr/bin/mysqldump -u "${dbUser}"  -p"${dbPassword}" "${nextcloudDatabase}" > "${backupdir}/${fileNameBackupDb}"
echo "Done"
echo

#
# Disable maintenance mode
#
DisableMaintenanceMode

#
# Delete old backups
#
if [ ${maxNrOfBackups} != 0 ]
then
	nrOfBackups=$(ls -l ${backupMainDir} | grep -c ^d)

	if [[ ${nrOfBackups} > ${maxNrOfBackups} ]]
	then
		echo "Removing old backups..."
		ls -t ${backupMainDir} | tail -$(( nrOfBackups - maxNrOfBackups )) | while read -r dirToRemove; do
			echo "${dirToRemove}"
			rm -r "${backupMainDir}/${dirToRemove:?}"
			echo "Done"
			echo
		done
	fi
fi

echo
echo "DONE!"
echo "Backup created: ${backupdir}"

#
# Get endtime and runtime
#
end=`date +%s`
echo "End: $(date -d @${end})"

runtime=$((end-start))
hours=$((runtime / 3600))
minutes=$(( (runtime % 3600) / 60 ))
seconds=$(( (runtime % 3600) % 60 )) 
printf "Runtime: %02i:%02i:%02i (hh:mm:ss)" $hours $minutes $seconds