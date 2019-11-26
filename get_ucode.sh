get_cpu_vendor ()
{
    if grep -qE AMD /proc/cpuinfo; then
        printf "AMD"
    fi
    if grep -qE Intel /proc/cpuinfo; then
        printf "Intel"
    fi
}

get_ucode_file ()
{
    local family=`grep -E "cpu family" /proc/cpuinfo | head -1 | sed s/.*:\ //`
    local model=`grep -E "model" /proc/cpuinfo |grep -v name | head -1 | sed s/.*:\ //`
    local stepping=`grep -E "stepping" /proc/cpuinfo | head -1 | sed s/.*:\ //`

    if [[ "$(get_cpu_vendor)" == "AMD" ]]; then
        # If family greater or equal than 0x15
        if [[ $family -ge 21 ]]; then
            printf "microcode_amd_fam15h.bin"
        else
            printf "microcode_amd.bin"
        fi
    fi
    if [[ "$(get_cpu_vendor)" == "Intel" ]]; then
        # The /proc/cpuinfo are in decimal.
        printf "%02x-%02x-%02x" ${family} ${model} ${stepping}
    fi
}

get_ucode_file
