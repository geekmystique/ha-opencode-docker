# Wrapper for zigporter: show a clear error when Z2M-dependent commands
# are used without Z2M_URL configured, instead of letting zigporter fail
# with a cryptic ValueError traceback.
zigporter() {
    case "$1" in
        list-z2m|migrate)
            if [ -z "$Z2M_URL" ]; then
                echo "Error: This zigporter command requires Zigbee2MQTT configuration." >&2
                echo "" >&2
                echo "To configure:" >&2
                echo "  Set Z2M_URL to the address you open the Z2M UI on, including the" >&2
                echo "  scheme, for example http://192.168.1.20:8080, then restart the container." >&2
                echo "" >&2
                echo "Commands that work without Z2M: rename-entity, rename-device," >&2
                echo "  inspect, list-devices, stale, fix-device, check, export" >&2
                return 1
            fi
            ;;
    esac
    command zigporter "$@"
}
