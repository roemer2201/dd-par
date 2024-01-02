#!/bin/bash

# Set default input and output file names

INPUT_FILE_BASENAME=""
OUTPUT_FILE=""

# Hilfemeldung anzeigen
function show_help {
  SCRIPT_NAME=$(basename "$0")
  echo "$SCRIPT_NAME - Ein Bash-Skript zur Verarbeitung von Parametern"
  echo "Verwendung: $SCRIPT_NAME [Optionen]"
  echo ""
  echo "Optionen:"
  echo "-i, --input PATH        Der Basisname des geteilten Abbildes"
  echo "-o, --output PATH       Vollständiger Pfad des Zielgeräts"
  echo "-h, --help              Diese Hilfe anzeigen"
  echo ""
  echo "Die Anzahl der Jobs und Blockgröße kann nicht geändert werden. Sie wird beim Erstellen des Abbildes festgelegt."
}

# Verwendung von getopts zur Verarbeitung der Optionen
while getopts ":i:o:h" opt; do
  case $opt in
    i|-input) INPUT="$OPTARG";;
    o|-output) OUTPUT="$OPTARG";;
    h|-help) show_help; exit 1;;
    \?) echo "Ungültige Option: -$OPTARG";;
  esac
done


function restore_split_image {
  for ((i=0; i<$NUM_JOBS; i++)); do
    START=$((i * SPLIT_SIZE))
    touch $OUTPUT_FILE
    echo "zcat ${INPUT_FILES}${i}.gz | dd of=$OUTPUT_FILE bs=$BLOCKSIZEBYTES seek=$((START / BLOCKSIZEBYTES)) &"
    zcat ${INPUT_FILES}${i}.gz | dd of=$OUTPUT_FILE bs=$BLOCKSIZEBYTES seek=$((START / BLOCKSIZEBYTES)) &
  done
}


# Create spinoff variables
INPUT_PATH=$(dirname $INPUT)
INPUT_FILE_BASENAME=$(basename $INPUT)
INPUT_FILES="${INPUT_PATH}/${INPUT_FILE_BASENAME}-"
#OUTPUT_PATH=/dev
#OUTPUT_FILE_BASENAME=sdi
#OUTPUT_FILE="${OUTPUT_PATH}/${OUTPUT_FILE_BASENAME}"
OUTPUT_FILE_TYPE="$(file -b $OUTPUT)"
METADATA_FILE="${INPUT_FILES}metadata.txt"

# Get parameters from metadata file
if [ ! -e "$METADATA_FILE" ]; then
  echo "Die Datei existiert $METADATA_FILE nicht."
  exit 1
fi
NUM_JOBS=$(grep "NUM_JOBS" $METADATA_FILE | cut -d "=" -f 2)
SPLIT_SIZE=$(grep "SPLIT_SIZE" $METADATA_FILE | cut -d "=" -f 2)
INPUT_SIZE=$(grep "INPUT_SIZE" $METADATA_FILE | cut -d "=" -f 2)
INPUT_FILE_TYPE=$(grep "FILE_TYPE" $METADATA_FILE | cut -d "=" -f 2)
BLOCKSIZEBYTES=$(grep "BLOCKSIZEBYTES" $METADATA_FILE | cut -d "=" -f 2)

# Überprüfung der erforderlichen Parameter
if [ -z "$INPUT_PATH" ] || [ -z "$INPUT_FILE_BASENAME" ] || [ -z "$OUTPUT" ]; then
  echo "Fehlende Parameter. Bitte geben Sie alle erforderlichen Parameter an."
  exit 1
fi

