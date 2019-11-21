#!/bin/bash


cpu_vulnerabilities_dir=/sys/devices/system/cpu/vulnerabilities

vulnerabilities="spectre_v1 spectre_v2 meltdown spec_store_bypass l1tf mds tsx_async_abort"

#modules="emcp nvidia oracleasm oracleadvm oracleacfs oracleoks vbox"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ret=0

echo "Server model:"
echo -n "  "
dmidecode -s system-product-name 2>/dev/null | tail -1

echo
echo "BIOS version:"
echo -n "  "
biosv=$(dmidecode -s bios-version 2>/dev/null| tail -1)
biosrd=$(dmidecode -s bios-release-date 2>/dev/null | tail -1)
echo "$biosv released on $biosrd"

echo
echo "CPU model name:"
grep "model name" /proc/cpuinfo | tail -1 | sed 's/model name.*://'
#dmidecode -s processor-version | tail -1

echo
echo "Hostname:"
echo -n "  "
hostname

echo
echo "Boot mode:"
echo -n "  "
if [ -d "/sys/firmware/efi" ]; then
    echo "UEFI"
else
    echo "Legacy BIOS"
fi

echo
echo "OS:"
echo -n "  "
if [ -f "/etc/oracle-release" ]; then
    cat /etc/oracle-release
    if grep -q -i "Oracle VM server" /etc/oracle-release; then
        echo -n "  "
        cat /etc/ovs-info | grep build
    fi
elif [ -f "/etc/redhat-release" ]; then
    cat /etc/redhat-release
elif [ -f "/etc/os-release" ]; then
    . /etc/os-release
    echo "$NAME $VERSION"
fi

echo
echo "kernel version:"
echo -n "  "
echo "$(uname -r) ($(grep CONFIG_RETPOLINE /boot/config-$(uname -r)))"

echo
echo "BIOS, FW, microcode_ctl RPM and microcode version:"
echo -n "  "
dmidecode -t bios | grep -i "bios Revision" | sed -e 's/^[ \t]*//'
echo -n "  "
dmidecode -t bios | grep -i "Firmware Revision" | sed -e 's/^[ \t]*//'
if which rpm >/dev/null 2>&1; then
    echo -n "  "
    rpm -q microcode_ctl
fi
echo -n "  "
grep microcode /proc/cpuinfo | tail -1

# gcc
if which gcc >/dev/null 2>&1; then
    echo
    echo "gcc version:"
    echo -n "  "
    if rpm -q gcc >/dev/null 2>&1; then
        rpm -q gcc
    else
        gcc --version | head -1
    fi
fi

#rdmsr
echo
echo "MSR:"
if which rdmsr &>/dev/null; then
    echo "  0x48 MSR value(cpu 0): $(rdmsr 0x48 2>/dev/null) (from rdmsr 0x48)"
    echo "  0x48 MSR value(cpu 1): $(rdmsr -p 1 0x48 2>/dev/null) (rdmsr -p 1 0x48)"
    echo "  0x10a MSR value(cpu 0): $(rdmsr 0x10a 2>/dev/null) (rdmsr 0x10a)"
    echo "  0x10a MSR value(cpu 1): $(rdmsr -p 1 0x10a 2>/dev/null) (rdmsr -p 0x10a)"
else
    echo "  !! Please install msr-tools package. (OL7 from developer_EPEL repo)"
fi

# xen
if rpm -q xen >/dev/null 2>&1; then
    echo
    echo "xen version:"
    echo -n "  "
    rpm -q xen
    echo -n "  "
    xm dmesg | grep -i --color gcc
fi

echo
echo "Mitigation control parameters in /proc/cmdline - spectre_v2, pti, lfence, ibrs, ibpb, retpoline, spec_store_bypass_disable,"
echo "retpoline_modules_only, nosmt, l1tf, kvm-intel.vmentry_l1d_flush, mds, tsx_async_abort, mitigations:"
#cat /proc/cmdline

options="spectre pti lfence ibrs ibpb retp spec_store_bypass_disable nosmt l1tf kvm-intel.vmentry_l1d_flush mds mitigations tsx"

cmdline=$(cat /proc/cmdline)
for p in $cmdline; do
    for o in $options; do
        echo "  $p" | grep -i --color $o
        #echo $p
    done
done

