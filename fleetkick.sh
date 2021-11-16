#!/bin/bash
: <<'__usage__'

KS_FQPATH: Fully qualified path to kickstart file
ISO_IN: Path to source ISO
ISO_OUT: Path to target ISO
WORKDIR: Path to the directory the source ISO will be exploded into.
REG_FQPATH: Fully qualified path to registration credential file

./fleetkick.sh -k kickstart-stage.ks \
-i /var/lib/libvirt/images/composer-api-d83040bf-b410-4317-9121-1ee7bd726ac1-rhel84-boot.iso \
-o /var/lib/libvirt/images/ksinjected/composer-api-d83040bf-b410-4317-9121-1ee7bd726ac1-rhel84-boot_notefi.iso \
-w /home/root/edgeiso/download98a \
-r fleet_env.bash \
-p isodir/fleet_kspost.txt \
-s isodir/fleet_authkeys.txt

__usage__


# Common log helper
log_msg() {
    LEVEL=$1
    MSG=$2

    timestamp=`date +"%b %d %H:%M:%S"`
    echo "${timestamp} ${FUNCNAME[1]}:${LEVEL}: ${MSG}"
}

# Exit on fatal error
fatal_error() {
    EXIT_CODE=$1
    MSG=$2

    timestamp=`date +"%b %d %H:%M:%S"`
    echo "${timestamp} ${FUNCNAME[1]}:FATAL: ${MSG}" >&2

    exit $EXIT_CODE
}


# Get the volume ID from the original ISO
get_iso_volid() {
    ISO=$1

    [[ -e "$ISO" ]] && volid=`isoinfo -d -i "$ISO" | grep "Volume id:" | awk -F': ' '{print $2}'` \
        || fatal_error 1 "No ISO file $ISO"
    echo $volid
}


# Validate the kickstart file before injection
validate_kickstart() {
    KS=$1

    log_msg INFO "Validating kickstart $KS"

    ksvalidator -v RHEL8 "$KS" && return 0 || fatal_error 1 "Kickstart $KS failed validation"
}


# Explode the ISO into a directory
explode_iso() {
    ISO=$1
    DIR=$2

    # Leaving this alternate 7z command here for reference...
    #[[ -e $ISO ]] && 7z x $ISO -o${DIR} || fatal_error 1 "No ISO file $ISO"
    [[ -e "$ISO" ]] && xorriso -osirrox on -indev "$ISO" -extract / $DIR
}


# Copy the kickstart file into the exploded ISO directory
insert_kickstart() {
    KS=$1
    DEST=$2

    echo;echo
    log_msg INFO "Copying kickstart file $KS to $DEST"
    [[ -e "$KS" ]] && cp "$KS" $DEST || fatal_error 1 "Kickstart file insertion failed"
    #cat $DEST
}


# Copy a file into the exploded ISO directory
insert_file() {
    SOURCE=$1
    DEST=$2

    echo;echo
    log_msg INFO "Copying file $SOURCE to $DEST"
    [[ -e "$SOURCE" ]] && cp "$SOURCE" "$DEST" || fatal_error 1 "File insertion $SOURCE to $DEST failed"
}


# Insert the kickstart path into the EFI or isolinux boot config
edit_bootconfig() {
    CONFIG=$1
    VOLID=$2
    KICKFILE=$3

    [[ -e $CONFIG ]] && file $CONFIG || fatal_error 1 "Boot config $CONFIG file does not exist"

    #sed -i "/rescue/n;/LABEL=${VOLID}/ s/$/ inst.ks=hd:LABEL=${VOLID}:\/${KICKFILE} None/" $CONFIG
    # Replace an existing inst.ks instruction
    sed -i "/rescue/n;/LABEL=${VOLID}/ s/\<inst.ks[^ ]*//g" $CONFIG
    # Replace an existing inst.ks instruction
    sed -i "/rescue/n;/LABEL=${VOLID}/ s/\<inst.ks[^ ]*/inst.ks=hd:LABEL=${VOLID}:\/${KICKFILE} None/g" $CONFIG
    # Inject an inst.ks instruction
    sed -i "/inst.ks=/n;/rescue/n;/LABEL=${VOLID}/ s/$/ inst.ks=hd:LABEL=${VOLID}:\/${KICKFILE} None/g" $CONFIG
    grep $VOLID $CONFIG
}


