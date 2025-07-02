#!/bin/sh

# ======================================================================
# Skrip untuk setup menu "Convert Akun" OpenClash
# VERSI 6 - Menambahkan menu, membuat view .htm, dan membuat file .php
# ======================================================================

# --- Konfigurasi LUA ---
LUA_FILE_PATH="/usr/lib/lua/luci/controller/openclash.lua"
LINE_TO_ADD_LUA='	entry({"admin", "services", "openclash", "converter"},template("openclash/converter"),_("Convert Akun"), 72).leaf = true'
TARGET_LINE=96

# --- Konfigurasi HTML ---
HTML_DIR="/usr/lib/lua/luci/view/openclash"
HTML_FILE_PATH="${HTML_DIR}/converter.htm"

# --- Konfigurasi PHP ---
PHP_DIR="/www"
PHP_FILE_PATH="${PHP_DIR}/converter.php"


#################################
# BAGIAN 1: MODIFIKASI FILE LUA #
#################################
echo "BAGIAN 1: Memodifikasi file openclash.lua..."

# 1. Pastikan file LUA ada
if [ ! -f "$LUA_FILE_PATH" ]; then
    echo "❌ Error: File LUA tidak ditemukan di '$LUA_FILE_PATH'."
    exit 1
fi
echo "✅ File LUA ditemukan."

# 2. Cek apakah baris LUA sudah ada
if grep -Fq "$LINE_TO_ADD_LUA" "$LUA_FILE_PATH"; then
    echo "ℹ️ Info: Baris LUA sudah ada di dalam file. Melanjutkan."
else
    echo "▶️ Membuat backup file LUA ke '$LUA_FILE_PATH.bak'..."
    rm -f "$LUA_FILE_PATH.bak"
    cp "$LUA_FILE_PATH" "$LUA_FILE_PATH.bak"
    echo "▶️ Menyisipkan baris baru di baris ke-$TARGET_LINE..."
    sed -i "${TARGET_LINE}i\\${LINE_TO_ADD_LUA}" "$LUA_FILE_PATH"
    
    # Verifikasi modifikasi LUA
    if grep -Fq "$LINE_TO_ADD_LUA" "$LUA_FILE_PATH"; then
        echo "✅ Sukses! Baris berhasil ditambahkan ke file LUA."
    else
        echo "❌ Error: Gagal menambahkan baris ke file LUA."
        exit 1
    fi
fi

echo "--------------------------------------------------"

#################################
# BAGIAN 2: PEMBUATAN FILE HTML #
#################################
echo "BAGIAN 2: Membuat file converter.htm..."

# 1. Pastikan direktori view ada, jika tidak, buat
if [ ! -d "$HTML_DIR" ]; then
    echo "▶️ Direktori '$HTML_DIR' tidak ditemukan, mencoba membuatnya..."
    mkdir -p "$HTML_DIR"
else
    echo "✅ Direktori '$HTML_DIR' sudah ada."
fi

# 2. Buat atau timpa file htm
echo "▶️ Membuat file '$HTML_FILE_PATH'..."
cat <<'EOF' > "$HTML_FILE_PATH"
<%+header%>
<div class="cbi-map"><br>
<iframe id="converter" style="width: 100%; min-height: 100vh; border: none; border-radius: 2px;"></iframe>
</div>
<script type="text/javascript">
document.getElementById("converter").src = window.location.protocol + "//" + window.location.host + "/converter.php";
</script>
<%+footer%>
EOF

# 3. Verifikasi pembuatan file htm
if [ -f "$HTML_FILE_PATH" ]; then
    echo "✅ File HTML '$HTML_FILE_PATH' berhasil dibuat/diperbarui."
else
    echo "❌ Error: Gagal membuat file HTML."
    exit 1
fi

echo "--------------------------------------------------"

################################
# BAGIAN 3: PEMBUATAN FILE PHP #
################################
echo "BAGIAN 3: Membuat file converter.php..."

