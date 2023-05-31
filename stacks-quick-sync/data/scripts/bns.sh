#!/usr/bin/env sh

BNS_IMPORT_DIR=${BNS_IMPORT_DIR:-${PWD}/bns-data}
USER_ID=$(id -u):$(id -g)

if [ ! -d "${BNS_IMPORT_DIR}" ]; then
    echo "Creating BNS Data directory: ${BNS_IMPORT_DIR}"
    mkdir -p "${BNS_IMPORT_DIR}"
fi

set -- chainstate.txt name_zonefiles.txt subdomain_zonefiles.txt subdomains.csv

echo ""
echo "*********************************"
echo " Setting up Stacks 1.0 BNS Data"
echo "*********************************"
echo ""

BNS_CHECK="${BNS_IMPORT_DIR}/bns_installed"
TARFILE="${BNS_IMPORT_DIR}/export-data.tar.gz"

if [ ! -f "${BNS_CHECK}" ]; then
    echo "Retrieving V1 BNS data as ${BNS_IMPORT_DIR}/export-data.tar.gz"
    wget "https://storage.googleapis.com/blockstack-v1-migration-data/export-data.tar.gz" -O "${TARFILE}" || { echo "Failed to download ${TARFILE}"; exit 1; }
else
    echo "BNS data already installed:"
    ls ${BNS_IMPORT_DIR}/ 
fi

check_sha256() {
    file="${1}"
    file_256="${file}.sha256"
    file_path="${BNS_IMPORT_DIR}/${file}"
    file_256_path="${BNS_IMPORT_DIR}/${file_256}"
    
    sha256=$(cat ${file_256_path})
    sha256sum=$(sha256sum ${file_path} | awk {'print $1'})

    [ "${sha256}" = "${sha256sum}" ]
}

extract_files() {
    file="${1}"
    file_256="${file}.sha256"
    file_path="${BNS_IMPORT_DIR}/${file}"
    file_256_path="${BNS_IMPORT_DIR}/${file_256}"
    
    tar -xzf ${TARFILE} -C ${BNS_IMPORT_DIR}/ ${file} ${file_256}
}

for FILE in "$@"; do
    echo
    echo "Checking sha256 of:"
    
    if [ ! -f "${BNS_IMPORT_DIR}/${FILE}" ] || [ ! -f "${BNS_IMPORT_DIR}/${FILE}.sha256" ]; then
        echo "Extracting BNS files: ${FILE} and ${FILE}.sha256"
        extract_files "${FILE}"
    fi
    
    if ! check_sha256 "${FILE}"; then
        echo "[ Warning ] - sha256 mismatch"
        echo "    - Removing ${FILE} and ${FILE}.sha256, re-attempting sha256 verification"
        rm -f "${BNS_IMPORT_DIR}/${FILE}" "${BNS_IMPORT_DIR}/${FILE}.sha256"
        extract_files "${FILE}"
        
        if ! check_sha256 "${FILE}"; then
            echo
            echo "[ Error ] - Failed to verify sha256 of ${FILE} after 2 attempts"
            exit 1
        fi
    fi
    
    sha256sum=$(sha256sum "${BNS_IMPORT_DIR}/${FILE}" | awk {'print $1'})
    printf "  - %-25s: %-20s Matched sha256 with %s\n" "${FILE}" "${sha256sum}" "${FILE}.sha256"
done

if [ ! -f "${BNS_CHECK}" ]; then
    echo "Setting dir ownership"
    echo "cmd: chown -R ${USER_ID} ${BNS_IMPORT_DIR}"
    chown -R ${USER_ID} ${BNS_IMPORT_DIR}
    echo
    echo "Creating ${BNS_CHECK}"
    touch ${BNS_CHECK}
    echo
    echo "Removing download archive: ${TARFILE}"
    rm -f ${TARFILE}
    echo
    echo "BNS data downloaded and verified"
fi
echo
echo "BNS data check complete"
echo ""
exit 0