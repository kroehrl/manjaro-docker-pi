#!/bin/bash
#
# Bash script for restoring backups of Nextcloud.
#
# Version 2.0.0
#
# Usage:
#   - With backup directory specified in the script: ./NextcloudRestore.sh <BackupName> (e.g. ./NextcloudRestore.sh 20170910_132703)
#   - With backup directory specified by parameter: ./NextcloudRestore.sh <BackupName> <BackupDirectory> (e.g. ./NextcloudRestore.sh 20170910_132703 /media/hdd/nextcloud_backup)
#
# The script is based on an installation of Nextcloud using nginx and MariaDB, see https://decatec.de/home-server/nextcloud-auf-ubuntu-server-18-04-lts-mit-nginx-mariadb-php-lets-encrypt-redis-und-fail2ban/
# Original Script: https://codeberg.org/DecaTec/Nextcloud-Backup-Restore

#
# IMPORTANT
# You have to customize this script (directories, users, etc.) for your actual environment.
# All entries which need to be customized are tagged with "TODO".
#

# Variables
restore=$1
backupMainDir=$2

if [ -z "$backupMainDir" ]; then
	# TODO: The directory where you store the Nextcloud backups (when not specified by args)
    backupMainDir='{{ nextcloud_backup_dir }}/Nextcloud'
fi

echo "Backup directory: $backupMainDir"

currentRestoreDir="${backupMainDir}/${restore}"

# TODO: The directory of your Nextcloud installation (this is a directory under your web root)
nextcloudFileDir='{{ nextcloud_config_dir }}/www/nextcloud'

# TODO: The directory of your Nextcloud data directory (outside the Nextcloud file directory)
# If your data directory is located under Nextcloud's file directory (somewhere in the web root), the data directory should not be restored separately
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

# TODO: Docker-compose file
dockerComposeFile='{{ nextcloud_compose_dir }}/docker-compose.yml'

# File names for backup files
# If you prefer other file names, you'll also have to change the NextcloudBackup.sh script.
fileNameBackupFileDir='nextcloud-filedir.tar.gz'
fileNameBackupDataDir='nextcloud-datadir.tar.gz'

fileNameBackupDb='nextcloud-db.sql'

# Function for error messages
errorecho() { cat <<< "$@" 1>&2; }

#
# Check if parameter(s) given
#
if [ $# != "1" ] && [ $# != "2" ]
then
    errorecho "ERROR: No backup name to restore given, or wrong number of parameters!"
    errorecho "Usage: NextcloudRestore.sh 'BackupDate' ['BackupDirectory']"
    exit 1
fi

#
# Check for root
#
if [ "$(id -u)" != "0" ]
then
    errorecho "ERROR: This script has to be run as root!"
    exit 1
fi

#
# Check if backup dir exists
#
if [ ! -d "${currentRestoreDir}" ]
then
	errorecho "ERROR: Backup ${restore} not found!"
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
# Delete old Nextcloud directories
#

# File directory
echo "Deleting old Nextcloud file directory..."
rm -r "${nextcloudFileDir}"
mkdir -p "${nextcloudFileDir}"
echo "Done"
echo

# Data directory
echo "Deleting old Nextcloud data directory..."
rm -r "${nextcloudDataDir}"
mkdir -p "${nextcloudDataDir}"
echo "Done"
echo

#
# Restore file and data directory
#

# File directory
echo "Restoring Nextcloud file directory..."
tar -xmpzf "${currentRestoreDir}/${fileNameBackupFileDir}" -C "${nextcloudFileDir}"
echo "Done"
echo

# Data directory
echo "Restoring Nextcloud data directory..."
tar -xmpzf "${currentRestoreDir}/${fileNameBackupDataDir}" -C "${nextcloudDataDir}"
echo "Done"
echo

#
# Restore database
#
echo "Dropping old Nextcloud DB..."
docker exec ${databaseContainer} /usr/bin/mysql -h localhost -u "${dbUser}"  -p"${dbPassword}" -e "DROP DATABASE ${nextcloudDatabase}"
echo "Done"
echo

echo "Creating new DB for Nextcloud..."
docker exec ${databaseContainer} /usr/bin/mysql -h localhost -u "${dbUser}"  -p"${dbPassword}" -e "CREATE DATABASE ${nextcloudDatabase} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
echo "Done"
echo

echo "Restoring backup DB..."
docker cp "${currentRestoreDir}/${fileNameBackupDb}" ${databaseContainer}:/dump
docker exec ${databaseContainer} /bin/bash -c "/usr/bin/mysql -u '${dbUser}' -p'${dbPassword}' '${nextcloudDatabase}' < /dump"
docker exec ${databaseContainer} /bin/bash -c "rm /dump"
echo "Done"
echo

#
# Restart nextcloud
#
echo "Restarting nextcloud stack..."
docker-compose -f ${dockerComposeFile} restart
echo "Done"
echo

#
# Set directory permissions
#
echo "Setting directory permissions..."
docker exec nextcloud chown -R "${webserverUser}":"${webserverUser}" "/data"
docker exec nextcloud chown -R "${webserverUser}":"${webserverUser}" "/config"
echo "Done"
echo

#
# Update the system data-fingerprint (see https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html#maintenance-commands-label)
#
echo "Updating the system data-fingerprint..."
docker exec --user ${webserverUser} ${nextcloudContainer} php /config/www/nextcloud/occ maintenance:data-fingerprint
echo "Done"
echo

#
# Disbale maintenance mode
#
echo "Switching off maintenance mode..."
docker exec --user ${webserverUser} ${nextcloudContainer} php /config/www/nextcloud/occ maintenance:mode --off
echo "Done"
echo

echo
echo "DONE!"
echo "Backup ${restore} successfully restored."