# 1. Pastikan direktori /www ada
if [ ! -d "$PHP_DIR" ]; then
    echo "❌ Error: Direktori web root '$PHP_DIR' tidak ditemukan."
    exit 1
fi
echo "✅ Direktori web root '$PHP_DIR' ditemukan."

# 2. Buat file php dengan isinya
echo "▶️ Membuat file '$PHP_FILE_PATH'..."
# Menggunakan 'EOF' untuk mencegah ekspansi variabel shell ($) di dalam kode PHP
cat <<'EOF' > "$PHP_FILE_PATH"
<?php
// ===================================================================
// BAGIAN 1: LOGIKA PHP
// ===================================================================

// Inisialisasi variabel
$yaml_output = '';
$proxy_input = '';

// Fungsi Parser Utama
function convert_to_proxy_data($url) {
    if (strpos($url, '://') === false) {
        if (strpos($url, '@') !== false) {
            if (strpos($url, 'type=') !== false || strpos($url, 'security=') !== false) {
                $url = 'vless://' . $url;
            } else {
                $url = 'trojan://' . $url;
            }
        }
    }
    $scheme = strtolower(parse_url($url, PHP_URL_SCHEME));
    switch ($scheme) {
        case 'trojan': return parse_trojan($url);
        case 'vmess': return parse_vmess($url);
        case 'vless': return parse_vless($url);
        default: return null;
    }
}

// =================================================================================
// >> FUNGSI PARSER TROJAN (DIMODIFIKASI) <<
// =================================================================================
function parse_trojan($url) {
    $parsed_url = parse_url($url);
    if (!$parsed_url || !isset($parsed_url['host']) || !isset($parsed_url['user'])) return null;
    $query_params = [];
    if (isset($parsed_url['query'])) parse_str($parsed_url['query'], $query_params);
    
    // PERUBAHAN DI SINI: Menggunakan nama dari # di link, bukan gabungan user-host
    $name = isset($parsed_url['fragment']) ? urldecode($parsed_url['fragment']) : $parsed_url['host'];
    
    $proxy = [
        'name' => $name, 'server' => $parsed_url['host'], 'port' => $parsed_url['port'] ?? 443,
        'type' => 'trojan', 'password' => $parsed_url['user'],
        'skip-cert-verify' => ($query_params['allowInsecure'] ?? '0') == '1',
        'sni' => $query_params['sni'] ?? $parsed_url['host'],
    ];
    if (($query_params['type'] ?? '') === 'ws' || ($query_params['network'] ?? '') === 'ws') {
        $proxy['network'] = 'ws';
        $proxy['ws-opts'] = [
            'path' => $query_params['path'] ?? '/trojan',
            'headers' => ['Host' => $query_params['host'] ?? $parsed_url['host']]
        ];
    }
    $proxy['udp'] = true;
    return $proxy;
}

// Fungsi Parser untuk Vmess
function parse_vmess($url) {
    $base64_part = str_replace('vmess://', '', $url);
    $json_data = base64_decode($base64_part);
    $data = json_decode($json_data, true);
    if (json_last_error() !== JSON_ERROR_NONE) return null;
    $proxy = [
        'name' => $data['ps'] ?? $data['add'] ?? 'vmess-'.substr(md5($url), 0, 5),
        'server' => $data['add'] ?? null,
        'port' => $data['port'] ?? null,
        'type' => 'vmess', 'uuid' => $data['id'] ?? null, 'alterId' => $data['aid'] ?? 0,
        'cipher' => $data['scy'] ?? 'auto',
        'tls' => isset($data['tls']) && in_array($data['tls'], ['tls', '1']),
        'skip-cert-verify' => true,
        'servername' => $data['sni'] ?? $data['host'] ?? null,
        'network' => $data['net'] ?? 'tcp',
        'ws-opts' => ($data['net'] ?? '') === 'ws' ? ['path' => $data['path'] ?? '/', 'headers' => array_filter(['Host' => $data['host'] ?? $data['add'] ?? null])] : null,
        'grpc-opts' => ($data['net'] ?? '') === 'grpc' ? ['grpc-service-name' => $data['path'] ?? ''] : null,
        'udp' => true,
    ];
    return array_filter($proxy, function($v) { return $v !== null; });
}

