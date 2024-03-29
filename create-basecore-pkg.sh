#!/bin/sh

# "debug" shell script
#set -x
if [ "${1}" = "-d" ] ; then
    echo "[DEBUG] debug enabled"
    DEBUG="YES"
    PKG_DEBUG="--debug"
else
    DEBUG="NO"
    PKG_DEBUG=""
fi

DEBUG_PLIST_FILE="allfiles_debug.plist"
DEBUG_ADDBACK_FILE="addback_debug.plist"

if [ -f "basecore.plist" ]; then
    rm basecore.plist
fi

if [ -f "${DEBUG_PLIST_FILE}" ]; then
    rm ${DEBUG_PLIST_FILE}
fi

if [ -f "${DEBUG_ADDBACK_FILE}" ]; then
    rm ${DEBUG_ADDBACK_FILE}
fi

PLIST_TMPFILE=$( mktemp /tmp/plist.XXXXXX )
ADDBACK_TMPFILE=$( mktemp /tmp/addback.XXXXXX )
UCL_TMPFILE=$( mktemp /tmp/ucl.XXXXXX )
BASECORE_TMPFILE=$( mktemp /tmp/basecore.XXXXXX )

SRC_DIR="/usr/src"
REPO_BASE_DIR="/usr/repo/basecore"

LEVEL="best"

## Git
git_revision()
{
    git=$( git -C "${SRC_DIR}" rev-parse --verify --short HEAD 2>/dev/null )
    git_cnt=$( git -C "${SRC_DIR}" rev-list --first-parent --count HEAD 2>/dev/null )
    if [ -n "$git_cnt" ] ; then
        git="n${git_cnt}-g${git}"
    fi

    git_b=$( git -C "${SRC_DIR}" rev-parse --abbrev-ref HEAD )
    if [ -n "$git_b" -a "$git_b" != "HEAD" ] ; then
        git="${git_b}-${git}"
    fi

    echo "${git}" | tr -d '/'
}

write_ucl()
{
cat  <<'EOF' | sed -e "s/%%REVISION%%/${REVISION}/g" > ${UCL_TMPFILE}
name = "FreeBSD-basecore"
origin = "base"
version = "%%REVISION%%"
comment = "FreeBSD minimal Base System for Jails"
categories = [ base ]
maintainer = "mj-mailinglist@gmx.de"
www = "https://www.FreeBSD.org"
prefix = "/"
vital = true
licenselogic = "single"
licenses = [ BSD2CLAUSE ]
desc = <<EOD
FreeBSD minimal Base System for Jails
EOD
scripts: {
    post-install = <<EOD
    ## FROM: runtime.ucl
    pwd_mkdb -i -p -d  ${PKG_ROOTDIR}/etc ${PKG_ROOTDIR}/etc/master.passwd
    services_mkdb -l -q -o ${PKG_ROOTDIR}/var/db/services.db ${PKG_ROOTDIR}/etc/services
    chmod 1777 ${PKG_ROOTDIR}/tmp

    ## FROM: utilities.ucl
    cap_mkdb -l ${PKG_ROOTDIR}/etc/login.conf

    ## FROM: caroot.ucl
    # XXX If pkg picks up a mechanism to detect in the post-install script
    # files being added or removed, we should use it instead to gate the
    # rehash.
    [ -x /usr/sbin/certctl ] && env DESTDIR=${PKG_ROOTDIR} /usr/sbin/certctl rehash
EOD
}
directories: {
    /dev = "y";
    /tmp = "y";
}
EOF
}

#REVISION=$( git -C "${SRC_DIR}" rev-parse --short HEAD )
REVISION=$( git_revision )
LAST_CHANGED_DATE=$( git --no-pager -C "${SRC_DIR}" log -1 --date=short --pretty=format:%cI )
SOURCE_DATE_EPOCH=$( git --no-pager -C "${SRC_DIR}" log -1 --date=short --pretty=format:%ct )

## OS Version Strings
FBSD_VERSION=$( uname -r | cut -c 1-4 )
ABI_VERSION=$( pkg config abi )

WORLDSTAGE_DIR="/usr/obj/usr/src/amd64.amd64/worldstage"
REPO_DIR="${REPO_BASE_DIR}/${ABI_VERSION}/${REVISION}"

# check requirements
if [ ! -d "${REPO_BASE_DIR}" ]; then
  echo "ERROR: Repository directory \"${REPO_BASE_DIR}\" does not exist!"
  exit 1
fi

# FreeBSD 13
PLIST_FILES="acct
             at
             autofs
             bsdinstall
             bsnmp
             caroot
             clibs
             dma
             dpv
             ee
             jail
             lib9p
             libarchive
             libbegemot
             libblocksruntime
             libbsdstat
             libbsdxml
             libbsm
             libbz2
             libcasper
             libcompiler_rt
             libdwarf
             libevent1
             libexecinfo
             libipt
             libldns
             liblzma
             libmagic
             libnetmap
             libopie
             libpathconv
             libregex
             librpcsec_gss
             librss
             libsdp
             libsmb
             libsqlite3
             libstdbuf
             libstdthreads
             libthread_db
             libucl
             libvmmapi
             nfs
             openssl
             quotacheck
             rc
             runtime
             ssh
             unbound
             utilities
             vi
             zoneinfo"

# disable: libcuse libvgl natd pf wpa 

# create a work-plist file from the PLIST_FILES (list see above)
# skipping unwanted files (e.g from -dev, -dbg, -lib32,... packages).
for FILE in ${PLIST_FILES}; do
    if [ -f "${WORLDSTAGE_DIR}/${FILE}.plist" ]; then 
        cat "${WORLDSTAGE_DIR}/${FILE}.plist" >> ${PLIST_TMPFILE}
    fi
done

# add basic language files to tmpfile
cat ${PLIST_TMPFILE} | grep -E "/usr/share/locale($|/C.UTF-8|/C|/en_US.UTF-8)" >> ${ADDBACK_TMPFILE}    # from: utilities.plist
cat ${PLIST_TMPFILE} | grep -E "/usr/share/nls($|/C.UTF-8|/C|/en_US.UTF-8)"    >> ${ADDBACK_TMPFILE}    # from: ee.plist, runtime.plist, utilities.plist
cat ${PLIST_TMPFILE} | grep -E "/usr/share/vi/catalog($|/C|/POSIX|/english)"   >> ${ADDBACK_TMPFILE}    # from: vi.plist