# Inject the EFI boot config into the EFI boot image
modify_efiboot_image() {
    CONFIG=$1
    IMAGE=$2

    mtype -i $IMAGE ::EFI/BOOT/grub.cfg | grep linuxefi
    mcopy -o -i $IMAGE $CONFIG ::EFI/BOOT/grub.cfg
    mtype -i $IMAGE ::EFI/BOOT/grub.cfg | grep linuxefi
}


# DEPRECATED: replaced by the grub injection via msdos tools
regen_efi_image() {
    EFI_IN=$1
    EFI_OUT=$2

    [[ -e $EFI_IN ]] && mkefiboot --label=ANACONDA --debug $EFI_IN $EFI_OUT \
         || fatal_error 1 "mkefiboot for $EFI_IN $EFI_OUT failed"
}


# Generate the new ISO
make_the_iso() {
    MKISODIR=$1
    ISOPATH=$2
    VOLUME_ID=$3

    cd $MKISODIR

    genisoimage -o "$ISOPATH" -R -J \
-V "${VOLUME_ID}" \
-A "${VOLUME_ID}" \
-volset "${VOLUME_ID}" \
-b isolinux/isolinux.bin \
-c isolinux/boot.cat \
-boot-load-size 4 \
-boot-info-table \
-no-emul-boot \
-verbose \
-debug \
-eltorito-alt-boot \
-e images/efiboot.img -no-emul-boot .
}


# Make the ISO bootable for EFI and non-EFI systems
hybridify() {
    ISOPATH=$1

    [[ -e "$ISOPATH" ]] && isohybrid --uefi "$ISOPATH" || fatal_error 1 "${ISOPATH} does not exist"
}


# Update md5 for the ISO
implant_md5() {
    ISOPATH=$1

    [[ -e "$ISOPATH" ]] && implantisomd5 "$ISOPATH" || fatal_error 1 "${ISOPATH} does not exist"
}


# Inject custom post into kickstart file
inject_custom_post() {
    POST_FILE=$1
    KS=$2

    log_msg INFO "Injecting $POST_FILE into $KS"
    sed -i -e "/#CUSTOM_POST_HERE/r ${POST_FILE}" $KS
}


# ISO injection constants
declare -r INJECT_ENV_FILE=1
declare -r INJECT_KICKSTART=2
declare -r INJECT_USER=4
declare -r INJECT_KSPOST=8
declare -r INJECT_AUTHKEYS=16