// Fungsi Parser untuk Vless
function parse_vless($url) {
    $parsed_url = parse_url($url);
    if (!$parsed_url || !isset($parsed_url['host']) || !isset($parsed_url['user'])) return null;
    $query_params = [];
    if (isset($parsed_url['query'])) parse_str($parsed_url['query'], $query_params);
    $proxy = [
        'name' => isset($parsed_url['fragment']) ? urldecode($parsed_url['fragment']) : $parsed_url['host'],
        'server' => $parsed_url['host'],
        'port' => $parsed_url['port'] ?? 443,
        'type' => 'vless', 'uuid' => $parsed_url['user'], 'cipher' => 'auto',
        'tls' => in_array(($query_params['security'] ?? ''), ['tls', 'reality']),
        'skip-cert-verify' => ($query_params['allowInsecure'] ?? '0') == '1',
        'servername' => $query_params['sni'] ?? $query_params['host'] ?? null,
        'network' => $query_params['type'] ?? 'tcp',
        'ws-opts' => ($query_params['type'] ?? '') === 'ws' ? ['path' => $query_params['path'] ?? '/', 'headers' => array_filter(['Host' => $query_params['host'] ?? $parsed_url['host'] ?? null])] : null,
        'grpc-opts' => ($query_params['type'] ?? '') === 'grpc' ? ['grpc-service-name' => $query_params['serviceName'] ?? null] : null,
        'reality-opts' => ($query_params['security'] ?? '') === 'reality' ? array_filter(['public-key' => $query_params['pbk'] ?? null, 'short-id' => $query_params['sid'] ?? null]) : null,
        'flow' => $query_params['flow'] ?? null,
        'udp' => true,
    ];
    return array_filter($proxy, function($v) { return $v !== null; });
}

// Fungsi pembuat YAML
function manual_yaml_builder($data, $indent = 0) {
    $yaml_string = '';
    $indent_space = str_repeat('  ', $indent);
    foreach ($data as $key => $value) {
        if ($value === null || $value === '' || (is_array($value) && empty($value))) continue;
        if ($key === 'proxies') {
            $proxy_yaml_parts = [];
            foreach ($value as $proxy_item) {
                $inner_block = manual_yaml_builder($proxy_item, $indent + 1);
                $proxy_yaml_parts[] = $indent_space . '- ' . ltrim($inner_block);
            }
            $yaml_string .= implode("\n", $proxy_yaml_parts);
            continue;
        }
        if (is_array($value)) {
            $is_associative = array_keys($value) !== range(0, count($value) - 1);
            $yaml_string .= $indent_space . $key . ":\n";
            if ($is_associative) {
                $yaml_string .= manual_yaml_builder($value, $indent + 1);
            } else {
                foreach($value as $item) $yaml_string .= $indent_space . "  - " . $item;
            }
        } elseif (is_bool($value)) {
            $yaml_string .= $indent_space . $key . ': ' . ($value ? 'true' : 'false');
        } else {
            $yaml_string .= $indent_space . $key . ': ' . $value;
        }
        $yaml_string .= "\n";
    }
    return rtrim($yaml_string);
}

