#!/usr/bin/env sh

ARCHIVE=${ARCHIVE:-https://archive.hiro.so}

NETWORK=${NETWORK:-mainnet}

SERVICE=${SERVICE:-stacks-blockchain-api}

RELEASE=${RELEASE:-latest}

POSTGRES_VERSION=${POSTGRES_VERSION:-15}

if [ "$SERVICE" = "stacks-blockchain" ]; then
    DATA_FILE=${DATA_FILE:-${NETWORK}-${SERVICE}-${RELEASE}.tar.gz}
    FILE_URL=${FILE_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}/${DATA_FILE}}
    SHA_URL=${SHA_URL:-${ARCHIVE}/${NETWORK}/${SERVICE}/${NETWORK}-${SERVICE}-${RELEASE}.sha256}
    IMPORT_DIR=${IMPORT_DIR:-${PWD}/${SERVICE}/${NETWORK}}
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
fi

USER_ID=${USER_ID:-$(id -u):$(id -g)}

ARCHIVE_CHECK="${IMPORT_DIR}/${SERVICE}_downloaded"

TARFILE="${IMPORT_DIR}/${DATA_FILE}"

set -- "${DATA_FILE}"

echo ""
echo "*********************************"
echo "Downloading ${SERVICE} Data"
echo "*********************************"
echo ""

if [ ! -d "${IMPORT_DIR}" ]; then
    echo ""
    echo "Creating ${SERVICE} data directory: ${IMPORT_DIR}"
    echo ""
    mkdir -p "${IMPORT_DIR}"
fi

if [ ! -f "${ARCHIVE_CHECK}" ]; then
    if [ ! -f "${TARFILE}.sha256" ]; then
        echo ""
        echo "Retrieving ${SERVICE} data as ${TARFILE}"
        echo "From ${FILE_URL}"
        echo ""
        wget "${SHA_URL}" -O "${TARFILE}.sha256" || {
            echo "Failed to download ${TARFILE}.sha256"
            exit 1
        }
    fi
    if [ ! -f "${TARFILE}" ]; then
        wget "${FILE_URL}" -O "${TARFILE}" || {
            echo "Failed to download ${TARFILE}"
            exit 1
        }
    fi
else
    echo "${SERVICE} data already downloaded:"
    ls "${IMPORT_DIR}"/
fi

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

extract_files() {
    file="${1}"
    file_path="${IMPORT_DIR}/${file}"

    if [ "$SERVICE" = "stacks-blockchain" ]; then
        tar -xzf "${TARFILE}" -C "${IMPORT_DIR}"/ "${file}"
    elif [ "$SERVICE" = "stacks-blockchain-api" ]; then
        gzip -dc "${TARFILE}" >"${IMPORT_DIR}/stacks-node-events.tsv"
    fi
}

for FILE in "$@"; do
    echo ""
    echo "Checking sha256 of: ${TARFILE}"
    echo ""

    if ! check_sha256 "${FILE}"; then
        echo "[ Warning ] - sha256 mismatch"
        echo "    - Removing ${FILE}.sha256, re-attempting sha256 verification"
        rm -f "${IMPORT_DIR}/${FILE}.sha256"
        wget "${SHA_URL}" -O "${TARFILE}.sha256" || {
            echo "Failed to re-download ${TARFILE}.sha256"
            exit 1
        }
        if ! check_sha256 "${FILE}"; then
            echo ""
            echo "[ Error ] - Failed to verify sha256 of ${FILE} after 2 attempts"
            rm -f "${IMPORT_DIR}/${FILE}" "${IMPORT_DIR}/${FILE}.sha256"
            exit 1
        fi
    fi

    if [ ! -f "${IMPORT_DIR}/${FILE}" ] || [ ! -f "${IMPORT_DIR}/${FILE}.sha256" ]; then
        echo "Extracting ${SERVICE} files: ${FILE}"
        extract_files "${FILE}"
    fi

    sha256sum=$(sha256sum "${IMPORT_DIR}/${FILE}" | awk {'print $1'})
    echo ""
    printf "  - %-25s: %-20s Matched sha256 with %s\n" "${FILE}" "${sha256sum}" "${FILE}.sha256"
    echo ""
done

if [ ! -f "${ARCHIVE_CHECK}" ]; then
    echo "Setting dir ownership"
    echo "cmd: chown -R ${USER_ID} ${IMPORT_DIR}"
    chown -R "${USER_ID}" "${IMPORT_DIR}"
    echo ""
    echo "Creating ${ARCHIVE_CHECK}"
    touch "${ARCHIVE_CHECK}"
    echo ""
    if [ "${SERVICE}" = "stacks-blockchain" ] || [ "${SERVICE}" = "stacks-blockchain-api" ]; then
        echo "Removing download archive: ${TARFILE} & ${TARFILE}.sha256"
        rm -f "${TARFILE}"
        rm -f "${TARFILE}.sha256"
    else
        rm -f "${TARFILE}.sha256"
    fi
    echo ""
    echo "${SERVICE} data downloaded and verified"
fi
echo
echo "${SERVICE} data check complete"
echo ""
exit 0
