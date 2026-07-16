# ejecutar:
printf '%s:%s\n' \
  "orangepi" \
  "$(printf '%s' 'orangepi' | sha256sum | awk '{print $1}')" \
  | sudo tee /home/orangepi/sdBackup/credentials.txt >/dev/null
  
# echo "orangepi:$(echo -n 'orangepi' | sha256sum | awk '{print $1}')" > /data/credentials.txt
