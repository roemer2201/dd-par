#!/bin/bash

# Standardwerte für die Parameter
INPUT_FILE=""
OUTPUT_PATH=""
MODE="clone"
NUM_JOBS="4"
BLOCKSIZEBYTES="1048576"
COMPRESSION=${COMPRESSION:-0}
CHECKSUM=${CHECKSUM:-0}
REMOTE=0
SSH_SOCKET_PATH="/tmp/ssh_mux_%n_%p_%r"


# Hilfemeldung anzeigen
function show_help {
  SCRIPT_NAME=$(basename "$0")
  echo "$SCRIPT_NAME - Ein Bash-Skript zum parallelen Klonen oder Sichern von Blockgeräten oder großen Dateien"
  echo "Verwendung: $SCRIPT_NAME [Optionen]"
  echo ""
  echo "Optionen:"
  echo "-i FILE|DEVICE          Die Eingabedatei"
  echo "-o FILE|DEVICE|PATH     Der Ausgabepfad"
  echo "-m clone|backup         Ziel des Vorgangs (Default: clone)"
  echo "-j NUM                  Die Anzahl der Jobs (Default: 4)"
  echo "-b NUM                  Die Blockgröße in Bytes (Default: 1048576 Bytes (1 MiB))"
  echo "-c [NUM]                Komprimierung anfordern, optional setzt NUM das Kompressionslevel (Default: -6)"
  echo "-s                      Checksumme der einzelnen Teile erstellen"
  echo "-r [lnc]                Remote-Verbindung, nur SSH möglich. Remote-Optionen: siehe unten"
  echo "-R user@host            Angabe des Remote-Host"
  echo "-h                      Diese Hilfe anzeigen"
  echo ""
  echo "Remote-Optionen:"
  echo "n: Standardeinstellung, No encryption, Verbindungsaufbau verschlüsselt, Datenübertragung unverschlüsselt"
  echo "l: Übertragung vollständig verschlüsselt, keine Kompression"
  echo "c: Aktiviert Remote-Kompression, Kompressionsvorgang erfolgt auf der Remote-Maschine"
  echo "   Ist \"-c, --compression\" aktiviert und wird \"-r ...\" ohne \"c\" verwendet, erfolgt die Kompression lokal"
}

function option_analysis {
  # Verwendung von getopts zur Verarbeitung der Optionen
  while getopts ":i:o:m:j:b:c::r::R:sh" opt; do
    case $opt in
      i) INPUT="${OPTARG}";;
      o) OUTPUT="${OPTARG}";;
      m) MODE="${OPTARG}";;
      j) NUM_JOBS="${OPTARG}";;
      b) BLOCKSIZEBYTES="${OPTARG}";;
      c)
        COMPRESSION=1 
        if [[ -n ${OPTARG} ]]; then
          COMPRESSION_LEVEL="${OPTARG}"
        else
          COMPRESSION_LEVEL="6"
        fi
        ;;
      s)
        CHECKSUM=1
        ;;
      r)
        REMOTE=1
        if [[ ${OPTARG} =~ ^[lnc]+$ ]]; then
          REMOTE_MODE="${OPTARG}"
        else
          REMOTE_MODE="l"
        fi
        ;;
      R)
        REMOTE=1
        if [ -n "${OPTARG}" ]; then
          REMOTE_HOST="${OPTARG}"
        fi
        ;;
      h) show_help; exit 1;;
      \?) echo "Ungültige Option: -${OPTARG}";;
    esac
  done
  
  # Überprüfung der erforderlichen Parameter
  if [ -z "${INPUT}" ] || [ -z "${OUTPUT}" ] ; then
    echo "Fehlende Parameter. Bitte geben Sie alle erforderlichen Parameter --input und --output an."
    exit 1
  fi
  }

