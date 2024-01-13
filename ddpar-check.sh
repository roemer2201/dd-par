#!/bin/bash



# Set the input and output file names
#OUTPUT_PATH=/dev
#OUTPUT_FILE_BASENAME=sdi
#OUTPUT_FILE="${OUTPUT_PATH}/${OUTPUT_FILE_BASENAME}"
#OUTPUT_FILE_TYPE="$(file -b $OUTPUT_FILE)"
INPUT_PATH=""
INPUT_FILE_BASENAME=""

function show_help {
  SCRIPT_NAME=$(basename "$0")
  echo "$SCRIPT_NAME - Ein Bash-Skript zur Verarbeitung von Parametern"
  echo "Verwendung: $SCRIPT_NAME [Optionen]"
  echo ""
  echo "Optionen:"
  echo "-p, --path PATH         Speicherort des Splitimages"
  echo "-n, --name NAME         Der Basisname des geteilten Abbildes"
  echo "-d                      Destination to compare against"
  echo "-h, --help              Zeigt diese Hilfemeldung an"
}

function check_restored_image {
  for ((i=0; i<$NUM_JOBS; i++)); do
    START=$((i * SPLIT_SIZE))
    echo "dd if=$OUTPUT_FILE bs=$BLOCKSIZEBYTES count=$((SPLIT_SIZE / $BLOCKSIZEBYTES)) skip=$((START / BLOCKSIZEBYTES)) status=none | sha256sum -c $INPUT_FILES$i.sha256 | sed s#-#$INPUT_FILES$i# &"
    dd if=$OUTPUT_FILE bs=$BLOCKSIZEBYTES count=$((SPLIT_SIZE / $BLOCKSIZEBYTES)) skip=$((START / BLOCKSIZEBYTES)) status=none | sha256sum -c $INPUT_FILES$i.sha256 | sed s#-#$INPUT_FILES$i# &
  done
}

# Verwendung von getopts zur Verarbeitung der Optionen
while getopts ":p:n:h" opt; do
  case $opt in
    p|-path) INPUT_PATH="$OPTARG";;
    n|-name) INPUT_FILE_BASENAME="$OPTARG";;
    d) DESTINATION="$OPTARG" ;;
    h|-help) show_help; exit 0;;
    \?) echo "Ungültige Option: -$OPTARG";;
  esac
done

# Überprüfung der erforderlichen Parameter
if [ -z "${INPUT_PATH}" ] || [ -z "${INPUT_FILE_BASENAME}" ]; then
  echo "Fehlende Parameter. Bitte geben Sie alle erforderlichen Parameter an."
  exit 1
fi

# Create spinoff variables
INPUT_FILES="${INPUT_PATH}/${INPUT_FILE_BASENAME}-"
METADATA_FILE="${INPUT_FILES}metadata.txt"
OUTPUT_FILE=$DESTINATION
OUTPUT_FILE_TYPE="$(file -b $DESTINATION)"

echo ${INPUT_PATH}
echo ${INPUT_FILE_BASENAME}
echo ${INPUT_FILES}*

# Get parameters from metadata file
NUM_JOBS=$(grep "NUM_JOBS" $METADATA_FILE | cut -d "=" -f 2)
SPLIT_SIZE=$(grep "SPLIT_SIZE" $METADATA_FILE | cut -d "=" -f 2)
INPUT_FILE_TYPE=$(grep "FILE_TYPE" $METADATA_FILE | cut -d "=" -f 2)
BLOCKSIZEBYTES=$(grep "BLOCKSIZEBYTES" $METADATA_FILE | cut -d "=" -f 2)

echo ${INPUT_FILE_TYPE}
echo ${OUTPUT_FILE_TYPE}
if [[ "${INPUT_FILE_TYPE}" == "block special"* ]] && [[ "${OUTPUT_FILE_TYPE}" == "block special"* ]]; then
  echo "Beginning to check ..."
  check_restored_image
fi
if [[ "${INPUT_FILE_TYPE}" != "block special"* ]] && [[ "${OUTPUT_FILE_TYPE}" != "block special"* ]]; then
  echo "Beginning to check ..."
  check_restored_image
fi
wait

