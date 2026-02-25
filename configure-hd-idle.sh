#!/bin/bash
# ============================================================
# Configurazione interattiva hd-idle
# Eseguire dopo nas-setup.sh per configurare lo spindown HDD
# ============================================================

set -e

echo ""
echo "======================================================"
echo " Configurazione hd-idle - spindown automatico HDD"
echo "======================================================"
echo ""

# Mostra i dischi disponibili
echo "Dischi disponibili nel sistema:"
echo ""
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | awk 'NR==1 || ($3=="disk" && $1 ~ /^sd/)'
echo ""

# Chiede il timeout di default
read -rp "Timeout di spindown in secondi (default: 600): " TIMEOUT
TIMEOUT=${TIMEOUT:-600}

# Chiede i dischi da includere
echo ""
echo "Inserisci i dischi da gestire con hd-idle (es: sda sdb sdc)"
echo "Lascia vuoto per rilevare automaticamente tutti i dischi di tipo 'disk' non di sistema"
read -rp "Dischi: " DISCHI_INPUT

# Determina i dischi
if [ -z "$DISCHI_INPUT" ]; then
    # Rileva automaticamente solo i dischi sd* (esclude mmcblk, zram, loop ecc.)
    DISCHI=$(lsblk -o NAME,TYPE | awk '$2=="disk" && $1 ~ /^sd/ {print $1}')
    echo ""
    echo "Dischi rilevati automaticamente: $DISCHI"
else
    DISCHI=$DISCHI_INPUT
fi

# Costruisce la stringa HD_IDLE_OPTS
OPTS="-i 0"
for DISCO in $DISCHI; do
    OPTS="$OPTS -a $DISCO -i $TIMEOUT -c ata"
done

echo ""
echo "Configurazione che verrà scritta:"
echo "HD_IDLE_OPTS=\"$OPTS\""
echo ""
read -rp "Confermi? [s/N]: " CONFERMA

if [[ ! "$CONFERMA" =~ ^[sS]$ ]]; then
    echo "Operazione annullata."
    exit 0
fi

# Abilita hd-idle e scrive la configurazione
sudo sed -i 's/START_HD_IDLE=false/START_HD_IDLE=true/' /etc/default/hd-idle

# Rimuove eventuali righe HD_IDLE_OPTS precedenti e aggiunge la nuova
sudo sed -i '/^HD_IDLE_OPTS/d' /etc/default/hd-idle
echo "HD_IDLE_OPTS=\"$OPTS\"" | sudo tee -a /etc/default/hd-idle > /dev/null

# Riavvia hd-idle
sudo systemctl enable --now hd-idle.service
sudo systemctl restart hd-idle.service

echo ""
echo "======================================================"
echo " hd-idle configurato!"
echo "======================================================"
echo " Dischi:   $DISCHI"
echo " Timeout:  ${TIMEOUT}s"
echo " Comando:  ata (consigliato per bridge USB-SATA)"
echo "======================================================"
echo " Per verificare: sudo hdparm -C /dev/sda"
echo " Per i log:      journalctl -u hd-idle -f"
echo "======================================================"
echo ""
