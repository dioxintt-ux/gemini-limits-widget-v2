import os
import sys
import json
import webbrowser
import requests
import secrets
import hashlib
import base64
import sqlite3
import re
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# Загружаем учетные данные из файла .env (чтобы не хранить секреты в репозитории)
DEFAULT_CLIENT_ID = ""
DEFAULT_CLIENT_SECRET = ""
BACKUP_CLIENT_SECRET = ""

env_path = os.path.join(os.path.dirname(__file__), ".env")
if os.path.exists(env_path):
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if k == "GOOGLE_CLIENT_ID":
                    DEFAULT_CLIENT_ID = v
                elif k == "GOOGLE_CLIENT_SECRET":
                    DEFAULT_CLIENT_SECRET = v
                elif k == "GOOGLE_BACKUP_CLIENT_SECRET":
                    BACKUP_CLIENT_SECRET = v

if not DEFAULT_CLIENT_ID or not DEFAULT_CLIENT_SECRET:
    print("Ошибка: Укажите GOOGLE_CLIENT_ID и GOOGLE_CLIENT_SECRET в файле .env")
    sys.exit(1)

PORT = 8080
REDIRECT_URI = f"http://localhost:{PORT}/"

# Глобальные переменные для PKCE и кода авторизации
auth_code = None
code_verifier = None

class OAuthCallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global auth_code
        query_components = parse_qs(urlparse(self.path).query)
        
        if "code" in query_components:
            auth_code = query_components["code"][0]
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("""
                <html>
                <head><title>Авторизация успешна</title></head>
                <body style="font-family: Arial, sans-serif; text-align: center; margin-top: 50px; background-color: #1e1e1e; color: #ffffff;">
                    <h2 style="color: #4CAF50;">Авторизация успешно пройдена!</h2>
                    <p>Вы можете закрыть эту вкладку браузера и вернуться в терминал.</p>
                </body>
                </html>
            """.encode("utf-8"))
        else:
            self.send_response(400)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("Ошибка авторизации. Не найден код авторизации.".encode("utf-8"))

    def log_message(self, format, *args):
        return

def generate_pkce():
    verifier = secrets.token_urlsafe(64)
    sha256_hash = hashlib.sha256(verifier.encode('utf-8')).digest()
    challenge = base64.urlsafe_b64encode(sha256_hash).decode('utf-8').rstrip('=')
    return verifier, challenge

