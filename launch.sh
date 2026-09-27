#!/bin/sh
set -x
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

echo "$0" "$@"
cd "$PAK_DIR" || exit 1
mkdir -p "$USERDATA_PATH/$PAK_NAME"

architecture=arm
if uname -m | grep -q '64'; then
    architecture=arm64
fi

export PATH="$PAK_DIR/bin/$architecture:$PAK_DIR/bin/$PLATFORM:$PAK_DIR/bin:$PATH"

if [ "$DEVICE" = "rgsp" ]; then
    export RGXX_MODEL="RG34xx"
fi
export LD_LIBRARY_PATH="$PAK_DIR/lib/$architecture:$PAK_DIR/lib/$PLATFORM:$PAK_DIR/lib:$LD_LIBRARY_PATH"
export IMAGE_MATCHER_URL="https://matching-images-is.bittersweet.rip"
export MINUI_IMAGE_WIDTH=300

populate_emus_list() {
    ls -A "$SDCARD_PATH/Roms" 2>/dev/null | grep -v '^\.' | grep '(FBN)' | sort >/tmp/emus.list
}

main_screen() {
    minui_list_file="/tmp/minui-list"
    rm -f "$minui_list_file" "/tmp/minui-output"
    touch "$minui_list_file"

    if [ ! -f "/tmp/emus.list" ]; then
        populate_emus_list
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --disable-auto-sleep --item-key "folders" --file "/tmp/emus.list" --format text --cancel-text "EXIT" --title "Select ROM Folder for map.txt" --write-location /tmp/minui-output --write-value selected 1>&2
}

action_menu() {
    ROM_FOLDER="$1"

    rm -f /tmp/action.list /tmp/action-output

    {
        echo "Use every Dat File"
        echo "Arcade"
        echo "ColecoVision"
        echo "FDS Games"
        echo "Fairchild Channel F Games"
        echo "Game Gear"
        echo "MSX 1 Games"
        echo "Master System"
        echo "Megadrive"
        echo "NES Games"
        echo "NeoGeo Pocket Games"
        echo "Neogeo"
        echo "PC-Engine"
        echo "Sega SG-1000"
        echo "SuprGrafx"
        echo "TurboGrafx16"
        echo "ZX Spectrum Games"
    } >>/tmp/action.list

    killall minui-presenter >/dev/null 2>&1 || true
    minui-list --disable-auto-sleep --item-key "actions" --file "/tmp/action.list" --format text --cancel-text "BACK" --title "Select Dat File for $ROM_FOLDER" --write-location /tmp/action-output --write-value selected 1>&2

    if [ $? -ne 0 ]; then
        return 1
    fi

    return 0
}

generate_map_txt() {
    ROM_FOLDER="$1"
    FBN_DAT_FILE="$2"

    exit_code=0
    if [ "$FBN_DAT_FILE" = "Use every Dat File" ]; then
        show_message "Generating map.txt for $ROM_FOLDER with every dat file" forever
        minui-map-txt-creator -roms "$SDCARD_PATH/Roms/$ROM_FOLDER" -map "$SDCARD_PATH/Roms/$ROM_FOLDER/map.txt" -ignore-tls -all-dats
        exit_code=$?
    else
        show_message "Generating map.txt for $ROM_FOLDER with $FBN_DAT_FILE dat file" forever
        minui-map-txt-creator -roms "$SDCARD_PATH/Roms/$ROM_FOLDER" -map "$SDCARD_PATH/Roms/$ROM_FOLDER/map.txt" -ignore-tls -dat-name "FinalBurn Neo (ClrMame Pro XML, $FBN_DAT_FILE only).dat"
        exit_code=$?
    fi

    if [ $exit_code -ne 0 ]; then
        show_message "Failed to generate map.txt for $ROM_FOLDER" 2
        return $exit_code
    fi

    show_message "Map.txt generated for $ROM_FOLDER" 2
    return 0
}

show_message() {
    message="$1"
    seconds="$2"

    if [ -z "$seconds" ]; then
        seconds="forever"
    fi

    killall minui-presenter >/dev/null 2>&1 || true
    echo "$message" 1>&2
    if [ "$seconds" = "forever" ]; then
        minui-presenter --message "$message" --timeout -1 &
    else
        minui-presenter --message "$message" --timeout "$seconds"
    fi
}

cleanup() {
    rm -f /tmp/stay_awake
    rm -f /tmp/emus.list
    rm -f /tmp/minui-output
    rm -f /tmp/action.list
    rm -f /tmp/action-output
    killall minui-presenter >/dev/null 2>&1 || true
}

main() {
    echo "1" >/tmp/stay_awake
    trap "cleanup" EXIT INT TERM HUP QUIT

    if [ "$PLATFORM" = "tg3040" ] && [ -z "$DEVICE" ]; then
        export DEVICE="brick"
        export PLATFORM="tg5040"
    fi

    allowed_platforms="h700 miyoomini my282 my355 rg35xxplus tg5040 tg5050"
    if ! echo "$allowed_platforms" | grep -q "$PLATFORM"; then
        show_message "$PLATFORM is not a supported platform" 2
        return 1
    fi

    if ! command -v minui-list >/dev/null 2>&1; then
        show_message "minui-list not found" 2
        return 1
    fi

    if ! command -v minui-presenter >/dev/null 2>&1; then
        show_message "minui-presenter not found" 2
        return 1
    fi

    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-list"
    chmod +x "$PAK_DIR/bin/$PLATFORM/minui-presenter"

    while true; do
        main_screen
        exit_code=$?
        # exit codes: 2 = back button, 3 = menu button
        if [ "$exit_code" -ne 0 ]; then
            break
        fi

        selection="$(cat /tmp/minui-output)"
        if [ -z "$selection" ]; then
            show_message "No selection made" forever
            continue
        fi

        # Show action menu
        action_menu "$selection"
        if [ $? -ne 0 ]; then
            continue
        fi

        fbn_dat_file="$(cat /tmp/action-output)"
        generate_map_txt "$selection" "$fbn_dat_file"
    done
}

main "$@"