#grep -i spectre_v2 /proc/cmdline
#grep -i nospectre /proc/cmdline
#grep -i ibrs /proc/cmdline
#grep -i ibpb /proc/cmdline
#grep -i pti /proc/cmdline

echo
echo "Mitigation of $vulnerabilities in sysfs $cpu_vulnerabilities_dir/:"
for vulnerability in $vulnerabilities; do
    if [ -f "$cpu_vulnerabilities_dir/$vulnerability" ]; then
        echo -n "  $vulnerability: "
        sysinfo=$(cat $cpu_vulnerabilities_dir/$vulnerability)

        color=$GREEN

        # just simply mark those without "^Mitigation:" or "^Not affected" red
        if echo "$sysinfo" | grep -q -i "^mitigation:" || echo "$sysinfo" | grep -q -i "^Not affected"; then
            color=$GREEN
        else
            color=$RED
            ret=1
        fi
        # if the the sysinfo is "Vulnerable", mark it red
        if [ "$sysinfo" = "Vulnerable" ]; then
            color=$RED
            ret=1
        fi
        echo -e "${color}$sysinfo${NC}"
    fi
done

# debugfs
debug_sysfs_parameters="ibpb_enabled ibrs_enabled retpoline_fallback pti_enabled lfence_enabled retp_enabled retpoline_enabled pti_enabled mds_idle_clear mds_user_clear microcode_loader_version"
debug_sysfs_dir=/sys/kernel/debug/x86
if [ ! -d $debug_sysfs_dir ]; then
    mount -t debugfs nodev /sys/kernel/debug >/dev/null 2>&1
fi
if [ -d $debug_sysfs_dir ]; then
    echo
    echo "Runtime parameter in debug sysfs $debug_sysfs_dir/:"
    for p in $debug_sysfs_parameters; do
        if [ -f $debug_sysfs_dir/$p ]; then
            echo "  $p: $(cat $debug_sysfs_dir/$p)"
        fi
    done
fi

# xen xm info/dmesg
if rpm -q xen >/dev/null 2>&1; then
    echo
    echo "xen cmdline:"
    xm info | grep xen_commandline | sed 's/.*:/  /g'
    echo
    echo "Microcode message in xm dmesg:"
    xm dmesg | grep -i --color microcode
    echo
    echo "Speculative message in xm dmesg:"
    #xm dmesg | grep -i --color retpoline
    xm dmesg | grep -A 3 --color -i spec
fi

echo
echo "SPEC_CTRL(IBRS) in dmesg:"
#dmesg | grep SPEC_CTRL | sed -e 's/^\[.*\]/ /g' | sort -u
#dmesg | grep SPEC_CTRL | sed -e 's/^\[.*\]/ /g'
dmesg | grep -i --color SPEC.CTRL

echo
echo "IBPB in dmesg:"
#dmesg |grep -i "Indirect Branch Prediction Barrier" | sed -e 's/^\[.*\]/ /g'
dmesg |grep -i --color "Indirect Branch Prediction Barrier"

echo
echo "SSBD(spec_store_bypass_disable) in dmesg:"
dmesg | grep -i --color SSBD
dmesg | grep -i --color "Speculative Store Bypass"

echo
echo "Spectre V1 in dmesg:"
dmesg | grep -i --color "Spectre V1"

echo
echo "Spectre V2 in dmesg:"
dmesg | grep -i --color "Spectre V2"

echo
echo "Retpoline and filling RSB in dmesg:"
dmesg | grep -v -i "command line:" | grep -i --color "retpoline"
dmesg | grep -v -i "command line:" | grep -i --color "filling RSB"

echo
echo "L1TF(L1 Terminal Fault) in dmesg:"
dmesg | grep -v -i "command line:" | grep -i --color l1tf

echo
echo "MDS(Microarchitectural Data Sampling) in dmesg:"
dmesg | grep -v -i "command line:" | grep -v nouveau | grep -i --color mds

echo
echo "TAA(TSX Asynchronous Abort) in dmesg:"
dmesg | grep -v -i "command line:" | grep -i --color taa

echo
echo "Other relevant dmesg:"
dmesg | grep -i --color "gcc"

# Today all modules are retpoline enabled, so we no longer log any special module
#for m in $modules; do
#    dmesg | grep -i --color "$m"
#done
dmesg | grep -i --color "vulnerable"

exit $ret
