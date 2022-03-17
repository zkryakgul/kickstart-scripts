# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
LCYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

function err {
    printf "${RED}$@${NC}\n"
}

function success {
    printf "${GREEN}$@${NC}\n"
}

function warn {
    printf "\n>>>>>> ${YELLOW}$@${NC} <<<<<<\n\n"
}

function info {
    printf "${WHITE}$@${NC}\n"
}

function stage {
    printf "\n\n############ ${YELLOW}$@${NC} ############\n\n"
}