function establish_ssh_connection {
    local target=$1
    local control_path=$2
    local password=$3

    # Wenn ein Passwort bereitgestellt wird, verwenden Sie es, um sich per SSH zu verbinden.
    if [ -n "$password" ]; then
        if ! which sshpass > /dev/null; then
          echo "Der Befehl \"sshpass\" existiert nicht. Bitte installieren Sie das entsprechende Paket ueber ihren Paketmanager"
          exit 1
        fi
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o ControlMaster=yes -o ControlPersist=yes -S "${control_path}" "${target}" true
    else
        echo "Verbindungsaufbau mit Sockel ${control_path} zu ${target}"
        ssh -o StrictHostKeyChecking=no -o ControlMaster=yes -o ControlPersist=yes -S "${control_path}" "${target}" true
    fi

    return $?
}

function connect_ssh {
    if [ -z "${REMOTE_HOST}" ]; then
        echo "Fehler: Kein Remote-Host angegeben."
        exit 1
    fi

    # Wenn ein Socket bereits existiert und funktioniert, dann frühzeitig aussteigen
    if is_ssh_socket_alive; then
        echo "SSH-Verbindung zu ${REMOTE_HOST} besteht bereits."
        return 0
    fi

    # Prüfen, ob der Host per SSH erreichbar ist
    output=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${REMOTE_HOST} true 2>&1)
    
    # Überprüfung des Exit Codes und der Ausgabe
    if [[ $? -eq 0 ]]; then
        echo "Passwortloser Verbindungsaufbau war erfolgreich."
        establish_ssh_connection "${REMOTE_HOST}" "${SSH_SOCKET_PATH}"
    elif echo "$output" | grep -q "Permission denied"; then
        echo "Host ist erreichbar, aber passwortlose Authentifizierung fehlgeschlagen."
        # Passwort vom Nutzer abfragen
        echo -n "Bitte geben Sie das SSH-Passwort für ${REMOTE_HOST} ein: "
        read -s USER_PASSWORD
        echo

        establish_ssh_connection "${REMOTE_HOST}" "${SSH_SOCKET_PATH}" "$USER_PASSWORD"
        if [ $? -ne 0 ]; then
            echo "Verbindung zu ${REMOTE_HOST} konnte nicht hergestellt werden."
            exit 1
        fi
    else
        echo "Unbekannter Fehler oder Host nicht erreichbar. Ausgabe:"
        echo "$output"
    fi

    echo "SSH-Verbindung zu ${REMOTE_HOST} wurde erfolgreich aufgebaut."
}

function is_ssh_socket_alive {
    # Überprüft, ob ein funktionierender Socket bereits existiert
    ssh -o ControlPath="${SSH_SOCKET_PATH}" -O check "${REMOTE_HOST}" 2>/dev/null
    return $?
}

function execute_remote_command {
    local command=$1

    if [ -z "${command}" ]; then
        echo "Fehler: Kein Befehl zum Ausführen angegeben."
        return 1
    fi

    ssh -S "${SSH_SOCKET_PATH}" "${REMOTE_HOST}" "${command}"
    
    return $?
}

function close_ssh_connection {
    ssh -S "${SSH_SOCKET_PATH}" -O exit "${REMOTE_HOST}"
    if [ $? -ne 0 ]; then
        echo "Warnung: Fehler beim Schließen der SSH-Verbindung zu ${REMOTE_HOST}."
    fi
}

check_commands_availability() {
    local commands=("dd" "nc" "df" "tee" "blockdev" "stat")  # Liste der zu überprüfenden Befehle
    
    if [ "$COMPRESSION" -eq 1 ]; then
        commands+=("gzip")
    fi
    
    if [ "$CHECKSUM" -eq 1 ]; then
        commands+=("sha256sum")
    fi
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Befehl $cmd ist nicht verfügbar."
            return 1  # Exit-Code 1, wenn mindestens ein Befehl nicht verfügbar ist
        fi
    done
    
    return 0  # Exit-Code 0, wenn alle Befehle verfügbar sind
}

