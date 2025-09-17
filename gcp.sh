#!/bin/bash

# ---------- Colors ----------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD='\033[1m'
RESET="\e[0m"

# ---------- Files ----------
SSH_INFO_FILE="$HOME/.gcp_vm_info"
TERM_KEY_PATH="$HOME/.ssh/termius_vm_key"
ACCOUNTS_JSON="$HOME/accounts.json"

# ---------- Fresh Install ----------
fresh_install() {
    echo -e "${CYAN}${BOLD}Running Fresh Install + CLI Setup...${RESET}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget git unzip python3 python3-pip docker.io jq
    sudo systemctl enable docker --now

    if ! command -v gcloud &> /dev/null
    then
        echo -e "${YELLOW}${BOLD}Gcloud CLI not found. Installing...${RESET}"
        curl https://sdk.cloud.google.com | bash
        exec -l $SHELL
    else
        echo -e "${GREEN}${BOLD}Gcloud CLI already installed.${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Now login to your Google Account:${RESET}"
    gcloud auth login --no-launch-browser
    echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Change Google Account ----------
change_google_account() {
    echo -e "${YELLOW}${BOLD}Logging into a new Google Account...${RESET}"
    gcloud auth login --no-launch-browser
    echo -e "${GREEN}${BOLD}Google Account changed successfully!${RESET}"
    read -p "Press Enter to continue..."
}

# ---------- Auto Project + Billing ----------
auto_create_projects() {
    echo -e "${YELLOW}${BOLD}Creating 3 Projects + Linking Billing...${RESET}"
    billing_id=$(gcloud beta billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    if [ -z "$billing_id" ]; then
        echo -e "${RED}${BOLD}No Billing Account Found!${RESET}"
        return
    fi

    for i in {1..3}; do
        projid="auto-proj-$RANDOM"
        gcloud projects create "$projid" --name="auto-proj-$i" --quiet
        gcloud beta billing projects link "$projid" --billing-account "$billing_id" --quiet
        gcloud services enable compute.googleapis.com --project="$projid" --quiet
        echo -e "${GREEN}Project $projid created & billing linked.${RESET}"
    done
}

# ---------- Auto VM Create (Using accounts.json) ----------
auto_create_vms() {
    auto_create_projects

    if [ ! -f "$ACCOUNTS_JSON" ]; then
        echo -e "${RED}${BOLD}accounts.json not found at $ACCOUNTS_JSON!${RESET}"
        return
    fi

    echo -e "${CYAN}${BOLD}Available Batches in $ACCOUNTS_JSON:${RESET}"
    batches=($(jq -r 'keys_unsorted[]' "$ACCOUNTS_JSON"))
    for i in "${!batches[@]}"; do
        echo "$((i+1))) ${batches[i]}"
    done

    read -p "Select batch number: " batch_num
    batch_index=$((batch_num - 1))
    if [[ $batch_index -lt 0 || $batch_index -ge ${#batches[@]} ]]; then
        echo -e "${RED}${BOLD}Invalid batch selection!${RESET}"
        return
    fi

    batch_name="${batches[$batch_index]}"
    echo -e "${GREEN}${BOLD}Selected batch: $batch_name${RESET}"

    mapfile -t usernames < <(jq -r --arg b "$batch_name" '.[$b][] | .username' "$ACCOUNTS_JSON")
    mapfile -t pubkeys < <(jq -r --arg b "$batch_name" '.[$b][] | .public_key' "$ACCOUNTS_JSON")

    if [ ${#usernames[@]} -ne 9 ] || [ ${#pubkeys[@]} -ne 9 ]; then
        echo -e "${RED}${BOLD}Batch does not contain exactly 9 users!${RESET}"
        return
    fi

    echo -e "${CYAN}${BOLD}Auto-Detected Projects:${RESET}"
    echo -e "${CYAN}${BOLD}Auto-Detected Projects with Billing Enabled:${RESET}"
    billing_id=$(gcloud billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    projects=$(gcloud billing projects list \
        --billing-account="$billing_id" \
        --format="value(projectId)" | head -n 3)

    for PROJECT in $projects; do
        echo "🚀 Enabling Compute Engine API in: $PROJECT"
        gcloud services enable compute.googleapis.com --project="$PROJECT"
    done
    echo "$projects"

    if [ -z "$projects" ]; then
        echo -e "${RED}${BOLD}No projects found in your account! Please create projects first.${RESET}"
        return
    fi

    zone="us-central1-a"
    mtype="e2-custom-4-32768"
    disksize="83"

    count=0
    for proj in $projects; do
        gcloud config set project $proj > /dev/null 2>&1
        echo -e "${CYAN}${BOLD}Switched to Project: $proj${RESET}"
        # Ensure Compute Engine API is enabled
        gcloud services enable compute.googleapis.com --project="$proj" --quiet
        for j in {1..3}; do
            username="${usernames[$count]}"
            pubkey="${pubkeys[$count]}"
            echo -e "${GREEN}${BOLD}Creating VM $username in $proj...${RESET}"
            gcloud compute instances create $username \
                --zone=$zone \
                --machine-type=$mtype \
                --image-family=ubuntu-2404-lts-amd64 \
                --image-project=ubuntu-os-cloud \
                --boot-disk-size=${disksize}GB \
                --boot-disk-type=pd-balanced \
                --metadata ssh-keys="${username}:${pubkey}" \
                --tags=http-server,https-server \
                --quiet
            ((count++))
        done
    done

    echo -e "${GREEN}${BOLD}All 9 VMs Created Successfully Across Projects!${RESET}"
    echo
    show_all_vms
}

# ---------- Show All VMs ----------
show_all_vms() {
    echo -e "\n${YELLOW}${BOLD}================================================="
    echo -e "         🌍 Listing All VMs Across Projects"
    echo -e "=================================================${RESET}\n"

    billing_id=$(gcloud billing accounts list --format="value(ACCOUNT_ID)" | head -n1)
    projects=$(gcloud billing projects list --billing-account="$billing_id" --format="value(projectId)")

    rows=""
    for proj in $projects; do
        vms=$(gcloud compute instances list \
            --project="$proj" \
            --format="csv(name,EXTERNAL_IP)" 2>/dev/null | tail -n +2)

        while IFS=',' read -r name ip; do
            rows+="$proj,$name,${ip:-—}"$'\n'
        done <<< "$vms"
    done

    if [ -z "$rows" ]; then
        echo -e "${RED}${BOLD}❌ No VMs found across any billing-enabled projects.${RESET}"
    else
        echo -e "${CYAN}${BOLD}"
        printf "┌──────┬────────────────────────────┬──────────────────────┬─────────────────────┐\n"
        printf "│ %-4s │ %-26s │ %-20s │ %-19s │\n" "S.No" "PROJECT" "USERNAME" "IP"
        printf "├──────┼────────────────────────────┼──────────────────────┼─────────────────────┤\n"
        i=1
        while IFS=',' read -r proj name ip; do
            [ -z "$proj" ] && continue   # ❌ skip empty line
            printf "│ %-4s │ %-26s │ %-20s │ %-19s │\n" "$i" "$proj" "$name" "$ip"
            ((i++))
        done <<< "$rows"
        printf "└──────┴────────────────────────────┴──────────────────────┴─────────────────────┘\n"
        echo -e "${RESET}"
    fi

    echo -e "\n${GREEN}${BOLD}✅ Finished listing all VMs${RESET}"
    read -p "Press Enter to continue..."
}




# ---------- Show All Projects ----------
show_all_projects() {
    echo -e "${YELLOW}${BOLD}Listing All Projects:${RESET}"
    gcloud projects list --format="table(projectId,name,createTime)"
    read -p "Press Enter to continue..."
}

# ---------- Delete One VM ----------
delete_one_vm() {
    echo -e "${YELLOW}${BOLD}Deleting a Single VM...${RESET}"
    gcloud projects list --format="table(projectId,name)"
    read -p "Enter Project ID: " projid
    gcloud compute instances list --project=$projid --format="table(name,zone,status)"
    read -p "Enter VM Name to delete: " vmname
    zone=$(gcloud compute instances list --project=$projid --filter="name=$vmname" --format="value(zone)")
    if [ -z "$zone" ]; then
        echo -e "${RED}VM not found!${RESET}"
    else
        gcloud compute instances delete $vmname --project=$projid --zone=$zone --quiet
        echo -e "${GREEN}VM $vmname deleted successfully from project $projid.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Auto Delete All VMs ----------
delete_all_vms() {
    echo -e "${RED}${BOLD}Deleting ALL VMs across ALL projects...${RESET}"
    for proj in $(gcloud projects list --format="value(projectId)"); do
        echo -e "${CYAN}${BOLD}Checking Project: $proj${RESET}"
        mapfile -t vms < <(gcloud compute instances list --project=$proj --format="value(name)")
        for vm in "${vms[@]}"; do
            zone=$(gcloud compute instances list --project=$proj --filter="name=$vm" --format="value(zone)")
            gcloud compute instances delete $vm --project=$proj --zone=$zone --quiet
            echo -e "${GREEN}Deleted $vm from $proj${RESET}"
        done
    done
    read -p "Press Enter to continue..."
}

# ---------- Connect VM using Termius Key (unchanged) ----------
connect_vm() {
    if [ ! -f "$TERM_KEY_PATH" ]; then
        echo -e "${YELLOW}Enter path to Termius private key to use for VM connections:${RESET}"
        read keypath
        cp "$keypath" "$TERM_KEY_PATH"
        chmod 600 "$TERM_KEY_PATH"
        echo -e "${GREEN}Termius key saved at $TERM_KEY_PATH${RESET}"
    fi

    echo -e "${YELLOW}${BOLD}Available VMs in current project:${RESET}"
    mapfile -t vms < <(gcloud compute instances list --format="value(name)")
    if [ ${#vms[@]} -eq 0 ]; then
        echo -e "${RED}No VMs found!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    for i in "${!vms[@]}"; do
        echo "$((i+1))) ${vms[$i]}"
    done

    read -p "Select VM to connect [number]: " vmnum
    vmindex=$((vmnum-1))
    if [[ -z "${vms[$vmindex]}" ]]; then
        echo -e "${RED}Invalid selection!${RESET}"
        read -p "Press Enter to continue..."
        return
    fi

    vmname="${vms[$vmindex]}"
    zone=$(gcloud compute instances list --filter="name=$vmname" --format="value(zone)")
    ext_ip=$(gcloud compute instances describe $vmname --zone $zone --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
    ssh_user=$(gcloud compute instances describe $vmname --zone $zone --format="get(metadata.ssh-keys)" | awk -F':' '{print $1}')

    echo "$vmname|$ssh_user|$ext_ip|$TERM_KEY_PATH" > "$SSH_INFO_FILE"

    echo -e "${GREEN}Connecting to $vmname using Termius private key...${RESET}"
    ssh -i "$TERM_KEY_PATH" "$ssh_user@$ext_ip"
    read -p "Press Enter to continue..."
}

# ---------- Disconnect VM ----------
disconnect_vm() {
    if [ -f "$SSH_INFO_FILE" ]; then
        rm "$SSH_INFO_FILE"
        echo -e "${GREEN}VM disconnected and SSH info cleared.${RESET}"
    else
        echo -e "${YELLOW}No active VM session found.${RESET}"
    fi
    read -p "Press Enter to continue..."
}

# ---------- Main Menu ----------
while true; do
    clear
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${CYAN}${BOLD}|                  GCP CLI By Aashish                |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo -e "${YELLOW}${BOLD}| [1] 🛠️ Fresh Install + CLI Setup                   |"
    echo -e "${YELLOW}${BOLD}| [2] 🔄 Change / Login Google Account               |"
    echo -e "${YELLOW}${BOLD}| [3] 📁 Auto Create Projects (3) + Billing Link     |"
    echo -e "${YELLOW}${BOLD}| [4] 🚀 Auto Create 9 VMs (3 per Project)           |"
    echo -e "${YELLOW}${BOLD}| [5] 🌍 Show All VMs Across Projects                |"
    echo -e "${YELLOW}${BOLD}| [6] 📜 Show All Projects                           |"
    echo -e "${YELLOW}${BOLD}| [7] 🔗 Connect VM (Termius Key)                    |"
    echo -e "${YELLOW}${BOLD}| [8] ❌ Disconnect VM                               |"
    echo -e "${YELLOW}${BOLD}| [9] 🗑️ Delete ONE VM                               |"
    echo -e "${YELLOW}${BOLD}| [10] 💣 Delete ALL VMs (ALL Projects)              |"
    echo -e "${YELLOW}${BOLD}| [11] 🚪 Exit                                       |"
    echo -e "${CYAN}${BOLD}+---------------------------------------------------+"
    echo
    read -p "Choose an option [1-11]: " choice

    case $choice in
        1) fresh_install ;;
        2) change_google_account ;;
        3) auto_create_projects ;;
        4) auto_create_vms ;;
        5) show_all_vms ;;
        6) show_all_projects ;;
        7) connect_vm ;;
        8) disconnect_vm ;;
        9) delete_one_vm ;;
        10) delete_all_vms ;;
        11) echo -e "${RED}Exiting...${RESET}" ; exit 0 ;;
        *) echo -e "${RED}Invalid choice!${RESET}" ; read -p "Press Enter to continue..." ;;
    esac
done