# add misc files to tmpfile
cat ${PLIST_TMPFILE} | grep -E "/usr/share/misc/magic"   >> ${ADDBACK_TMPFILE}
cat ${PLIST_TMPFILE} | grep -E "/usr/share/misc/termcap" >> ${ADDBACK_TMPFILE}

# add some files/symlinks to fix dangling symlinks
# they are in the "wrong" plist file.
# So add them here, until someone reacts to Bug 249143
echo "@(root,wheel,0444,) /usr/lib/libc.so"        >> ${ADDBACK_TMPFILE}    # from: clibs-dev.plist
echo "@(root,wheel,0755,) /usr/lib/libformw.so"    >> ${ADDBACK_TMPFILE}    # from: utilities-dev.plist
echo "@(root,wheel,0755,) /usr/lib/libmenuw.so"    >> ${ADDBACK_TMPFILE}    # from: utilities-dev.plist
echo "@(root,wheel,0755,) /usr/lib/libncursesw.so" >> ${ADDBACK_TMPFILE}    # from: clibs-dev.plist
echo "@(root,wheel,0755,) /usr/lib/libpanelw.so"   >> ${ADDBACK_TMPFILE}    # from: utilities-dev.plist
echo "@(root,wheel,0755,) /usr/lib/libthr.so"      >> ${ADDBACK_TMPFILE}    # from: clibs-dev.plist
echo "@(root,wheel,0755,) /usr/lib/libulog.so"     >> ${ADDBACK_TMPFILE}    # from: utilities-dev.plist

