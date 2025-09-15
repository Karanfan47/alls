#!/bin/bash
set -euo pipefail

# ---------------- Trap for Ctrl+C ----------------
trap ctrl_c INT

ctrl_c() {
    echo -e "\n${RED}❌ Interrupted by user. Exiting safely...${RESET}"
    read -rp "Press Enter to exit..."
    exit 0
}

# ---------------- Colors ----------------
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"; RESET="\e[0m"; BOLD="\033[1m"

CONFIG_FILE="accounts.json"

ZONE="us-central1-a"
MACHINE_TYPE="e2-custom-4-32768" 
DISK_SIZE="83GB"
IMAGE_FAMILY="ubuntu-2004-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

LOGFILE="output.log"

# Clear old VM list
: > vm_list.txt

# ---------------- Fresh Install + Dependencies ----------------
check_deps() {
    echo -e "${CYAN}${BOLD}Running Fresh Install + CLI Setup...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip jq docker.io
    sudo systemctl enable docker --now

    if ! command -v gcloud &> /dev/null; then
        echo -e "${YELLOW}Gcloud CLI not found. Installing...${RESET}"
        curl -sSL https://sdk.cloud.google.com | bash
        echo -e "${CYAN}⚠️ Please restart your shell or run 'source ~/.bashrc' before re-running this script.${RESET}"
        exit 0
    else
        echo -e "${GREEN}Gcloud CLI already installed.${RESET}"
    fi
}

# ---------------- Project Creation ----------------
create_project() {
    local pname=$1 billing=$2
    local pid="${pname}-$(date +%s)-$RANDOM"

    echo -e "${YELLOW}➡️  Creating project: $pname ($pid)${RESET}" | tee -a "$LOGFILE"

    if gcloud projects describe "$pid" &>/dev/null; then
        echo -e "${CYAN}Project $pid already exists. Skipping.${RESET}" | tee -a "$LOGFILE"
        echo "$pid"; return
    fi

    gcloud projects create "$pid" --name="$pname" >/dev/null
    gcloud beta billing projects link "$pid" --billing-account="$billing" >/dev/null
    gcloud services enable compute.googleapis.com iam.googleapis.com --project="$pid" >/dev/null

    echo "$pid"
}

# ---------------- VM Creation ----------------
create_vm() {
    local vmname=$1 username=$2 sshkey=$3 project_id=$4 project_key=$5 batch=$6

    if gcloud compute instances describe "$vmname" --project="$project_id" --zone="$ZONE" &>/dev/null; then
        echo -e "   • ${CYAN}$username (already exists)${RESET}" | tee -a "$LOGFILE"
        return
    fi

    gcloud compute instances create "$vmname" \
        --project="$project_id" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --image-family="$IMAGE_FAMILY" \
        --image-project="$IMAGE_PROJECT" \
        --boot-disk-size="$DISK_SIZE" \
        --boot-disk-type=pd-balanced \
        --metadata "ssh-keys=$username:$sshkey" \
        --tags=http-server,https-server >/dev/null

    local ip
    ip=$(gcloud compute instances describe "$vmname" --project="$project_id" --zone="$ZONE" \
         --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

    echo -e "   • ${GREEN}$username@$ip${RESET}" | tee -a "$LOGFILE"

    # Save to master file with details
    {
        echo "Batch: $batch"
        echo "Project: $project_id"
        echo "VM: $vmname"
        echo "User: $username"
        echo "IP: $ip"
        echo "---------------------------------------"
    } >> vm_list.txt
}

# ---------------- Batch Creation ----------------
create_batch() {
    local batch=$1
    echo -e "\n${CYAN}${BOLD}========================================"
    echo "   Creating Batch: $batch"
    echo -e "========================================${RESET}\n" | tee -a "$LOGFILE"

    # Auto detect billing account
    local billing_id
    billing_id=$(gcloud beta billing accounts list --format="value(name)" --limit=1)

    if [[ -z "$billing_id" ]]; then
        echo -e "${RED}❌ No billing account found. Please add one in GCP.${RESET}" | tee -a "$LOGFILE"
        exit 1
    fi

    for project_key in $(jq -r ".\"$batch\".projects | keys[]" "$CONFIG_FILE"); do
        local pname="${batch}-${project_key}"
        local project_id
        project_id=$(create_project "$pname" "$billing_id")

        echo -e "\n${GREEN}${BOLD}Project Ready: $project_id${RESET}" | tee -a "$LOGFILE"
        echo -e "${YELLOW}VMs:${RESET}" | tee -a "$LOGFILE"

        while read -r vm; do
            local uname key vmname
            uname=$(echo "$vm" | jq -r '.username')
            key=$(echo "$vm" | jq -r '.public_key')
            vmname="${project_key}-${uname}"

            create_vm "$vmname" "$uname" "$key" "$project_id" "$project_key" "$batch"
        done < <(jq -c ".\"$batch\".projects.\"$project_key\"[]" "$CONFIG_FILE")
    done

    echo -e "\n${CYAN}${BOLD}✅ Batch $batch fully created!${RESET}\n" | tee -a "$LOGFILE"
}

# ---------------- Main Menu ----------------
main_menu() {
    echo -e "${CYAN}${BOLD}+-----------------------------------+${RESET}"
    echo -e "${CYAN}${BOLD}|   GCP Auto Project + VM Manager   |${RESET}"
    echo -e "${CYAN}${BOLD}+-----------------------------------+${RESET}\n"

    local batches
    batches=$(jq -r 'keys[]' "$CONFIG_FILE")
    echo "Available Batches (GCP Accounts):"
    select batch in $batches Exit; do
        case $batch in
            Exit) echo "Bye!"; break ;;
            *) create_batch "$batch"; break ;;
        esac
    done
}

# ---------------- Run ----------------
check_deps

echo -e "${YELLOW}${BOLD}Now login to your Google Account:${RESET}"
gcloud auth login

main_menu

echo -e "\n${CYAN}All tasks completed.${RESET}"
read -rp "Press Enter to exit..."
