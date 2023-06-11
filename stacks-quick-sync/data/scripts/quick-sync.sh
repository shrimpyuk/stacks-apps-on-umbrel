#!/usr/bin/env sh

# Setting default values for variables or use values from environment variables if they exist
ARCHIVE=${ARCHIVE:-https://archive.hiro.so}
NETWORK=${NETWORK:-mainnet}
SERVICE=${SERVICE:-stacks-blockchain}
RELEASE=${RELEASE:-latest}
USER_ID=${USER_ID:-$(id -u):$(id -g)}
DL_RATE=${DL_RATE:-0}
POSTGRES_VERSION=${POSTGRES_VERSION:-15}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_DB=${POSTGRES_DB:-postgres}
IMPORT=${IMPORT:-false}
EXTRACT=${EXTRACT:-true}

# Set different data file names and URLs based on the service being used
if [ "$SERVICE" = "stacks-blockchain" ]; then
    DATA_FILE=${DATA_FILE:-${NETWORK}-${SERVICE}-${RELEASE}.tar.gz}
    FILE_URL=${FILE_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}/${DATA_FILE}}
    SHA_URL=${SHA_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}/${NETWORK}-${SERVICE}-${RELEASE}.sha256}
    IMPORT_DIR=${IMPORT_DIR:-${PWD}/${SERVICE}}
elif [ "$SERVICE" = "stacks-blockchain-api" ]; then
    DATA_FILE=${DATA_FILE:-${NETWORK}-${SERVICE}-${RELEASE}.gz}
    FILE_URL=${FILE_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}/${DATA_FILE}}
    SHA_URL=${SHA_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}/${NETWORK}-${SERVICE}-${RELEASE}.sha256}
    IMPORT_DIR=${IMPORT_DIR:-${PWD}/event-replay}
elif [ "$SERVICE" = "postgres" ]; then
    DATA_FILE=${DATA_FILE:-stacks-blockchain-api-pg-${POSTGRES_VERSION}-${RELEASE}.dump}
    FILE_URL=${FILE_URL:-${ARCHIVE}/${NETWORK}/stacks-blockchain-api-pg/${DATA_FILE}}
    SHA_URL=${SHA_URL:-${ARCHIVE}/${NETWORK}/stacks-blockchain-api-pg/stacks-blockchain-api-pg-${POSTGRES_VERSION}-${RELEASE}.sha256}
    IMPORT_DIR=${IMPORT_DIR:-${PWD}/${SERVICE}}
elif [ "$SERVICE" = "token-metadata" ]; then
    DATA_FILE=${DATA_FILE:-${SERVICE}-api-pg-${POSTGRES_VERSION}-${RELEASE}.dump}
    FILE_URL=${FILE_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}-api-pg/${DATA_FILE}}
    SHA_URL=${SHA_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}-api-pg/${SERVICE}-api-pg-${POSTGRES_VERSION}-${RELEASE}.sha256}
    IMPORT_DIR=${IMPORT_DIR:-${PWD}/${SERVICE}}
fi

TARFILE="${IMPORT_DIR}/${DATA_FILE}"

set -- "${DATA_FILE}"

# Function to check if necessary commands are available and install if they are not
check_commands() {
    # Determine whether to use apk (Alpine) or apt-get (Ubuntu/Debian)
    if command -v apk > /dev/null 2>&1; then
        INSTALL_CMD="apk add --upgrade"
    elif command -v apt-get > /dev/null 2>&1; then
        INSTALL_CMD="apt-get install -y"
    else
        echo "Neither apk nor apt-get are available on your system."
        exit 1
    fi

    # Check and install required commands
    for cmd in wget tar gzip sha256sum pv; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            echo "${cmd} is not installed. Attempting to install..."
            $INSTALL_CMD "$cmd"
        fi
    done

    if [ "$SERVICE" = "postgres" ] || [ "$SERVICE" = "token-metadata" ]; then
        if [ "$IMPORT" = "true" ]; then
            if ! command -v pg_restore > /dev/null 2>&1; then
                echo "pg_restore is not installed. Attempting to install postgresql..."
                if [ "$INSTALL_CMD" = "apk add --upgrade" ]; then
                    $INSTALL_CMD postgresql"${POSTGRES_VERSION}"
                else
                    apt-get update
                    apt-get install -y curl ca-certificates gnupg lsb-release
                    curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
                    release=$(lsb_release -cs)
                    echo "deb http://apt.postgresql.org/pub/repos/apt ${release}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
                    apt-get update
                    apt-get install -y postgresql-"${POSTGRES_VERSION}"
                fi
            fi
        fi
    fi

    if [ "$SERVICE" = "stacks-blockchain-api" ]; then
        if [ "$IMPORT" = "true" ]; then
            if ! command -v node > /dev/null 2>&1; then
                echo "nodejs is not installed. Attempting to install nodejs..."
                if [ "$INSTALL_CMD" = "apk add --upgrade" ]; then
                    $INSTALL_CMD nodejs-current
                else
                    apt-get update
                    apt-get install -y nodejs
                fi
            fi
        fi
    fi
}


