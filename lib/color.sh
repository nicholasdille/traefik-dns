DEFAULT="\e[39m\e[49m"
LIGHT_GRAY="\e[37m"

DARK_GRAY="\e[90m"
RED="\e[91m"
GREEN="\e[92m"
YELLOW="\e[93m"
BLUE="\e[94m"
MAGENTA="\e[95m"
CYAN="\e[96m"

BG_DARKGRAY="\e[100m"
BG_RED="\e[101m"
BG_GREEN="\e[102m"
BG_YELLOW="\e[103m"
BG_BLUE="\e[104m"
BG_MAGENTA="\e[105m"
BG_CYAN="\e[106m"

function echo_color() {
    local color=$1
    local message=$2

    echo -e "${!color}${message}${DEFAULT}"
}