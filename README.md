# Convert-url-to-yaml
script auto install convert url ke yaml yang terintegrasi langsung di sub menu openclash

# Instalasi
Pastikan anda sudah berada di terminal openwrt, lalu copy perintah di bawah ini :
 ```html
wget -O url-to-yaml.sh https://raw.githubusercontent.com/Elysya28/Convert-url-to-yaml/main/url-to-yaml.sh && sed -i 's/\r$//' url-to-yaml.sh && sed -i '1s/bash/sh/' url-to-yaml.sh && chmod +x url-to-yaml.sh && ./url-to-yaml.sh
 ```