function main() {

    inject_files=0
    while getopts 'k:i:o:w:r:p:u:s:' OPTION
    do
        case "$OPTION" in
            k)
                # Kicktstart file
                KS_FQPATH="$OPTARG"
                inject_files=$(( $inject_files | $INJECT_KICKSTART ))
                ;;
            i)
                # Source ISO
                ISO_IN="$OPTARG"
                ;;
            o)
                # Output ISO
                ISO_OUT="$OPTARG"
                ;;
            w)
                # The working directory for ISO explosion
                WORKDIR="$OPTARG"
                ;;
            r)
                # The registration credentials env file
                REG_FQPATH="$OPTARG"
                inject_files=$(( $inject_files | $INJECT_ENV_FILE ))
                ;;
            p)
                # Kickstart post section file
                KS_POST_FILE="$OPTARG"
                inject_files=$(( $inject_files | $INJECT_KSPOST ))
                ;;
            u)
                # Add an admin user
                ADMIN_USER="$OPTARG"
                inject_files=$(( $inject_files | $INJECT_USER ))
                ;;
            s)
                # Inject an authorized_keys file to user specified in -u
                AUTHKEYS_FQPATH="$OPTARG"
                inject_files=$(( $inject_files | $INJECT_AUTHKEYS ))
                ;;
            ?)
                echo "script usage: $(basename \$0) [-k ksfile] [-i input ISO] [-o output ISO] [-w wordir path] [-r registration file]" >&2
                exit 1
                ;;
        esac
    done
    shift "$(($OPTIND -1))"

    # Exit if kickstart and env files are not provided
    if [[ -z ${KS_FQPATH+x} ]] && [[ -z ${REG_FQPATH+x} ]]
    then
        fatal_error 1 "No files to inject"
    fi


    # Open up the ISO
    if [ $inject_files -gt 0 ]
    then
        [[ -e "$ISO_IN" ]] || fatal_error 1 "No source ISO file"

        # Get ISO Vol ID  (needed to identify the volume at install)
        VOLID=$(get_iso_volid "$ISO_IN")
        log_msg INFO "The ISO VOLID is $VOLID"

        # Copy the ISO internal contents to a working directory
        explode_iso "$ISO_IN" $WORKDIR
    fi


    # Insert the env file to the root of the working directory
    (( $inject_files & $INJECT_ENV_FILE )) && insert_file "$REG_FQPATH" ${WORKDIR}/fleet_env.bash

    # Insert the authkeys file to the root of the working directory
    (( $inject_files & $INJECT_ENV_FILE )) && insert_file "$AUTHKEYS_FQPATH" ${WORKDIR}/fleet_authkeys.txt

    # Inject the Kickstart file and configure installer boot
    if (( $inject_files & $INJECT_KICKSTART ))
    then
        # Validate the kickstart file
        [[ -e "$KS_FQPATH" ]] || fatal_error 1 "No kickstart file"
        #inject_custom_post /isodir/fleet_kspost.txt $"KS_FQPATH"
        validate_kickstart "$KS_FQPATH" || fatal_error 1 "Kickstart file is not valid"

        ISOCFG="${WORKDIR}/isolinux/isolinux.cfg"
        EFICFG="${WORKDIR}/EFI/BOOT/grub.cfg"
        EFI_DIR="${WORKDIR}/EFI/BOOT"
        EFI_IMAGEPATH="${WORKDIR}/images/efiboot.img"
        KSFILE=fleet.ks
        #KSFILE=`basename "$KS_FQPATH"`
        #KSFILE=`basename ${KS_FQPATH// /_}`

        echo "KS_FQPATH: ${KS_FQPATH}"
        echo "ISO IN: ${ISO_IN}"
        echo "ISO OUT: ${ISO_OUT}"
        echo "WORKDIR: ${WORKDIR}"
        echo "REG_FQPATH: ${REG_FQPATH}"

        echo "ISOCFG: ${ISOCFG}"
        echo "EFICFG: ${EFICFG}"
        echo "KSFILE: ${KSFILE}"

        insert_file "$KS_FQPATH" ${WORKDIR}/${KSFILE}
        #insert_file "$KS_FQPATH" ${WORKDIR}/finalKickstart-fleetmgmt.ks

        # Edit boot files to point to the Kickstart file
        edit_bootconfig $ISOCFG $VOLID "$KSFILE"
        edit_bootconfig $EFICFG $VOLID "$KSFILE"

        # IT IS NO LONGER NECESSARY TO REGEN THE EFI IMAGE
        #   WE INJECT THE FILES INTO THE MSDOS IMAGE IN PLACE
        #regen_efi_image $EFI_DIR $EFI_IMAGEPATH
        modify_efiboot_image $EFICFG $EFI_IMAGEPATH
    fi


    # Inject a custom Kickstart post section from file
    #(( $inject_files & $INJECT_KSPOST )) && inject_custom_post $KS_POST_FILE ${WORKDIR}/${KSFILE}
    #validate_kickstart ${WORKDIR}/${KSFILE} || fatal_error 1 "Kickstart file ${WORKDIR}/${KSFILE} is not valid"
    (( $inject_files & $INJECT_KSPOST )) && insert_file "$KS_POST_FILE" ${WORKDIR}/fleet_kspost.txt


    # Close things up
    if [ $inject_files -gt 0 ]
    then
        # Create a new bootable ISO
        make_the_iso $WORKDIR "$ISO_OUT" $VOLID
        # Make it hybrid bootable
        hybridify "$ISO_OUT"
        # Update the internal checksum
        implant_md5 "$ISO_OUT"

        echo
        log_msg INFO "New ISO $ISO_OUT created."
    fi
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi


# FIXME: Error checking and return codes for all functions
# FIXME: Error checking logic for function calls
# FIXME: Usage message
# FIXME: Do we actually need None in the boot line?
# TODO: add main logic
# TODO: add default for ISO OUT
# TODO: add config file (-c) instead of passing all arguments on cli
# TODO: add debug mode
# TODO: add script description to header (mention this does not require root)