apt-get update
apt-get install -y curl ca-certificates gnupg lsb-release
curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
release=$(lsb_release -cs)
echo "deb http://apt.postgresql.org/pub/repos/apt ${release}-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install postgresql-"${POSTGRES_VERSION}"


# Function to download files if they do not exist in the specified path
download_file() {
    file_url="$1"
    output_file="$2"
    dl_rate="$3"

    if [ ! -f "${output_file}" ]; then
        if [ "${dl_rate}" -eq 0 ]; then
            echo "Downloading ${output_file}"
            wget "${file_url}" -O "${output_file}" --user-agent="Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36" || {
                echo "Failed to download ${output_file}"
                exit 1
            }
        else
            echo "Downloading ${output_file} with rate limit of ${dl_rate}m"
            wget--user-agent="Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36" --limit-rate="${dl_rate}m" "${file_url}" -O "${output_file}" || {
                echo "Failed to download ${output_file}"
                exit 1
            }
        fi
    fi
}

# Function to import data for stacks-blockchain-api and postgres services
import_files() {
    file="${1}"
    file_path="${IMPORT_DIR}/${file}"
    echo ""
    echo "**********************************************************"
    echo "   Importing ${SERVICE} Data. This will take awhile..."
    echo "**********************************************************"
    if [ "$SERVICE" = "stacks-blockchain-api" ]; then
        # Event replay import will only work when run from stacks-blockchain-api directory/docker container
        if [ -f ./lib/index.js ]; then
            # For stacks-blockchain-api, kill existing node process and start new one for importing events
            pkill node
            node ./lib/index.js import-events --file "${IMPORT_DIR}/stacks-node-events.tsv" --wipe-db --force >> "${IMPORT_DIR}/output.log" 2>&1 &
            # Waiting for successful import or failed import message
            while true; do
            sleep 10
                if grep -q "Event import and playback successful" "${IMPORT_DIR}/output.log"; then
                    echo "Event import and playback successful"
                    break
                elif grep -q "import-events process failed" "${IMPORT_DIR}/output.log"; then
                    echo "import-events process failed, trying again..."
                    # Kill the previous node process
                    pkill node
                    # Try running the node command again
                    node ./lib/index.js import-events --file "${IMPORT_DIR}/stacks-node-events.tsv" --wipe-db --force >> "${IMPORT_DIR}/output.log" 2>&1
                fi
            done
        else
            echo "Can not find stacks blockchain api ./lib/index.js file. Please check if the file is in the correct directory."
            return 1
        fi
    elif [ "$SERVICE" = "postgres" ] || [ "$SERVICE" = "token-metadata" ]; then
        # For postgres, use pg_restore to import data
        PGPASSWORD=$POSTGRES_PASSWORD pg_restore -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -v "${TARFILE}"
    fi
    echo ""
    echo "Done importing ${SERVICE} Data"
}

# Function to verify the sha256 checksum of the downloaded file
check_sha256() {
    file="${1}"
    file_256="${file}.sha256"
    file_path="${IMPORT_DIR}/${file}"
    file_256_path="${IMPORT_DIR}/${file_256}"
    filename="${DATA_FILE}"
    sha256=$(awk '{print $1}' "${file_256_path}")
    echo "Sha256 given: $sha256  $filename"
    sha256sum=$(sha256sum "${file_path}" | awk {'print $1'})
    echo ""
    echo "Sha256 found: $sha256sum  ${file}"
    [ "${sha256}" = "${sha256sum}" ] && [ "${filename}" = "${file}" ]
}