if [ -e $OUTPUT ]; then
  # Determine the type of the output
  OUTPUT_FILE_TYPE=$(file -b $OUTPUT)
  # Use the appropriate command to determine destination types and sizes
  case "$OUTPUT_FILE_TYPE" in
    # Wenn OUTPUT_FILE ein Blockdevice ist, prüfen, ob OUTPUT_FILE groß genug ist.
    "block special"*)
      OUTPUT_SIZE=$(blockdev --getsize64 $OUTPUT)
      if [ "$BLOCKSIZEBYTES" -gt "$OUTPUT_SIZE" ]; then
        echo "Fehler: Die Eingabegröße ($BLOCKSIZEBYTES) ist größer als die Ausgabegröße ($OUTPUT_SIZE)."
        exit 1
      fi
      OUTPUT_FILE="$OUTPUT"
      ;;
    # Wenn OUTPUT ein Verzeichnis ist, prüfen, ob genügend freier Speicherplatz vorhanden ist.
    directory)
      AVAILABLE_SPACE=$(df -B 1 "$OUTPUT" | awk 'NR==2{print $4}')
      if [ ! "$AVAILABLE_SPACE" -ge "$INPUT_SIZE" ]; then
        echo "Fehler: Nicht genügend Speicherplatz vorhanden für $INPUT_FILE_BASENAME in $OUTPUT ."
        exit 1
      fi
      OUTPUT_FILE="$OUTPUT/$INPUT_FILE_BASENAME"
      ;;
    # Wenn OUTPUT eine Datei ist (die bereits exitiert), prüfen, ob genügend freier Speicherplatz vorhanden ist.
    *)
      OUTPUT_DIR=$(dirname "$OUTPUT")
      OUTPUT_FILE="$OUTPUT"
      AVAILABLE_SPACE=$(df -B 1 "$OUTPUT_DIR" | awk 'NR==2{print $4}')
      if [ ! "$AVAILABLE_SPACE" -ge "$INPUT_SIZE" ]; then
        echo "Fehler: Nicht genügend Speicherplatz vorhanden für $INPUT_FILE_BASENAME in $OUTPUT_DIR ."
        exit 1
      fi
      ;;
  esac
else
  # Wenn OUTPUT eine Datei ist (die nicht exitiert), prüfen, ob genügend freier Speicherplatz vorhanden ist.
  OUTPUT_DIR=$(dirname "$OUTPUT")
  OUTPUT_FILE="$OUTPUT"
  AVAILABLE_SPACE=$(df -B 1 "$OUTPUT_DIR" | awk 'NR==2{print $4}')
    if [ ! "$AVAILABLE_SPACE" -ge "$INPUT_SIZE" ]; then
      echo "Fehler: Nicht genügend Speicherplatz vorhanden für $INPUT_FILE_BASENAME in $OUTPUT_DIR ."
      exit 1
    fi
  if [ -w "$OUTPUT_DIR" ]; then
    touch $OUTPUT
  else
    echo "Kein Schreibzugriff auf das Verzeichnis $OUTPUT_DIR vorhanden."
  fi

fi

echo "Nachfolgend werden die geteilten Dateien unter $INPUT_PATH/$INPUT_FILE_BASENAME nach $OUTPUT_FILE geschrieben."
while true; do
  read -p "Möchten Sie fortfahren [y/N]? " choice
  case "$choice" in
    y|Y)
      echo "Beginning to restore ..."
      restore_split_image
      break
      ;;
    n|N|"")
      echo "Abbruch."
      # Fügen Sie hier den Code hinzu, der bei "Nein" ausgeführt werden soll
      exit 0
      ;;
    *)
      echo "Ungültige Eingabe. Bitte wählen Sie 'y' oder 'N'."
      ;;
  esac
done

#if [[ "$INPUT_FILE_TYPE" == "block special"* ]] && [[ "$OUTPUT_FILE_TYPE" == "block special"* ]]; then
#  echo "Beginning to restore ..."
#  restore_split_image
#else
#  echo "Input File Type ($INPUT_FILE_TYPE) stimmt nicht mit Output File Type ($OUTPUT_FILE_TYPE) überein."
#fi
#if [[ "$INPUT_FILE_TYPE" != "block special"* ]] && [[ "$OUTPUT_FILE_TYPE" != "block special"* ]]; then
#  echo "Beginning to restore ..."
#  restore_split_image
#else
#  echo "Input File Type ($INPUT_FILE_TYPE) stimmt nicht mit Output File Type ($OUTPUT_FILE_TYPE) überein."
#fi
wait