function input_analysis {
  # Determine the type of the input file
  echo "Analysiere INPUT"
  INPUT_FILE_TYPE=$(file -b ${INPUT})
  echo "\$INPUT_FILE_TYPE = $INPUT_FILE_TYPE"
  
  # Use the appropriate command to calculate the size of the input file
  if [[ "${INPUT_FILE_TYPE}" == "block special"* ]]; then
    #echo "INPUT_SIZE=$(blockdev --getsize64 $INPUT)"
    INPUT_SIZE=$(blockdev --getsize64 ${INPUT})
    #echo $INPUT_SIZE
  else
    INPUT_SIZE=$(stat -c %s ${INPUT})
    #echo $INPUT_SIZE
  fi
}

function output_analysis {
  # Determine the type of the output file
  echo "Analysiere OUTPUT"
  OUTPUT_FILE_TYPE=$(file -b ${OUTPUT})
  
  # Use the appropriate command to calculate the size of the output file
  echo "\$OUTPUT_FILE_TYPE: ${OUTPUT_FILE_TYPE}"
  if [[ "${OUTPUT_FILE_TYPE}" == "block special"* ]]; then
    echo "OUTPUT_SIZE=$(blockdev --getsize64 $OUTPUT)"
    OUTPUT_SIZE=$(blockdev --getsize64 ${OUTPUT})
    echo "\$OUTPUT_SIZE = $OUTPUT_SIZE"
  else
    OUTPUT_SIZE=$(stat -c %s ${OUTPUT})
    echo "\$OUTPUT_SIZE = $OUTPUT_SIZE"
  fi
}

function size_calculation {
  # Calculate the size of each input split file
  echo "Calculate the size of each input split file"
  SPLIT_SIZE=$((INPUT_SIZE / NUM_JOBS))
  echo "Splitsize: ${SPLIT_SIZE}"
  
  # Check if all sizes have whole numbers
  echo "Check if all sizes have whole numbers"
  if [ $((INPUT_SIZE % NUM_JOBS)) -ne 0 ] || [ $((SPLIT_SIZE % BLOCKSIZEBYTES)) -ne 0 ]; then
    echo "ERROR: The input file size (${INPUT_SIZE}) is not evenly divisible by the number of jobs (${NUM_JOBS}), or the resulting split size is not evenly divisible by defined blocksize in by bytes ($BLOCKSIZEBYTES)."
    # Calculate the next higher usable job number
    echo "Calculate the next higher usable job number"
      for ((i=${NUM_JOBS}; i<$((${NUM_JOBS}**2)); i++)); do
        if [ $((INPUT_SIZE % i)) -eq 0 ] && [ $(( $((INPUT_SIZE / i)) % BLOCKSIZEBYTES)) -eq 0 ]; then
          #echo "i=${i} - ${INPUT_SIZE}/${NUM_JOBS} = $((INPUT_SIZE % i)) - SPLIT_SIZE: $(( $((INPUT_SIZE / i)) % BLOCKSIZEBYTES))"
          echo "INFO: The next higher usable Threadnumber is $i (at same Blocksize of ${BLOCKSIZEBYTES}"
          break
        fi
      done
    # Calculate the next lower usable job number
    echo "Calculate the next lower usable job number"
      for ((i=$NUM_JOBS; i>0; i--)); do
        if [ $((INPUT_SIZE % i)) -eq 0 ] && [ $(( $((INPUT_SIZE / i)) % BLOCKSIZEBYTES)) -eq 0 ]; then
          #echo "i=${i} - ${INPUT_SIZE}/${NUM_JOBS} = $((INPUT_SIZE % i)) - SPLIT_SIZE: $(( $((INPUT_SIZE / i)) % BLOCKSIZEBYTES))"
          echo "INFO: The next lower usable Threadnumber is $i (at same Blocksize of ${BLOCKSIZEBYTES}"
          break
        fi
      done
    # Calculate the next higher usable blocksize number
    echo "Calculate the next higher usable blocksize number"
    for ((i=$BLOCKSIZEBYTES; i<$(($BLOCKSIZEBYTES*4)); i++)); do
      if [ $((INPUT_SIZE % i)) -eq 0 ] && [ $(( $((INPUT_SIZE / i)) % NUM_JOBS)) -eq 0 ]; then
        #echo "i=${i} - ${INPUT_SIZE}/${NUM_JOBS} = $((INPUT_SIZE % i)) - SPLIT_SIZE: $(( $((INPUT_SIZE / i)) % BLOCKSIZEBYTES))"
        echo "INFO: The next higher usable blocksize number is $i (at same number of jobs (${NUM_JOBS}))"
        break
      fi
    done
    # Calculate the next lower usable blocksize number
    echo "Calculate the next lower usable blocksize number"
    for ((i=${BLOCKSIZEBYTES}; i>0; i--)); do
      if [ $((INPUT_SIZE % i)) -eq 0 ] && [ $(( $((INPUT_SIZE / i)) % NUM_JOBS)) -eq 0 ]; then
        #echo "i=${i} - ${INPUT_SIZE}/${NUM_JOBS} = $((INPUT_SIZE % i)) - SPLIT_SIZE: $(( $((INPUT_SIZE / i)) % BLOCKSIZEBYTES))"
        echo "INFO: The next lower usable blocksize number is ${i} (at same number of jobs (${NUM_JOBS}))"
        break
      fi
    done
    exit 1
  else
    echo "All sizes seem even."
  fi
}