def get_google_tokens(client_id, client_secret):
    global auth_code, code_verifier
    auth_code = None
    
    code_verifier, code_challenge = generate_pkce()
    server = HTTPServer(("localhost", PORT), OAuthCallbackHandler)
    
    scopes = [
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    auth_url = (
        f"https://accounts.google.com/o/oauth2/v2/auth?"
        f"client_id={client_id}&"
        f"redirect_uri={REDIRECT_URI}&"
        f"response_type=code&"
        f"scope={'+'.join(scopes)}&"
        f"access_type=offline&"
        f"prompt=consent&"
        f"code_challenge={code_challenge}&"
        f"code_challenge_method=S256"
    )
    
    print("\n=== Шаг 1: Авторизация через браузер ===")
    print("Открываем браузер для входа в Google...")
    webbrowser.open(auth_url)
    print("Ожидание подтверждения в браузере...")
    
    server.handle_request()
    server.server_close()
    
    if not auth_code:
        print("Ошибка: не удалось получить код авторизации.")
        sys.exit(1)
        
    print("\n=== Шаг 2: Получение токенов от Google ===")
    token_url = "https://oauth2.googleapis.com/token"
    
    # Пробуем первый секрет
    payload = {
        "code": auth_code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": REDIRECT_URI,
        "grant_type": "authorization_code",
        "code_verifier": code_verifier
    }
    
    response = requests.post(token_url, data=payload)
    if response.status_code != 200:
        # Если первый секрет не подошел, пробуем запасной
        backup_secret = BACKUP_CLIENT_SECRET
        print(f"Первая попытка обмена токенов не удалась, пробуем запасной секрет...")
        payload["client_secret"] = backup_secret
        response = requests.post(token_url, data=payload)
        
    if response.status_code != 200:
        print(f"Ошибка обмена кода на токены: {response.text}")
        sys.exit(1)
        
    tokens = response.json()
    refresh_token = tokens.get("refresh_token")
    access_token = tokens.get("access_token")
    
    if not refresh_token:
        print("Предупреждение: Google не вернул refresh_token. Попробуйте выйти из аккаунта Google в браузере и войти снова.")
        
    userinfo_url = "https://www.googleapis.com/oauth2/v3/userinfo"
    headers = {"Authorization": f"Bearer {access_token}"}
    userinfo_resp = requests.get(userinfo_url, headers=headers)
    email = userinfo_resp.json().get("email", "unknown")
    
    # Запоминаем, какой секрет сработал, чтобы сохранить его для fetcher.py
    used_secret = payload["client_secret"]
    
    return email, refresh_token, used_secret, access_token


def encode_varint(value):
    output = bytearray()
    while True:
        towrite = value & 0x7F
        value >>= 7
        if value:
            output.append(towrite | 0x80)
        else:
            output.append(towrite)
            break
    return bytes(output)


def build_credentials_proto(access_token, refresh_token):
    acc_bytes = access_token.encode('utf-8')
    f1 = b'\x0a' + encode_varint(len(acc_bytes)) + acc_bytes
    
    f2 = b'\x12\x06Bearer'
    
    rt_bytes = refresh_token.encode('utf-8')
    f3 = b'\x1a' + encode_varint(len(rt_bytes)) + rt_bytes
    
    f4 = b'\x22\x06\x08\xc3\xf3\xf8\xd1\x06'
    
    return f1 + f2 + f3 + f4


def build_outer_proto(cred_proto_bytes):
    cred_b64 = base64.b64encode(cred_proto_bytes).decode('utf-8')
    cred_b64_bytes = cred_b64.encode('utf-8')
    
    sub1 = b'\x0a' + encode_varint(len(cred_b64_bytes)) + cred_b64_bytes
    f2 = b'\x12' + encode_varint(len(sub1)) + sub1
    f1 = b'\x0a\x19oauthTokenInfoSentinelKey'
    
    token_sentinel_payload = f1 + f2
    
    auth_sentinel = (
        b'\x0a\xf9\x01\x0a\x1fauthStateWithContextSentinelKey\x12\xd5\x01\x0a\xd2\x01'
        b'{"state":"signedIn","context":{"project":"","showProjectError":false,"errorMessage":"","ineligibleMessage":"",'
        b'"verificationUrl":"","isGcpTos":false,"browserOpenFailed":false,"appealUrl":"","appealLinkText":""}}'
    )
    
    token_sentinel = b'\x0a' + encode_varint(len(token_sentinel_payload)) + token_sentinel_payload
    
    final_bytes = auth_sentinel + token_sentinel
    return base64.b64encode(final_bytes).decode('utf-8')


def save_account(email, refresh_token, client_secret, db_value=None):
    config_path = os.path.join(os.path.dirname(__file__), "accounts.json")
    
    accounts = []
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                accounts = json.load(f)
        except Exception:
            pass
            
    existing = next((a for a in accounts if a["email"] == email), None)
    
    alias = input(f"Введите отображаемое имя (алиас) для аккаунта {email} [по умолчанию: {email}]: ").strip()
    if not alias:
        alias = email
        
    if existing:
        existing["alias"] = alias
        existing["client_secret"] = client_secret
        if refresh_token:
            existing["refresh_token"] = refresh_token
        if db_value:
            existing["db_value"] = db_value
        print(f"Аккаунт {email} обновлен.")
    else:
        if not refresh_token:
            print("Ошибка: Для нового аккаунта не был получен refresh_token. Попробуйте очистить разрешения для этого приложения в Google Security Console.")
            sys.exit(1)
        accounts.append({
            "email": email,
            "alias": alias,
            "refresh_token": refresh_token,
            "client_secret": client_secret,
            "db_value": db_value
        })
        print(f"Аккаунт {email} успешно добавлен.")
        
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(accounts, f, indent=4, ensure_ascii=False)
        
    print(f"Конфигурация сохранена в {config_path}")

def try_import_local_token():
    db_path = os.path.expanduser("~/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb")
    if not os.path.exists(db_path):
        return None
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken'")
        row = cursor.fetchone()
        if not row:
            return None
        val = row[0]
        try:
            decoded = base64.b64decode(val)
        except Exception:
            decoded = val
        text = decoded.decode('utf-8', errors='ignore')
        candidates = re.findall(r"[a-zA-Z0-9+/=_-]{80,}", text)
        if not candidates:
            return None
        
        for cand in candidates:
            cand_norm = cand.replace('-', '+').replace('_', '/')
            cand_norm += "=" * ((4 - len(cand_norm) % 4) % 4)
            try:
                dec_cand = base64.b64decode(cand_norm)
                idx = dec_cand.find(b"1//")
                if idx != -1:
                    token_part = dec_cand[idx:]
                    clean_token = bytearray()
                    for b in token_part:
                        if 32 <= b <= 126:
                            clean_token.append(b)
                        else:
                            break
                    raw_token = clean_token.decode('utf-8')
                    refresh_token = re.sub(r'[^a-zA-Z0-9_/\.-]', '', raw_token).rstrip('.')
                    
                    # Проверяем токен с правильным Client ID и Secret
                    url = "https://oauth2.googleapis.com/token"
                    payload = {
                        "client_id": DEFAULT_CLIENT_ID,
                        "client_secret": DEFAULT_CLIENT_SECRET,
                        "refresh_token": refresh_token,
                        "grant_type": "refresh_token"
                    }
                    response = requests.post(url, data=payload)
                    if response.status_code == 200:
                        access_token = response.json().get("access_token")
                        userinfo_resp = requests.get("https://www.googleapis.com/oauth2/v3/userinfo", headers={"Authorization": f"Bearer {access_token}"})
                        email = userinfo_resp.json().get("email", "unknown")
                        return email, refresh_token, DEFAULT_CLIENT_SECRET, val
            except Exception:
                pass
    except Exception:
        pass
    return None

def main():
    print("=== Регистрация Google аккаунта для виджета лимитов ===")
    
    # Пытаемся автоматически импортировать токен из локальной IDE
    print("Попытка автоматического импорта токена из Antigravity IDE...")
    local_info = try_import_local_token()
    if local_info:
        email, refresh_token, used_secret, db_value = local_info
        print(f"✅ Обнаружен активный токен в IDE для аккаунта {email}!")
        try:
            ans = input("Импортировать этот токен? [Y/n]: ").strip().lower()
        except (KeyboardInterrupt, EOFError):
            ans = "y"
        if ans in ("", "y", "yes"):
            save_account(email, refresh_token, used_secret, db_value)
            return
        
    client_id = DEFAULT_CLIENT_ID
    client_secret = DEFAULT_CLIENT_SECRET

    try:
        email, refresh_token, used_secret, access_token = get_google_tokens(client_id, client_secret)
        
        # Проверяем, совпадает ли полученный email с тем, что сейчас в IDE
        db_value = None
        local_info = try_import_local_token()
        if local_info and local_info[0] == email:
            db_value = local_info[3]
            
        # Если слепка в IDE нет, то строим его динамически
        if not db_value and access_token:
            try:
                cred_proto = build_credentials_proto(access_token, refresh_token)
                db_value = build_outer_proto(cred_proto)
            except Exception:
                pass
            
        save_account(email, refresh_token, used_secret, db_value)
    except KeyboardInterrupt:
        print("\nПроцесс прерван пользователем.")
        sys.exit(0)

if __name__ == "__main__":
    main()