# remove unwanted/unneeded binaries, files and directories
process_plist_file()
{
    # from: runtime.plist
    sed -i '' -e 's#.*/bin/chio$##g'                       ${PLIST_TMPFILE}  # medium changer control utility

    # from: bootloader.plist, bsdinstall.plist, rc.plist, runtime.plist, utilities.plist
    sed -i '' -e 's#.*/boot/.*##g'                         ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/boot$##g'                           ${PLIST_TMPFILE}  # remove directories and files therein

    # from: bsdinstall.plist, utilities.plist
    sed -i '' -e 's#.*/doc/.*##g'                          ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/doc$##g'                            ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/etc/mtree/BSD\.debug\.dist$##g'     ${PLIST_TMPFILE}
    sed -i '' -e 's#.*/etc/mtree/BSD\.lib32\.dist$##g'     ${PLIST_TMPFILE}

    # from: rc.plist
    sed -i '' -e 's#.*/etc/rc.d/kld$##g'                   ${PLIST_TMPFILE}  # Load kernel modules
    sed -i '' -e 's#.*/etc/rc.d/kldxref$##g'               ${PLIST_TMPFILE}  # Generate hints for the kernel loader

    sed -i '' -e 's#.*/etc/rmt$##g'                        ${PLIST_TMPFILE}  # remote magtape protocol module
    sed -i '' -e 's#.*/lib/libbe\..*##g'                   ${PLIST_TMPFILE}  # library for creating, destroying and modifying ZFS boot environments
    sed -i '' -e 's#.*/lib/nvmecontrol/.*##g'              ${PLIST_TMPFILE}  # NVM Express control utility
    sed -i '' -e 's#.*/lib/nvmecontrol$##g'                ${PLIST_TMPFILE}  # NVM Express control utility
    sed -i '' -e 's#.*/sbin/bectl$##g'                     ${PLIST_TMPFILE}  # Utility to manage boot environments on ZFS
    sed -i '' -e 's#.*/sbin/bsdlabel$##g'                  ${PLIST_TMPFILE}  # read and write BSD label
    sed -i '' -e 's#.*/sbin/camcontrol$##g'                ${PLIST_TMPFILE}  # CAM control program
    sed -i '' -e 's#.*/sbin/clri$##g'                      ${PLIST_TMPFILE}  # clear an inode
    sed -i '' -e 's#.*/sbin/comcontrol$##g'                ${PLIST_TMPFILE}  # control a special tty device
    sed -i '' -e 's#.*/sbin/conscontrol$##g'               ${PLIST_TMPFILE}  # control physical console devices
    sed -i '' -e 's#.*/sbin/disklabel$##g'                 ${PLIST_TMPFILE}  # read and write BSD label
    sed -i '' -e 's#.*/sbin/dump$##g'                      ${PLIST_TMPFILE}  # file system backup
    sed -i '' -e 's#.*/sbin/dumpfs$##g'                    ${PLIST_TMPFILE}  # dump UFS file system information
    sed -i '' -e 's#.*/sbin/dumpon$##g'                    ${PLIST_TMPFILE}  # specify a device for crash dumps
    sed -i '' -e 's#.*/sbin/etherswitchcfg$##g'            ${PLIST_TMPFILE}  # configure a built-in Ethernet switch
    sed -i '' -e 's#.*/sbin/fdisk$##g'                     ${PLIST_TMPFILE}  # PC slice table maintenance utility
    sed -i '' -e 's#.*/sbin/ffsinfo$##g'                   ${PLIST_TMPFILE}  # dump all meta information of an existing ufs file system
    sed -i '' -e 's#.*/sbin/fsck_4.2bsd$##g'               ${PLIST_TMPFILE}  # file system consistency check and interactive repair
    sed -i '' -e 's#.*/sbin/fsck_ffs$##g'                  ${PLIST_TMPFILE}  # file system consistency check and interactive repair
    sed -i '' -e 's#.*/sbin/fsck_msdosfs$##g'              ${PLIST_TMPFILE}  # DOS/Windows (FAT) file system consistency checker
    sed -i '' -e 's#.*/sbin/fsck_ufs$##g'                  ${PLIST_TMPFILE}  # file system consistency check and interactive repair
    sed -i '' -e 's#.*/sbin/fsck$##g'                      ${PLIST_TMPFILE}  # file system consistency check and interactive repair
    sed -i '' -e 's#.*/sbin/fsirand$##g'                   ${PLIST_TMPFILE}  # randomize inode generation numbers

    # from: runtime.plist
    sed -i '' -e 's#.*/sbin/gbde$##g'                      ${PLIST_TMPFILE}  # operation and management utility for Geom Based Disk Encryption
    sed -i '' -e 's#.*/sbin/gcache$##g'                    ${PLIST_TMPFILE}  # control utility for CACHE GEOM class
    sed -i '' -e 's#.*/sbin/gconcat$##g'                   ${PLIST_TMPFILE}  # disk concatenation control utility
    sed -i '' -e 's#.*/sbin/geli$##g'                      ${PLIST_TMPFILE}  # control utility for the cryptographic GEOM class
    sed -i '' -e 's#.*/sbin/geom$##g'                      ${PLIST_TMPFILE}  # universal control utility for GEOM classes
    sed -i '' -e 's#.*/sbin/ggatec$##g'                    ${PLIST_TMPFILE}  # GEOM Gate network client and control utility
    sed -i '' -e 's#.*/sbin/ggated$##g'                    ${PLIST_TMPFILE}  # GEOM Gate network daemon
    sed -i '' -e 's#.*/sbin/ggatel$##g'                    ${PLIST_TMPFILE}  # GEOM Gate local control utility
    sed -i '' -e 's#.*/sbin/gjournal$##g'                  ${PLIST_TMPFILE}  # control utility for journaled devices
    sed -i '' -e 's#.*/sbin/glabel$##g'                    ${PLIST_TMPFILE}  # disk labelization control utility
    sed -i '' -e 's#.*/sbin/gmirror$##g'                   ${PLIST_TMPFILE}  # control utility for mirrored devices
    sed -i '' -e 's#.*/sbin/gmountver$##g'                 ${PLIST_TMPFILE}  # control utility for disk mount verification GEOM class
    sed -i '' -e 's#.*/sbin/gmultipath$##g'                ${PLIST_TMPFILE}  # disk multipath control utility
    sed -i '' -e 's#.*/sbin/gnop$##g'                      ${PLIST_TMPFILE}  # control utility for NOP GEOM class
    sed -i '' -e 's#.*/sbin/gpart$##g'                     ${PLIST_TMPFILE}  # control utility for the disk partitioning GEOM class
    sed -i '' -e 's#.*/sbin/graid$##g'                     ${PLIST_TMPFILE}  # control utility for software RAID devices
    sed -i '' -e 's#.*/sbin/graid3$##g'                    ${PLIST_TMPFILE}  # control utility for RAID3 devices
    sed -i '' -e 's#.*/sbin/gsched$##g'                    ${PLIST_TMPFILE}  # control utility for disk scheduler GEOM class
    sed -i '' -e 's#.*/sbin/gshsec$##g'                    ${PLIST_TMPFILE}  # control utility for shared secret devices
    sed -i '' -e 's#.*/sbin/gstripe$##g'                   ${PLIST_TMPFILE}  # control utility for striped devices
    sed -i '' -e 's#.*/sbin/gvinum$##g'                    ${PLIST_TMPFILE}  # Logical Volume Manager control program
    sed -i '' -e 's#.*/sbin/gvirstor$##g'                  ${PLIST_TMPFILE}  # control utility for virtual data storage devices

    # from: runtime.plist
    sed -i '' -e 's#.*/sbin/kldconfig$##g'                 ${PLIST_TMPFILE}  # display or modify the kernel module search path
    sed -i '' -e 's#.*/sbin/kldload$##g'                   ${PLIST_TMPFILE}  # load a file into the kernel
    sed -i '' -e 's#.*/sbin/kldstat$##g'                   ${PLIST_TMPFILE}  # display status of dynamic kernel linker
    sed -i '' -e 's#.*/sbin/kldunload$##g'                 ${PLIST_TMPFILE}  # unload a file from the kernel
    
    # from: runtime.plist
    sed -i '' -e 's#.*/sbin/mount_cd9660$##g'              ${PLIST_TMPFILE}  # mount an ISO-9660 file system
    sed -i '' -e 's#.*/sbin/mount_msdosfs$##g'             ${PLIST_TMPFILE}  # mount an MS-DOS file system
    sed -i '' -e 's#.*/sbin/mount_udf$##g'                 ${PLIST_TMPFILE}  # mount a UDF file system

    sed -i '' -e 's#.*/sbin/newfs_msdos$##g'               ${PLIST_TMPFILE}  # construct a new MS-DOS (FAT) file system
    sed -i '' -e 's#.*/sbin/newfs$##g'                     ${PLIST_TMPFILE}  # construct a new UFS1/UFS2 file system
    sed -i '' -e 's#.*/sbin/nextboot$##g'                  ${PLIST_TMPFILE}  # specify an alternate kernel and boot flags for the next reboot
    sed -i '' -e 's#.*/sbin/nos-tun$##g'                   ${PLIST_TMPFILE}  # implement 'nos' or 'ka9q' style IP over IP tunnel
    sed -i '' -e 's#.*/sbin/nvmecontrol$##g'               ${PLIST_TMPFILE}  # NVM Express control utility
    sed -i '' -e 's#.*/sbin/rdump$##g'                     ${PLIST_TMPFILE}  # file system backup
    sed -i '' -e 's#.*/sbin/recoverdisk$##g'               ${PLIST_TMPFILE}  # recover data from hard disk or optical media
    sed -i '' -e 's#.*/sbin/restore$##g'                   ${PLIST_TMPFILE}  # restore files or file systems from backups made with dump
    sed -i '' -e 's#.*/sbin/rrestore$##g'                  ${PLIST_TMPFILE}  # restore files or file systems from backups made with dump
    sed -i '' -e 's#.*/sbin/swapctl$##g'                   ${PLIST_TMPFILE}  # specify devices for paging and swapping
    sed -i '' -e 's#.*/sbin/swapoff$##g'                   ${PLIST_TMPFILE}  # specify devices for paging and swapping
    sed -i '' -e 's#.*/sbin/swapon$##g'                    ${PLIST_TMPFILE}  # specify devices for paging and swapping
    sed -i '' -e 's#.*/usr/bin/ar$##g'                     ${PLIST_TMPFILE}  # manage archives
    sed -i '' -e 's#.*/usr/bin/byacc$##g'                  ${PLIST_TMPFILE}  # an LALR(1) parser generator
    sed -i '' -e 's#.*/usr/bin/c++filt$##g'                ${PLIST_TMPFILE}  # decode C++ symbols
    sed -i '' -e 's#.*/usr/bin/c89$##g'                    ${PLIST_TMPFILE}  # POSIX.2 C language compiler
    sed -i '' -e 's#.*/usr/bin/c99$##g'                    ${PLIST_TMPFILE}  # standard C language compiler
    sed -i '' -e 's#.*/usr/bin/colldef$##g'                ${PLIST_TMPFILE}  # convert collation sequence source definition
    sed -i '' -e 's#.*/usr/bin/compile_et$##g'             ${PLIST_TMPFILE}  # error table compiler
    sed -i '' -e 's#.*/usr/bin/ctags$##g'                  ${PLIST_TMPFILE}  # create a tags file
    sed -i '' -e 's#.*/usr/bin/ctfconvert$##g'             ${PLIST_TMPFILE}  # convert debug data to CTF data
    sed -i '' -e 's#.*/usr/bin/ctfdump$##g'                ${PLIST_TMPFILE}  # dump the SUNW_ctf section of an ELF file
    sed -i '' -e 's#.*/usr/bin/ctfmerge$##g'               ${PLIST_TMPFILE}  # merge several CTF data sections into one
    sed -i '' -e 's#.*/usr/bin/dtc$##g'                    ${PLIST_TMPFILE}  # device tree compiler
    sed -i '' -e 's#.*/usr/bin/elf2aout$##g'               ${PLIST_TMPFILE}  # Convert ELF binary to a.out format
    sed -i '' -e 's#.*/usr/bin/file2c$##g'                 ${PLIST_TMPFILE}  # convert file to c#source
    sed -i '' -e 's#.*/usr/bin/flex++$##g'                 ${PLIST_TMPFILE}  # fast lexical analyzer generator
    sed -i '' -e 's#.*/usr/bin/flex$##g'                   ${PLIST_TMPFILE}  # fast lexical analyzer generator
    sed -i '' -e 's#.*/usr/bin/fortune$##g'                ${PLIST_TMPFILE}  # print a random, hopefully interesting, adage
    sed -i '' -e 's#.*/usr/bin/ibstat$##g'                 ${PLIST_TMPFILE}  # QUERY BASIC STATUS OF INFINIBAND DEVICE(S)
    sed -i '' -e 's#.*/usr/bin/ibv_asyncwatch$##g'         ${PLIST_TMPFILE}  # display asynchronous events
    sed -i '' -e 's#.*/usr/bin/ibv_devices$##g'            ${PLIST_TMPFILE}  # list RDMA devices
    sed -i '' -e 's#.*/usr/bin/ibv_devinfo$##g'            ${PLIST_TMPFILE}  # query RDMA devices
    sed -i '' -e 's#.*/usr/bin/ibv_rc_pingpong$##g'        ${PLIST_TMPFILE}  # simple InfiniBand RC transport test
    sed -i '' -e 's#.*/usr/bin/ibv_srq_pingpong$##g'       ${PLIST_TMPFILE}  # simple InfiniBand shared receive queue test
    sed -i '' -e 's#.*/usr/bin/ibv_uc_pingpong$##g'        ${PLIST_TMPFILE}  # simple InfiniBand UC transport test
    sed -i '' -e 's#.*/usr/bin/ibv_ud_pingpong$##g'        ${PLIST_TMPFILE}  # simple InfiniBand UD transport test
    sed -i '' -e 's#.*/usr/bin/lex++$##g'                  ${PLIST_TMPFILE}  # fast lexical analyzer generator
    sed -i '' -e 's#.*/usr/bin/lex$##g'                    ${PLIST_TMPFILE}  # fast lexical analyzer generator
    sed -i '' -e 's#.*/usr/bin/man$##g'                    ${PLIST_TMPFILE}  # display online manual documentation pages
    sed -i '' -e 's#.*/usr/bin/mandoc$##g'                 ${PLIST_TMPFILE}  # format manual pages
    sed -i '' -e 's#.*/usr/bin/manpath$##g'                ${PLIST_TMPFILE}  # display search path for manual pages
    sed -i '' -e 's#.*/usr/bin/mckey$##g'                  ${PLIST_TMPFILE}  # RDMA CM multicast setup and simple data transfer test
    sed -i '' -e 's#.*/usr/bin/mesg$##g'                   ${PLIST_TMPFILE}  # display (do not display) messages from other users
    sed -i '' -e 's#.*/usr/bin/mkstr$##g'                  ${PLIST_TMPFILE}  # create an error message file by massaging C source
    sed -i '' -e 's#.*/usr/bin/msgs$##g'                   ${PLIST_TMPFILE}  # system messages and junk mail program
    sed -i '' -e 's#.*/usr/bin/mt$##g'                     ${PLIST_TMPFILE}  # magnetic tape manipulating program
    sed -i '' -e 's#.*/usr/bin/objcopy$##g'                ${PLIST_TMPFILE}  # copy and translate object files
    sed -i '' -e 's#.*/usr/bin/pmcstudy$##g'               ${PLIST_TMPFILE}  # Perform various studies on a system's overall PMCs
    sed -i '' -e 's#.*/usr/bin/ranlib$##g'                 ${PLIST_TMPFILE}  # manage archives
    sed -i '' -e 's#.*/usr/bin/sscop$##g'                  ${PLIST_TMPFILE}  # SSCOP transport protocol
    sed -i '' -e 's#.*/usr/bin/strfile$##g'                ${PLIST_TMPFILE}  # create a random access file for storing strings
    sed -i '' -e 's#.*/usr/bin/tcopy$##g'                  ${PLIST_TMPFILE}  # copy and/or verify mag tapes
    sed -i '' -e 's#.*/usr/bin/ucmatose$##g'               ${PLIST_TMPFILE}  # RDMA CM connection and simple ping#pong test.
    sed -i '' -e 's#.*/usr/bin/udaddy$##g'                 ${PLIST_TMPFILE}  # RDMA CM datagram setup and simple ping#pong test.
    sed -i '' -e 's#.*/usr/bin/unifdef$##g'                ${PLIST_TMPFILE}  # remove preprocessor conditionals from code
    sed -i '' -e 's#.*/usr/bin/unifdefall$##g'             ${PLIST_TMPFILE}  # remove preprocessor conditionals from code
    sed -i '' -e 's#.*/usr/bin/unstr$##g'                  ${PLIST_TMPFILE}  # create a random access file for storing strings
    sed -i '' -e 's#.*/usr/bin/usbhidaction$##g'           ${PLIST_TMPFILE}  # perform actions according to USB HID controls
    sed -i '' -e 's#.*/usr/bin/usbhidctl$##g'              ${PLIST_TMPFILE}  # manipulate USB HID devices
    sed -i '' -e 's#.*/usr/bin/vtfontcvt$##g'              ${PLIST_TMPFILE}  # convert font files for use by the video console
    sed -i '' -e 's#.*/usr/bin/xstr$##g'                   ${PLIST_TMPFILE}  # extract strings from C programs to implement shared strings
    sed -i '' -e 's#.*/usr/bin/yacc$##g'                   ${PLIST_TMPFILE}  # an LALR(1) parser generator
    sed -i '' -e 's#.*/usr/include/.*##g'                  ${PLIST_TMPFILE}

    # from: clibs.plist, utilities.plist
    sed -i '' -e 's#.*/usr/lib/.*\.a$##g'                  ${PLIST_TMPFILE}  # remove .a archive files
    sed -i '' -e 's#.*/usr/lib/clang/.*\.asan.*\.so$##g'   ${PLIST_TMPFILE}  # remove clang adress sanitizer library (only needed for development?)
    sed -i '' -e 's#.*/usr/lib/dtrace.*##g'                ${PLIST_TMPFILE}  # DTrace scripts
    sed -i '' -e 's#.*/usr/lib/libngatm.so.*##g'           ${PLIST_TMPFILE}  # ATM signalling library
    sed -i '' -e 's#.*/usr/lib/libpmc.so.*##g'             ${PLIST_TMPFILE}  # library for accessing hardware performance monitoring counters
    sed -i '' -e 's#.*/usr/lib/libxo/encoder/test.enc$##g' ${PLIST_TMPFILE}
    sed -i '' -e 's#.*/usr/lib32/.*##g'                    ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/lib32$##g'                      ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/libexec/atf-check$##g'          ${PLIST_TMPFILE}  # executes a command and analyzes its results
    sed -i '' -e 's#.*/usr/libexec/atf-sh$##g'             ${PLIST_TMPFILE}  # interpreter for shell-based test programs
    sed -i '' -e 's#.*/usr/libexec/bootpd$##g'             ${PLIST_TMPFILE}  # Internet Boot Protocol server/gateway
    sed -i '' -e 's#.*/usr/libexec/bootpgw$##g'            ${PLIST_TMPFILE}  # Internet Boot Protocol server/gateway
    sed -i '' -e 's#.*/usr/libexec/bsdinstall/.*##g'       ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/libexec/bsdinstall$##g'         ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/libexec/comsat$##g'             ${PLIST_TMPFILE}  # comsat - biff server
    sed -i '' -e 's#.*/usr/libexec/dwatch/.*##g'           ${PLIST_TMPFILE}  # watch processes as they trigger a particular DTrace probe
    sed -i '' -e 's#.*/usr/libexec/dwatch$##g'             ${PLIST_TMPFILE}  # watch processes as they trigger a particular DTrace probe
    sed -i '' -e 's#.*/usr/libexec/hyperv/.*##g'           ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/libexec/hyperv$##g'             ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/libexec/rbootd$##g'             ${PLIST_TMPFILE}  # HP remote boot server
    sed -i '' -e 's#.*/usr/sbin/ancontrol$##g'             ${PLIST_TMPFILE}  # configure Aironet 4500/4800 devices
    sed -i '' -e 's#.*/usr/sbin/binmiscctl$##g'            ${PLIST_TMPFILE}  # manage binary image activators
    sed -i '' -e 's#.*/usr/sbin/boot0cfg$##g'              ${PLIST_TMPFILE}  # boot manager installation/configuration utility
    sed -i '' -e 's#.*/usr/sbin/bootparamd$##g'            ${PLIST_TMPFILE}  # boot parameter server
    sed -i '' -e 's#.*/usr/sbin/bootpef$##g'               ${PLIST_TMPFILE}  # BOOTP Extension File compiler
    sed -i '' -e 's#.*/usr/sbin/bootptest$##g'             ${PLIST_TMPFILE}  # send BOOTP queries and print responses
    sed -i '' -e 's#.*/usr/sbin/btxld$##g'                 ${PLIST_TMPFILE}  # NO MAN PAGE
    sed -i '' -e 's#.*/usr/sbin/callbootd$##g'             ${PLIST_TMPFILE}  # NO MAN PAGE
    sed -i '' -e 's#.*/usr/sbin/camdd$##g'                 ${PLIST_TMPFILE}  # CAM data transfer utility
    sed -i '' -e 's#.*/usr/sbin/cdcontrol$##g'             ${PLIST_TMPFILE}  # compact disc control utility
    sed -i '' -e 's#.*/usr/sbin/ctladm$##g'                ${PLIST_TMPFILE}  # CAM Target Layer control utility
    sed -i '' -e 's#.*/usr/sbin/ctld$##g'                  ${PLIST_TMPFILE}  # CAM Target Layer / iSCSI target daemon
    sed -i '' -e 's#.*/usr/sbin/ctm_dequeue$##g'           ${PLIST_TMPFILE}  # send and receive ctm(1) deltas via mail
    sed -i '' -e 's#.*/usr/sbin/ctm_rmail$##g'             ${PLIST_TMPFILE}  # send and receive ctm(1) deltas via mail
    sed -i '' -e 's#.*/usr/sbin/ctm_smail$##g'             ${PLIST_TMPFILE}  # send and receive ctm(1) deltas via mail
    sed -i '' -e 's#.*/usr/sbin/cxgbetool$##g'             ${PLIST_TMPFILE}  # NO MAN PAGE
    sed -i '' -e 's#.*/usr/sbin/dconschat$##g'             ${PLIST_TMPFILE}  # user interface to dcons(4)
    sed -i '' -e 's#.*/usr/sbin/dumpcis$##g'               ${PLIST_TMPFILE}  # PC Card and Cardbus (PCMCIA) CIS display tool
    sed -i '' -e 's#.*/usr/sbin/dwatch$##g'                ${PLIST_TMPFILE}  # watch processes as they trigger a particular DTrace probe
    sed -i '' -e 's#.*/usr/sbin/editmap$##g'               ${PLIST_TMPFILE}  # query and edit single records in database maps for sendmail
    sed -i '' -e 's#.*/usr/sbin/efibootmgr$##g'            ${PLIST_TMPFILE}  # manipulate the EFI Boot Manager
    sed -i '' -e 's#.*/usr/sbin/efidp$##g'                 ${PLIST_TMPFILE}  # UEFI Device Path manipulation
    sed -i '' -e 's#.*/usr/sbin/efivar$##g'                ${PLIST_TMPFILE}  # UEFI environment variable interaction
    sed -i '' -e 's#.*/usr/sbin/fdcontrol$##g'             ${PLIST_TMPFILE}  # display and modify floppy disk parameters
    sed -i '' -e 's#.*/usr/sbin/fdformat$##g'              ${PLIST_TMPFILE}  # format floppy disks
    sed -i '' -e 's#.*/usr/sbin/fdread$##g'                ${PLIST_TMPFILE}  # read floppy disks
    sed -i '' -e 's#.*/usr/sbin/fdwrite$##g'               ${PLIST_TMPFILE}  # format and write floppy disks
    sed -i '' -e 's#.*/usr/sbin/fwcontrol$##g'             ${PLIST_TMPFILE}  # FireWire control utility
    sed -i '' -e 's#.*/usr/sbin/gpioctl$##g'               ${PLIST_TMPFILE}  # GPIO control utility
    sed -i '' -e 's#.*/usr/sbin/hostapd_cli$##g'           ${PLIST_TMPFILE}  # text-based frontend program for interacting with hostapd(8)
    sed -i '' -e 's#.*/usr/sbin/hostapd$##g'               ${PLIST_TMPFILE}  # authenticator for IEEE 802.11 networks
    sed -i '' -e 's#.*/usr/sbin/hoststat$##g'              ${PLIST_TMPFILE}  # sendmail - an electronic mail transport agent
    sed -i '' -e 's#.*/usr/sbin/hv_kvp_daemon$##g'         ${PLIST_TMPFILE}  # Hyper#V Key Value Pair Daemon
    sed -i '' -e 's#.*/usr/sbin/hv_vss_daemon$##g'         ${PLIST_TMPFILE}  # Hyper#V Volume Shadow Copy Service Daemon
    sed -i '' -e 's#.*/usr/sbin/i2c$##g'                   ${PLIST_TMPFILE}  # test I2C bus and slave devices
    sed -i '' -e 's#.*/usr/sbin/iovctl$##g'                ${PLIST_TMPFILE}  # PCI SR-IOV configuration utility
    sed -i '' -e 's#.*/usr/sbin/kbdcontrol$##g'            ${PLIST_TMPFILE}  # keyboard control and configuration utility
    sed -i '' -e 's#.*/usr/sbin/kbdmap$##g'                ${PLIST_TMPFILE}  # front end for syscons and vt
    sed -i '' -e 's#.*/usr/sbin/kldxref$##g'               ${PLIST_TMPFILE}  # generate hints for the kernel loader
    sed -i '' -e 's#.*/usr/sbin/l2control$##g'             ${PLIST_TMPFILE}  # L2CAP configuration utility
    sed -i '' -e 's#.*/usr/sbin/l2ping$##g'                ${PLIST_TMPFILE}  # send L2CAP ECHO_REQUEST to remote devices
    sed -i '' -e 's#.*/usr/sbin/lptcontrol$##g'            ${PLIST_TMPFILE}  # a utility for manipulating the lpt printer driver
    sed -i '' -e 's#.*/usr/sbin/lptest$##g'                ${PLIST_TMPFILE}  # generate lineprinter ripple pattern
    sed -i '' -e 's#.*/usr/sbin/mailq$##g'                 ${PLIST_TMPFILE}  # sendmail - an electronic mail transport agent
    sed -i '' -e 's#.*/usr/sbin/mailstats$##g'             ${PLIST_TMPFILE}  # display mail statistics
    sed -i '' -e 's#.*/usr/sbin/makemap$##g'               ${PLIST_TMPFILE}  # create database maps for sendmail
    sed -i '' -e 's#.*/usr/sbin/manctl$##g'                ${PLIST_TMPFILE}  # manipulating manual pages
    sed -i '' -e 's#.*/usr/sbin/memcontrol$##g'            ${PLIST_TMPFILE}  # control system cache behaviour with respect to memory
    sed -i '' -e 's#.*/usr/sbin/mfiutil$##g'               ${PLIST_TMPFILE}  # Utility for managing LSI MegaRAID SAS controllers
    sed -i '' -e 's#.*/usr/sbin/mixer$##g'                 ${PLIST_TMPFILE}  # set/display soundcard mixer values
    sed -i '' -e 's#.*/usr/sbin/mlx5tool$##g'              ${PLIST_TMPFILE}  # Utility for managing Connect#X 4/5/6 Mellanox network adapters
    sed -i '' -e 's#.*/usr/sbin/mlxcontrol$##g'            ${PLIST_TMPFILE}  # Mylex DAC#family RAID management utility
    sed -i '' -e 's#.*/usr/sbin/moused$##g'                ${PLIST_TMPFILE}  # pass mouse data to the console driver
    sed -i '' -e 's#.*/usr/sbin/mprutil$##g'               ${PLIST_TMPFILE}  # Utility for managing LSI Fusion#MPT 2/3 controllers
    sed -i '' -e 's#.*/usr/sbin/mpsutil$##g'               ${PLIST_TMPFILE}  # Utility for managing LSI Fusion#MPT 2/3 controllers
    sed -i '' -e 's#.*/usr/sbin/mptable$##g'               ${PLIST_TMPFILE}  # display MP configuration table
    sed -i '' -e 's#.*/usr/sbin/mptutil$##g'               ${PLIST_TMPFILE}  # Utility for managing LSI Fusion#MPT controllers
    sed -i '' -e 's#.*/usr/sbin/ndis_events$##g'           ${PLIST_TMPFILE}  # relay events from ndis(4) drivers to wpa_supplicant(8)
    sed -i '' -e 's#.*/usr/sbin/ndiscvt$##g'               ${PLIST_TMPFILE}  # convert Windows® NDIS drivers for use with FreeBSD
    sed -i '' -e 's#.*/usr/sbin/ndisgen$##g'               ${PLIST_TMPFILE}  # NDIS miniport driver wrapper
    sed -i '' -e 's#.*/usr/sbin/newaliases$##g'            ${PLIST_TMPFILE}  # sendmail - an electronic mail transport agent
    sed -i '' -e 's#.*/usr/sbin/pac$##g'                   ${PLIST_TMPFILE}  # printer/plotter accounting information
    sed -i '' -e 's#.*/usr/sbin/pc-sysinstall$##g'         ${PLIST_TMPFILE}  # System installer backend
    sed -i '' -e 's#.*/usr/sbin/pmc$##g'                   ${PLIST_TMPFILE}  # library for accessing hardware performance monitoring counters
    sed -i '' -e 's#.*/usr/sbin/pmcannotate$##g'           ${PLIST_TMPFILE}  # sources printout with inlined profiling
    sed -i '' -e 's#.*/usr/sbin/pmccontrol$##g'            ${PLIST_TMPFILE}  # control hardware performance monitoring counters
    sed -i '' -e 's#.*/usr/sbin/pmcstat$##g'               ${PLIST_TMPFILE}  # performance measurement with performance monitoring hardware
    sed -i '' -e 's#.*/usr/sbin/ppp$##g'                   ${PLIST_TMPFILE}  # Point to Point Protocol (a.k.a. user#ppp)
    sed -i '' -e 's#.*/usr/sbin/praliases$##g'             ${PLIST_TMPFILE}  # display system mail aliases
    sed -i '' -e 's#.*/usr/sbin/purgestat$##g'             ${PLIST_TMPFILE}  # sendmail - an electronic mail transport agent
    sed -i '' -e 's#.*/usr/sbin/rfcomm_pppd$##g'           ${PLIST_TMPFILE}  # RFCOMM PPP daemon
    sed -i '' -e 's#.*/usr/sbin/rmt$##g'                   ${PLIST_TMPFILE}  # remote magtape protocol module
    sed -i '' -e 's#.*/usr/sbin/sesutil$##g'               ${PLIST_TMPFILE}  # Utility for managing SCSI Enclosure Services (SES) device
    sed -i '' -e 's#.*/usr/sbin/smbmsg$##g'                ${PLIST_TMPFILE}  # send or receive messages over an SMBus
    sed -i '' -e 's#.*/usr/sbin/smtpd$##g'                 ${PLIST_TMPFILE}  # sendmail - an electronic mail transport agent
    sed -i '' -e 's#.*/usr/sbin/spi$##g'                   ${PLIST_TMPFILE}  # communicate on SPI bus with slave devices
    sed -i '' -e 's#.*/usr/sbin/spkrtest$##g'              ${PLIST_TMPFILE}  # test script for the speaker driver
    sed -i '' -e 's#.*/usr/sbin/spray$##g'                 ${PLIST_TMPFILE}  # send many packets to hos
    sed -i '' -e 's#.*/usr/sbin/trpt$##g'                  ${PLIST_TMPFILE}  # transliterate protocol trace
    sed -i '' -e 's#.*/usr/sbin/uathload$##g'              ${PLIST_TMPFILE}  # firmware loader for Atheros USB wireless driver
    sed -i '' -e 's#.*/usr/sbin/uefisign$##g'              ${PLIST_TMPFILE}  # UEFI Secure Boot signing utility
    sed -i '' -e 's#.*/usr/sbin/uhsoctl$##g'               ${PLIST_TMPFILE}  # connection utility for Option based devices
    sed -i '' -e 's#.*/usr/sbin/usbconfig$##g'             ${PLIST_TMPFILE}  # configure the USB subsystem
    sed -i '' -e 's#.*/usr/sbin/usbdump$##g'               ${PLIST_TMPFILE}  # dump traffic on USB host controller
    sed -i '' -e 's#.*/usr/sbin/valectl$##g'               ${PLIST_TMPFILE}  # manage VALE switches provided by netmap
    sed -i '' -e 's#.*/usr/sbin/vidcontrol$##g'            ${PLIST_TMPFILE}  # system console control and configuration utility
    sed -i '' -e 's#.*/usr/sbin/vidfont$##g'               ${PLIST_TMPFILE}  # front end for syscons and vt
    sed -i '' -e 's#.*/usr/sbin/wlandebug$##g'             ${PLIST_TMPFILE}  # set/query 802.11 wireless debugging messages

    # from: rc.plist, runtime.plist
    sed -i '' -e 's#.*/usr/sbin/wpa_cli$##g'               ${PLIST_TMPFILE}  # text#based frontend program for interacting with wpa_supplicant
    sed -i '' -e 's#.*/usr/sbin/wpa_passphrase$##g'        ${PLIST_TMPFILE}  # utility for generating a 256#bit pre#shared WPA key from an ASCII passphrase
    sed -i '' -e 's#.*/usr/sbin/wpa_supplicant$##g'        ${PLIST_TMPFILE}  # WPA/802.11i Supplicant for wireless network devices

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/sbin/zonectl$##g'               ${PLIST_TMPFILE}  # Shingled Magnetic Recording Zone Control utility
    #sed -i '' -e 's#.*/usr/share/atf/.*##g'                ${PLIST_TMPFILE}  # Automated Testing Framework
    #sed -i '' -e 's#.*/usr/share/atf$##g'                  ${PLIST_TMPFILE}  # Automated Testing Framework

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/calendar/.*##g'           ${PLIST_TMPFILE}  # reminder service files and directories
    sed -i '' -e 's#.*/usr/share/calendar$##g'             ${PLIST_TMPFILE}  # reminder service files and directories

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/dict/.*##g'               ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/dict$##g'                 ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/dtrace/.*##g'             ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/dtrace$##g'               ${PLIST_TMPFILE}  # remove directories and files therein

    # from: dma.plist, runtime.plist, utilities.plist
    sed -i '' -e 's#.*/usr/share/examples/.*##g'           ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/examples$##g'             ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/firmware/.*##g'           ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/firmware$##g'             ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/games/.*##g'              ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/games$##g'                ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/locale/.*##g'             ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/locale$##g'               ${PLIST_TMPFILE}  # remove directories and files therein

    # from: at.plist clibs.plist dma.plist ee.plist libarchive.plist libbegemot.plist libbsdxml.plist libbsm.plist,
    # libcasper.plist libdwarf.plist libexecinfo.plist libmagic.plist libopie.plist libpathconv.plist libstdbuf.plist,
    # libstdthreads.plist libucl.plist rc.plist runtime.plist ssh.plist utilities.plist vi.plist
    sed -i '' -e 's#.*/usr/share/man/.*##g'                ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/man$##g'                  ${PLIST_TMPFILE}  # remove directories and files therein

    # from: libmagic.plist, runtime.plist, utilities.plist
    sed -i '' -e 's#.*/usr/share/misc/.*##g'               ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/mk/.*##g'                 ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/mk$##g'                   ${PLIST_TMPFILE}  # remove directories and files therein

    # from: ee.plist, runtime.plist, utilities.plist
    sed -i '' -e 's#.*/usr/share/nls/.*##g'                ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/nls$##g'                  ${PLIST_TMPFILE}  # remove directories and files therein

    # from: runtime.plist, utilities.plist
    sed -i '' -e 's#.*/usr/share/openssl/.*##g'            ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/openssl$##g'              ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/syscons/.*##g'            ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/syscons$##g'              ${PLIST_TMPFILE}  # remove directories and files therein

    # from: vi.plist
    sed -i '' -e 's#.*/usr/share/vi/catalog/.*##g'         ${PLIST_TMPFILE}  # remove directories and files therein

    # from: utilities.plist
    sed -i '' -e 's#.*/usr/share/vt/.*##g'                 ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/share/vt$##g'                   ${PLIST_TMPFILE}  # remove directories and files therein

    # from: ssh.plist, utilities.plist
    sed -i '' -e 's#.*/usr/tests/.*##g'                    ${PLIST_TMPFILE}  # remove directories and files therein
    sed -i '' -e 's#.*/usr/tests$##g'                      ${PLIST_TMPFILE}  # remove directories and files therein

    ### remove freebsd-update files/directories:
    # /var/db/freebsd-update
    # /etc/freebsd-update.conf
    # /usr/sbin/freebsd-update
    # from: utilities.plist
    sed -i '' -e 's#.*freebsd-update.*$##g'                ${PLIST_TMPFILE}

    ### remove ppp files/directories:
    # /etc/rc.d/ppp
    # /etc/rc.d/pppoed
    # /etc/rc.d/sppp
    # /var/run/ppp
    # /etc/newsyslog.conf.d/ppp.conf
    # /etc/ppp
    # /etc/syslog.d/ppp.conf
    # spppcontrol - display or set parameters for an sppp interface
    # pppoed - handle incoming PPP over Ethernet connections
    # from: rc.plist, runtime.plist, utilities.plist
    sed -i '' -e 's#.*ppp.*$##g'                           ${PLIST_TMPFILE}

    ### now remove empty lines
    sed -i '' -e '/^$/d'                                   ${PLIST_TMPFILE}
}

