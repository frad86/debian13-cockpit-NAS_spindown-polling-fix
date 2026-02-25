# Debian NAS Setup - Debian 13 + Cockpit — Fix: no spindown & continuous polling on HDD

**L'alternativa semplice e solida a OpenMediaVault.**

Dopo anni di OMV ero stanco di dover reinstallare tutto per colpa del `config.xml` che si corrompeva ad ogni minimo cambio di configurazione o di disco. Ho deciso di passare a Debian puro + Cockpit e non torno più indietro.

Script post-installazione per configurare un NAS minimale con **Debian + Cockpit** con spindown automatico degli HDD.

Testato su **Odroid H2** con **Debian 13 (Trixie)**, con dischi USB tramite enclosure **Terramaster D2-320**.

> 💡 **Il fix principale:** se usi dischi collegati tramite **enclosure USB** (Terramaster, Orico e simili) e `hd-idle` non manda mai i dischi in standby nonostante li loggi come spenti — il problema è il comando di default `scsi` che i bridge USB non gestiscono correttamente. La soluzione è usare `-c ata` in `hd-idle`. Vedi la sezione [I problemi](#i-problemi) per tutti i dettagli.

---

## I problemi

Su una installazione Debian con Cockpit, gli HDD non vanno mai in spindown anche se si usa `hd-idle`. I colpevoli sono due:

### 1. udisks2 fa polling continuo sui dischi

udisks2 monitora i dischi in continuazione, svegliandoli ogni volta che stanno per addormentarsi.

**Soluzione:** disabilitare il polling automatico tramite una regola **udev**, senza disabilitare udisks2 stesso:

```
SUBSYSTEM=="block", ENV{ID_TYPE}=="disk", ENV{UDISKS_DISABLE_POLLING}="1", ENV{ID_ATA_SMART_ACCESS}="none"
```

### 2. hd-idle con comando SCSI non funziona su enclosure USB

I bridge USB-SATA (come quelli usati nei NAS Terramaster e simili) non gestiscono correttamente i comandi SCSI passthrough. hd-idle invia il comando di spindown, lo considera riuscito e lo logga — ma il disco in realtà rimane in uno stato intermedio, né acceso né in standby, dal quale non riesce più a tornare in idle autonomamente.

**Soluzione:** usare il comando `-c ata` invece del default `scsi`:

```bash
HD_IDLE_OPTS="-i 0 -a sda -i 60 -c ata -a sdb -i 60 -c ata -a sdc -i 60 -c ata"
```

Il comando ATA usa SAT (SCSI-ATA Translation) che i bridge USB gestiscono correttamente.

---

## Risultato

Con entrambe le soluzioni applicate:

- ✅ Spindown automatico degli HDD funzionante (testato 20+ minuti)
- ✅ Sezione **Archiviazione** di Cockpit funzionante
- ✅ udisks2 attivo per la gestione dei dischi
- ✅ smartd attivo senza svegliare i dischi in standby

---

## Note su Cockpit

La sezione **Archiviazione** ci mette qualche secondo in più del normale ad aprirsi — è una conseguenza del polling disabilitato. udisks2 non ha i dati già pronti e li recupera al momento dell'apertura. Non è un bug.

I dischi collegati tramite bridge USB-SATA potrebbero mostrare **bad sector** nella sezione Archiviazione di Cockpit — si tratta di falsi positivi causati dalla lettura imprecisa degli attributi SMART attraverso il bridge USB. Non indicano problemi reali sui dischi.

---

## Cosa installa lo script

- **Cockpit** + moduli (storaged, networkmanager, file-sharing, identities, packagekit)
- **smartmontools** — monitoraggio salute dischi
- **log2ram** — log in RAM per ridurre scritture su eMMC
- **btrfs-progs** — supporto filesystem BTRFS
- **open-iscsi** — supporto iSCSI
- **hd-idle** — spindown automatico HDD
- **zram-tools** — swap in RAM
- **lvm2** — installa automaticamente anche `udisks2-lvm2` come dipendenza (evita errori nei log al boot)

> **Nota:** udisks2 cerca anche il plugin `libudisks2_iscsi.so` che non esiste come pacchetto separato in Debian. L'errore nei log è innocuo — `open-iscsi` funziona indipendentemente.

---

## Utilizzo

```bash
chmod +x nas-setup.sh
sudo ./nas-setup.sh
```

Dopo l'esecuzione **riavviare il sistema**.

---

## Configurazione hd-idle

Lo script principale configura hd-idle per 3 dischi (sda, sdb, sdc) con spindown a 60 secondi usando il comando ATA. Per una configurazione interattiva e personalizzata è disponibile uno script dedicato:

```bash
chmod +x configure-hd-idle.sh
sudo ./configure-hd-idle.sh
```

Lo script permette di scegliere quali dischi gestire, impostare il timeout di spindown e rilevare automaticamente i dischi disponibili escludendo il disco di sistema.

Prima di eseguire lo script, verifica i tuoi dischi con:

```bash
lsblk -o NAME,MOUNTPOINT
```

Poi modifica `/etc/default/hd-idle` in base al tuo sistema. Esempi:

```bash
# Spindown a 60s per sda, sdb, sdc con comando ATA (consigliato per dischi USB)
HD_IDLE_OPTS="-i 0 -a sda -i 60 -c ata -a sdb -i 60 -c ata -a sdc -i 60 -c ata"

# Alternativa: spindown globale tranne il disco di sistema (es. eMMC)
HD_IDLE_OPTS="-i 60 -c ata -a mmcblk0 -i 0"
```

> **Nota:** il default di hd-idle è `-c scsi`. Sui dischi collegati tramite bridge USB-SATA (enclosure esterne) il comando scsi potrebbe non funzionare correttamente anche se hd-idle non riporta errori. Usare sempre `-c ata` in questi casi.

---

## Diagnostica

```bash
# Verifica stato effettivo del disco (standby = spento, active/idle = acceso)
sudo apt install hdparm
sudo hdparm -C /dev/sda
sudo hdparm -C /dev/sdb

# Verifica se il disco viene acceduto (confronta i numeri a distanza di 30s)
cat /sys/block/sda/stat
sleep 30 && cat /sys/block/sda/stat

# Verifica cosa scrive sui dischi in tempo reale
sudo fatrace | grep -E "sda|sdb|sdc"

# Log hd-idle in tempo reale
journalctl -u hd-idle -f
```

> **Attenzione:** `fatrace` mostra solo i processi che accedono ai dischi tramite il filesystem. Se il disco è sveglio ma `fatrace` non mostra nulla, verificare lo stato con `hdparm -C` e controllare i log di hd-idle.