# Function to extract the downloaded files
extract_files() {
    file="${1}"
    file_path="${IMPORT_DIR}/${file}"
    echo ""
    echo "**********************************************************"
    echo "   Extracting ${SERVICE} Data. This will take awhile..."
    echo "**********************************************************"
    if [ "$SERVICE" = "stacks-blockchain" ]; then
        # If service is stacks-blockchain, use tar to extract the filer 
        pv -p -t -e -w 80 "${TARFILE}" | tar -xzf - -C "${IMPORT_DIR}" >/dev/null
    elif [ "$SERVICE" = "stacks-blockchain-api" ]; then
        # If service is stacks-blockchain-api, use gzip to decompress the file
        gzip -dc "${TARFILE}" > "${IMPORT_DIR}/stacks-node-events.tsv"
    fi
    echo ""
    echo "Done extracting ${SERVICE} Data"
}

# Start of the main execution
echo ""
echo "**********************************************************"
echo "        Running setup script for ${SERVICE} Data"
echo "**********************************************************"
echo ""

# Start of the main execution
check_commands

# Check if import directory exists, if not create it
if [ ! -d "${IMPORT_DIR}" ]; then
    echo ""
    echo "Creating ${SERVICE} data directory: ${IMPORT_DIR}"
    echo ""
    mkdir -p "${IMPORT_DIR}"
fi

echo ""
echo "Retrieving ${SERVICE} data as ${TARFILE}"
echo "From ${FILE_URL}"
echo ""
# Download sha256 and actual service file
download_file "${SHA_URL}" "${TARFILE}.sha256" "${DL_RATE}"
download_file "${FILE_URL}" "${TARFILE}" "${DL_RATE}"

# Iterate over all the files to check sha256, extract and import them
for FILE in "$@"; do
    echo ""
    echo "Checking sha256 of: ${TARFILE}"
    echo ""

    # Check sha256 checksum of downloaded file
    if ! check_sha256 "${FILE}"; then
        echo "[ Warning ] - sha256 mismatch"
        echo "    - Removing ${FILE}, re-attempting sha256 verification"
        rm -f "${IMPORT_DIR}/${FILE}" "${IMPORT_DIR}/${FILE}.sha256"
        download_file "${SHA_URL}" "${TARFILE}.sha256" || {
            echo "Failed to re-download ${TARFILE}.sha256"
            exit 1
        }
        download_file "${FILE_URL}" "${TARFILE}" "${DL_RATE}" || {
            echo "Failed to re-download ${TARFILE}"
            exit 1
        }
        if ! check_sha256 "${FILE}"; then
            echo ""
            echo "[ Error ] - Failed to verify sha256 of ${FILE} after 2 attempts"
            rm -f "${IMPORT_DIR}/${FILE}" "${IMPORT_DIR}/${FILE}.sha256"
            exit 1
        fi
    else
        sha256sum=$(sha256sum "${IMPORT_DIR}/${FILE}" | awk {'print $1'})
        echo ""
        printf "  - %-25s: %-20s Matched sha256 with %s\n" "${FILE}" "${sha256sum}" "${FILE}.sha256"
        echo ""

        # If file exists, extract and import it based on the service
        if [ -f "${IMPORT_DIR}/${FILE}" ]; then
            if [ "$SERVICE" = "stacks-blockchain" ] || [ "$SERVICE" = "stacks-blockchain-api" ]; then
                if [ "$EXTRACT" = "true" ]; then
                    echo "Extracting ${SERVICE} files: ${FILE}"
                    extract_files "${FILE}"
                    if [ "$SERVICE" = "stacks-blockchain-api" ]; then
                        if [ "$IMPORT" = "true" ]; then
                            echo "Importing ${SERVICE} files: ${FILE}"
                            import_files "${FILE}"
                        fi
                    fi
                fi
            else #postgres or token-metadata
                if [ "$IMPORT" = "true" ]; then
                    echo "Importing ${SERVICE} files: ${FILE}"
                    import_files "${FILE}"
                fi
            fi
        fi
    fi
done

# Setting the ownership of the import directory to the user
echo "Setting dir ownership"
echo "cmd: chown -R ${USER_ID} ${IMPORT_DIR}"
chown -R "${USER_ID}" "${IMPORT_DIR}"

# Cleanup: Removing downloaded files
echo ""
echo "Cleaning up downloaded files"
if [ -f "${IMPORT_DIR}/${FILE}" ]; then
    echo "Removing download archive: ${TARFILE}"
    rm -f "${IMPORT_DIR}/${FILE}"
elif [ -f "${IMPORT_DIR}/${FILE}.sha256" ]; then
    echo "Removing downloaded ${IMPORT_DIR}/${FILE}.sha256"
    rm -f "${IMPORT_DIR}/${FILE}.sha256"
fi

# Script execution complete
echo ""
echo "${SERVICE} data downloaded and verified"
echo ""
echo "${SERVICE} data check complete"
echo ""
exit 0