################
# Script Start #
################
option_analysis $@
input_analysis
size_calculation
if [ $REMOTE -eq 1 ]; then
  is_ssh_socket_alive
  if [ $? -ne 0 ]; then
    echo "Not yet implemented, please support at https://github.com/roemer2201/ddpar"
    connect_ssh
    # check_commands_availability, auf local und remote ausführen
    # Variablen übergeben, zB. $COMPRESSION usw.
  fi    
fi
check_commands_availability
output_analysis # ggf. auf remote ausführen


echo "Initialisierung erfolgreich"

# Modus analysieren

case $MODE in
    "clone")
        echo "Prüfe Klon-Parameter."
        if (( INPUT_SIZE <= OUTPUT_SIZE )); then
            if [[ "${INPUT_TYPE}" != "block special"* ]]; then
                echo "Fehler: Ungültige Eingabe-Typ. Erforderlich: block special. Nur Block-Geräte können geklont werden."
                # Hier kannst du den Code für den Fehlerfall des Eingabe-Typs einfügen
                exit 1
            fi
            
            if [[ "${OUTPUT_TYPE}" != "block special"* ]]; then
                echo "Fehler: Ungültige Ausgabe-Typ. Erforderlich: block special. Beim Klonen muss das Ziel ebenfalls ein Block-Gerät sein"
                # Hier kannst du den Code für den Fehlerfall des Ausgabe-Typs einfügen
                exit 1
            fi
            
            echo "Klonvorgang kann durchgeführt werden."
            # Hier kannst du den Code für den Klonvorgang einfügen
            echo "ToDo: Klonvorgang programmieren."
        else
            echo "Fehler: Eingabegröße (${INPUT_SIZE}) ist größer als Ausgabegröße (${OUTPUT_SIZE}). Bitte stelle ein anderes Zielgerät bereit."
            # Hier kannst du den Code für den Fehlerfall des Größenverhältnisses einfügen
            exit 1
        fi
        ;;
    "backup")
        if [[ "${OUTPUT_FILE_TYPE}" != *"directory"* ]]; then
            echo "Fehler: Ungültiger Ausgabe-Typ ${OUTPUT_FILE_TYPE}. Erforderlich: directory."
            # Hier kannst du den Code für den Fehlerfall des Ausgabe-Typs einfügen
            exit 1
        fi
        # Freier Speicher im Zielpfad analysieren
        FREE_SPACE=$(df -P -B 1 "${OUTPUT}" | awk 'NR==2 {print $4}')
        if (( INPUT_SIZE > FREE_SPACE )); then
            echo "Fehler: Eingabegröße (${INPUT_SIZE}) überschreitet den verfügbaren Speicherplatz (${FREE_SPACE})."
            # Hier kannst du den Code für den Fehlerfall des Speicherplatzes einfügen
            exit 1
        fi
        
        echo "Führe die Backup-Aktion durch."

        # generate further spinoff variables
        INPUT_FILE_NAME=$(basename "${INPUT}")
        OUTPUT_FILE_NAME=${INPUT_FILE_NAME}
        OUTPUT_FILE="${OUTPUT}/${OUTPUT_FILE_NAME}-"
        METADATA_FILE="${OUTPUT_FILE}metadata.txt"
        
        # Write metadata file
        if [ -f ${METADATA_FILE} ]; then
            echo "Metadatafile already exists, copying it to ${METADATA_FILE}.old"
            cp -p ${METADATA_FILE} ${METADATA_FILE}.old
            cat /dev/null > ${METADATA_FILE}
        fi

        echo "NUM_JOBS=${NUM_JOBS}" >> ${METADATA_FILE}
        echo "FILE_NAME=${INPUT_FILE_NAME}" >> ${METADATA_FILE}
        echo "BLOCKSIZEBYTES=${BLOCKSIZEBYTES}" >> ${METADATA_FILE}
        echo "INPUT_SIZE=${INPUT_SIZE}" >> ${METADATA_FILE}
        echo "INPUT_FILE_NAME=${INPUT_FILE_NAME}" >> ${METADATA_FILE}
        echo "FILE_TYPE=${INPUT_FILE_TYPE}" >> ${METADATA_FILE}
        
        # Write to metadata file
        echo "SPLIT_SIZE=${SPLIT_SIZE}" >> ${METADATA_FILE}
        
        echo "Starte die Prozesse ..."
        for ((PART_NUM=0; PART_NUM<${NUM_JOBS}; PART_NUM++)); do

        # Build individual subcommands and concatinate, if enabled
        INPUT_CMD="dd if=${INPUT} bs=${BLOCKSIZEBYTES} count=$((SPLIT_SIZE / ${BLOCKSIZEBYTES})) skip=$((START / ${BLOCKSIZEBYTES}))"
        FULL_CMD="${INPUT_CMD}"
        if [ $CHECKSUM -eq 1 ]; then
          CHECKSUM_CMD="tee >(sha256sum > ${OUTPUT_FILE}${PART_NUM}.sha256)"
          FULL_CMD="${FULL_CMD} | $CHECKSUM_CMD"
        fi
        if [ $COMPRESSION -eq 1 ]; then
          COMPRESSION_CMD="gzip -${COMPRESSION_LEVEL} > ${OUTPUT_FILE}${PART_NUM}.gz"
          FULL_CMD="${FULL_CMD} | $COMPRESSION_CMD &"
        else
          OUTPUT_CMD="dd of=${OUTPUT_FILE}${PART_NUM}.part bs=${BLOCKSIZEBYTES}"
          FULL_CMD="${FULL_CMD} | $OUTPUT_CMD &"
        fi

          echo "$FULL_CMD"
          eval $FULL_CMD
        done
        
        
        ## Run `dd` in parallel to copy each split file and compress the output with gzip
        ## The following lines were used in the past, when the full command was not dynamically build
        #for ((PART_NUM=0; PART_NUM<${NUM_JOBS}; PART_NUM++)); do
        #  START=$((PART_NUM * SPLIT_SIZE))
        #  echo "dd if=${INPUT} bs=${BLOCKSIZEBYTES} count=$((SPLIT_SIZE / ${BLOCKSIZEBYTES})) skip=$((START / ${BLOCKSIZEBYTES})) | tee >(sha256sum > ${OUTPUT_FILE}${PART_NUM}.sha256) | gzip > ${OUTPUT_FILE}${PART_NUM}.gz &"
        #  dd if=${INPUT} bs=${BLOCKSIZEBYTES} count=$((SPLIT_SIZE / ${BLOCKSIZEBYTES})) skip=$((START / ${BLOCKSIZEBYTES})) | tee >(sha256sum > ${OUTPUT_FILE}${PART_NUM}.sha256) | gzip > ${OUTPUT_FILE}${PART_NUM}.gz &
        #done

        # Wait for all jobs to finish
        wait
        ;;
    *)
        echo "Ungültiger Modus: $MODE. Gültige Angaben: clone|backup"
        ;;
esac

if [ $REMOTE -eq 1 ]; then
  close_ssh_connection
fi