# now do the processing
process_plist_file

# add language files back
cat ${ADDBACK_TMPFILE} >> ${PLIST_TMPFILE}

# remove duplicate lines without sorting the file
awk '! visited[$0]++' ${PLIST_TMPFILE} > ${BASECORE_TMPFILE}

# create the ucl file
write_ucl

# create the minijail package
pkg ${PKG_DEBUG}                                       \
    --option ABI_FILE=${WORLDSTAGE_DIR}/usr/bin/uname  \
    --option ALLOW_BASE_SHLIBS=yes                     \
    create                                             \
    --verbose                                          \
    --timestamp ${SOURCE_DATE_EPOCH}                   \
    --level ${LEVEL}                                   \
    --manifest ${UCL_TMPFILE}                          \
    --plist ${BASECORE_TMPFILE}                        \
    --root-dir ${WORLDSTAGE_DIR}                       \
    --out-dir ${REPO_DIR}

# create the minijail repository
cd ${WORLDSTAGE_DIR}
pkg repo --list-files ${REPO_DIR}

# create "latest" symlink in repository
echo "Creating symlink \"latest\" -> \"${REVISION}\""
cd ${REPO_DIR}/..

# remove symlink if it exists
if [ -L latest ] ; then
    rm latest
fi

ln -s "${REVISION}" latest

if [ ${DEBUG} = "NO" ] ; then
    echo "cleanup temp files"
    rm "${PLIST_TMPFILE}"
    rm "${ADDBACK_TMPFILE}"
    rm "${UCL_TMPFILE}"
    rm "${BASECORE_TMPFILE}"
else
    rm ${PLIST_TMPFILE}
    echo "[DEBUG] plist file:   ${BASECORE_TMPFILE}"
    echo "[DEBUG] addback file: ${ADDBACK_TMPFILE}"
    echo "[DEBUG] ucl file:     ${UCL_TMPFILE}"
fi
