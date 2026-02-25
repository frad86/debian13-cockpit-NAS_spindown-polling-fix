#!/bin/bash
# ============================================================
# Script post-installazione NAS - Debian minimal + Cockpit
# Testato su Odroid H2 - Debian 13 (Trixie)
# ============================================================

set -e  # interrompe lo script in caso di errore

echo "==> Aggiornamento sistema..."
sudo apt update && sudo apt upgrade -y

# ============================================================
# INSTALLAZIONE PACCHETTI
# ============================================================
echo "==> Installazione Cockpit e strumenti NAS..."
sudo apt install -y \
    cockpit \
    cockpit-storaged \
    cockpit-networkmanager \
    cockpit-file-sharing \
    cockpit-identities \
    cockpit-packagekit \
    smartmontools \
    log2ram \
    polkitd \
    btrfs-progs \
    open-iscsi \
    hd-idle \
    zram-tools \
    lvm2

# lvm2: installa automaticamente anche udisks2-lvm2 come dipendenza,
# necessario per evitare errori nei log al boot di udisks2
# udisks2-btrfs NON installato (non necessario su NAS base)

# ============================================================
# DISABILITA POLLING UDISKS2 (causa wakeup casuali dei dischi)
# udisks2 rimane attivo per la sezione Archiviazione di Cockpit,
# ma il polling automatico viene disabilitato su tutti gli HDD
# per permettere lo spindown con hd-idle.
# ============================================================
echo "==> Disabilitazione polling udisks2 e SMART automatico sugli HDD..."
sudo tee /etc/udev/rules.d/69-udisks-no-polling.rules > /dev/null <<'EOF'
# Disabilita il polling e l'accesso SMART automatico per tutti i dischi
# ma li lascia visibili a udisks2/Cockpit
SUBSYSTEM=="block", ENV{ID_TYPE}=="disk", ENV{UDISKS_DISABLE_POLLING}="1", ENV{ID_ATA_SMART_ACCESS}="none"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block

# ============================================================
# SMARTD - non svegliare i dischi se sono in standby
# ============================================================
echo "==> Configurazione smartd per rispettare lo standby..."
# -n standby,15,q dice a smartd di non svegliare i dischi in standby
sudo sed -i 's/^DEVICESCAN.*/DEVICESCAN -n standby,15,q/' /etc/smartd.conf

# ============================================================
# HD-IDLE - spin-down automatico dischi dopo 60 secondi
# ============================================================
echo "==> Configurazione hd-idle (spin-down a 60s)..."
# Configurazione attuale: disabilita globale (-i 0) e imposta 60s per sda/sdb/sdc
# IMPORTANTE: verifica i tuoi dischi con: lsblk -o NAME,MOUNTPOINT
# e modifica /etc/default/hd-idle in base al tuo sistema.
# Esempio alternativo per escludere solo il disco di sistema:
#   HD_IDLE_OPTS="-i 60 -a mmcblk0 -i 0"  (se il sistema è su eMMC)
sudo sed -i 's/START_HD_IDLE=false/START_HD_IDLE=true/' /etc/default/hd-idle
echo 'HD_IDLE_OPTS="-i 0 -a sda -i 60 -c ata -a sdb -i 60 -c ata -a sdc -i 60 -c ata"' | sudo tee -a /etc/default/hd-idle

sudo systemctl enable --now hd-idle.service


# ============================================================
# ZRAM SWAP - swap in RAM, disabilita swap su disco
# ============================================================
echo "==> Configurazione zram swap..."
sudo systemctl enable --now zramswap.service

# Disabilita swap su disco se presente
sudo swapoff -a
# Commenta le righe swap in fstab
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab

# ============================================================
# RIEPILOGO
# ============================================================
echo ""
echo "======================================================"
echo " Setup completato!"
echo "======================================================"
echo " Cockpit:    https://$(hostname -I | awk '{print $1}'):9090"
echo " hd-idle:    spin-down a 60 secondi"
echo " udisks2:    polling disabilitato via udev"
echo " smartd:     non risveglia i dischi in standby"
echo " zram swap:  attivo"
echo "======================================================"
echo " Per verificare wakeup dischi: sudo fatrace -f W"
echo " Per log hd-idle: journalctl -u hd-idle -f"
echo "======================================================"
echo ""
echo " RIAVVIA il sistema per applicare tutte le modifiche!"
echo ""
