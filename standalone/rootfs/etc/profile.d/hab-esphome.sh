# Wrapper for hab: show a clear error when ESPHome commands are used without
# either an HA access token or a direct ESPHome connection configured,
# instead of letting hab fail cryptically.
hab() {
    if [ "$1" = "esphome" ] && [ -z "$HA_ACCESS_TOKEN" ] && [ -z "$ESPHOME_URL" ]; then
        echo "Error: ESPHome tools need either HA_ACCESS_TOKEN or ESPHOME_URL configured." >&2
        echo "" >&2
        echo "Easiest: set ESPHOME_URL to your ESPHome dashboard's own address" >&2
        echo "  (e.g. http://esphome:6052), then restart the container." >&2
        echo "" >&2
        echo "Or set HA_ACCESS_TOKEN (a Long-Lived Access Token from your Home" >&2
        echo "  Assistant profile page), if ESPHome runs as an HA add-on you reach" >&2
        echo "  through Home Assistant Ingress - not the common standalone setup." >&2
        return 1
    fi
    command hab "$@"
}