// Logika utama saat form disubmit
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['proxy_input'])) {
    $proxy_input = trim($_POST['proxy_input']);
    if (empty($proxy_input)) {
        $yaml_output = "Error: Kolom input tidak boleh kosong.";
    } else {
        $proxy_links = explode("\n", $proxy_input);
        $converted_proxies = [];
        foreach ($proxy_links as $link) {
            $link = trim($link);
            if (empty($link)) continue;
            $proxy_data = convert_to_proxy_data($link);
            if (is_array($proxy_data)) {
                $converted_proxies[] = $proxy_data;
            }
        }
        if (!empty($converted_proxies)) {
            $final_yaml_data = ['proxies' => $converted_proxies];
            $yaml_output = manual_yaml_builder($final_yaml_data);
        } else {
            $yaml_output = "Error: Tidak ada link valid yang ditemukan atau gagal mengurai link.";
        }
    }
}
?>
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Konverter ke YAML untuk OpenClash</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background-color: #f4f7f9; color: #333; margin: 0; padding: 20px; display: flex; justify-content: center; }
        .container { width: 100%; max-width: 900px; background-color: #fff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        h1 { text-align: center; color: #2c3e50; margin-bottom: 30px; }
        textarea { width: 100%; padding: 12px; border-radius: 6px; border: 1px solid #dcdfe6; font-family: monospace; font-size: 14px; line-height: 1.5; box-sizing: border-box; resize: vertical; min-height: 150px; margin-bottom: 15px; }
        textarea:focus { outline: none; border-color: #6bdebb; box-shadow: 0 0 0 1px #6bdebb; }
        label { display: block; margin-bottom: 8px; font-weight: 600; color: #606266; }
        .output-container { margin-top: 30px; }
        
        .btn {
            display: block; width: 100%; padding: 12px;
            font-size: 16px; font-weight: 600; color: #fff;
            background-color: #6bdebb;
            border: none; border-radius: 6px;
            cursor: pointer; transition: background-color 0.3s;
        }
        .btn:hover {
            background-color: #7fe4c8;
        }

        .copy-btn {
            display: block;
            width: 140px;
            margin: 0 auto;
            padding: 8px 12px;
            font-size: 14px;
            font-weight: 600;
            color: #fff;
            background-color: #67c23a;
            border: none; border-radius: 6px;
            cursor: pointer; opacity: 0.9;
            transition: opacity 0.3s;
        }
        .copy-btn:hover { opacity: 1; }

        footer { text-align: center; margin-top: 30px; font-size: 12px; color: #909399; }
        footer a { color: #6bdebb; text-decoration: none; }
        footer a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Convert Akun</h1>
        
        <form action="<?php echo htmlspecialchars($_SERVER["PHP_SELF"]); ?>" method="post">
            <div class="input-container">
                <label for="proxy_input">Masukkan Link Akun :</label>
                <textarea id="proxy_input" name="proxy_input" placeholder="trojan://...
vmess://...
vless://..." rows="8"><?php echo htmlspecialchars($proxy_input); ?></textarea>
            </div>
            
            <button type="submit" class="btn">Convert</button>
        </form>
        
        <?php if (!empty($yaml_output)): ?>
        <div class="output-container">
            <label for="yaml_output">Hasil Convert :</label>
            <textarea id="yaml_output" readonly rows="12"><?php echo htmlspecialchars($yaml_output); ?></textarea>
            
            <button type="button" class="copy-btn" onclick="copyToClipboard()">Salin Hasil</button>
        </div>
        <?php endif; ?>
        
        <footer>Dibuat Oleh <a href="https://t.me/karelforta" target="_blank" rel="noopener noreferrer">A2OS</a></footer>
    </div>

    <script>
        function copyToClipboard() {
            const textarea = document.getElementById('yaml_output');
            textarea.select();
            // Untuk perangkat mobile
            textarea.setSelectionRange(0, 99999);
            document.execCommand('copy');
            alert('Hasil YAML berhasil disalin!');
        }
    </script>
</body>
</html>
EOF

# 3. Verifikasi pembuatan file php
if [ -f "$PHP_FILE_PATH" ]; then
    echo "✅ File PHP '$PHP_FILE_PATH' berhasil dibuat/diperbarui."
else
    echo "❌ Error: Gagal membuat file PHP."
    exit 1
fi

echo ""
echo "🎉 SEMUA PROSES SELESAI DENGAN SUKSES! 🎉"

exit 0
