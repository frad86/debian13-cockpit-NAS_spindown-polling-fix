#!/bin/bash

echo "Sincronizza la password SYSTEM+SAMBA dell'user"
echo "per utilizzare le stesse credenziali utente di sistema in SMB"
echo "Se non c'è l user in SMB lo crea."

read -p "Inserisci il nome utente: " TARGET_USER
echo ""

# Controllo se l'utente esiste nel sistema
if ! id "$TARGET_USER" &>/dev/null; then
    echo "Errore: l'utente '$TARGET_USER' non esiste nel sistema."
    exit 1
fi

read -s -p "Inserisci la nuova password per $TARGET_USER: " PASS1
echo ""
read -s -p "Conferma la nuova password: " PASS2
echo ""

if [ "$PASS1" != "$PASS2" ]; then
    echo "Errore: Le password non coincidono."
    exit 1
fi

# Sistema Linux
echo "$TARGET_USER:$PASS1" | sudo chpasswd
echo "Sistema Linux: password aggiornata."

# Samba
echo -e "$PASS1\n$PASS1" | sudo smbpasswd -a -s "$TARGET_USER"
echo "Samba: password aggiornata."

unset PASS1 PASS2

echo ""
echo "--- OK! Utente sincronizzato (Sistema + Samba) ---"
