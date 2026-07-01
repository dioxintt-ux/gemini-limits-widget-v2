import os
import sys
import json
import requests
import sqlite3
import re
import base64

# Загружаем учетные данные из файла .env (чтобы не хранить секреты в репозитории)
DEFAULT_CLIENT_ID = ""
DEFAULT_CLIENT_SECRET = ""

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

if not DEFAULT_CLIENT_ID or not DEFAULT_CLIENT_SECRET:
    print("Ошибка: Укажите GOOGLE_CLIENT_ID и GOOGLE_CLIENT_SECRET в файле .env")
    sys.exit(1)

def refresh_access_token(client_id, client_secret, refresh_token):
    url = "https://oauth2.googleapis.com/token"
    payload = {
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token"
    }
    response = requests.post(url, data=payload)
    if response.status_code != 200:
        print(f"Ошибка обновления токена: {response.text}")
        return None
    return response.json().get("access_token")

def query_google_api(access_token, endpoint):
    url = f"https://daily-cloudcode-pa.googleapis.com/v1internal:{endpoint}"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
        "User-Agent": "Antigravity-Limits-Fetcher/1.0.0"
    }
    try:
        response = requests.post(url, json={}, headers=headers, timeout=10)
        print(f"\n--- Отладочные заголовки для {endpoint} ---")
        for k, v in response.headers.items():
            print(f"  {k}: {v}")
        print("------------------------------------------")
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Эндпоинт {endpoint} вернул ошибку: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        print(f"Ошибка при запросе к {endpoint}: {e}")
        return None

def parse_quota_data(load_assist_data, quota_summary_data):
    parsed_quotas = {
        "tier": "unknown",
        "groups": []
    }
    
    # Парсим тир аккаунта
    if load_assist_data and "allowedTiers" in load_assist_data:
        tiers = load_assist_data["allowedTiers"]
        if tiers:
            parsed_quotas["tier"] = tiers[0].get("id", "unknown")
            
    # Парсим группы квот из retrieveUserQuotaSummary
    if quota_summary_data and "groups" in quota_summary_data:
        for group in quota_summary_data["groups"]:
            group_name = group.get("displayName", "Unknown Group")
            group_desc = group.get("description", "")
            
            parsed_group = {
                "displayName": group_name,
                "description": group_desc,
                "limits": {}
            }
            
            for bucket in group.get("buckets", []):
                window = bucket.get("window", "unknown")
                display_name = bucket.get("displayName", window)
                remaining_fraction = bucket.get("remainingFraction", 1.0)
                # Показываем процент оставшегося лимита, а не потраченного!
                remaining_percent = int(round(remaining_fraction * 100))
                reset_time = bucket.get("resetTime", "")
                desc = bucket.get("description", "")
                
                parsed_group["limits"][window] = {
                    "displayName": display_name,
                    "remaining_fraction": remaining_fraction,
                    "used_percent": remaining_percent, # Передаем оставшийся процент в used_percent для совместимости с SwiftBar
                    "reset_time": reset_time,
                    "description": desc
                }
                
            parsed_quotas["groups"].append(parsed_group)
            
    return parsed_quotas

def sync_accounts_with_ide(accounts_path):
    db_path = os.path.expanduser("~/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb")
    if not os.path.exists(db_path):
        return
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken'")
        row = cursor.fetchone()
        if not row:
            return
        val = row[0]
        try:
            decoded = base64.b64decode(val)
        except Exception:
            decoded = val
        text = decoded.decode('utf-8', errors='ignore')
        candidates = re.findall(r"[a-zA-Z0-9+/=_-]{80,}", text)
        if not candidates:
            return
        
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
                        
                        # Читаем текущие аккаунты
                        accounts = []
                        if os.path.exists(accounts_path):
                            try:
                                with open(accounts_path, "r", encoding="utf-8") as f:
                                    accounts = json.load(f)
                            except Exception:
                                pass
                                
                        # Ищем, есть ли уже этот email
                        existing = next((a for a in accounts if a["email"] == email), None)
                        updated = False
                        
                        if not existing:
                            alias = email.split('@')[0]
                            existing = {
                                "email": email,
                                "alias": alias,
                                "refresh_token": refresh_token,
                                "client_secret": DEFAULT_CLIENT_SECRET,
                                "db_value": val
                            }
                            accounts.append(existing)
                            print(f"Новый аккаунт {email} автоматически импортирован из IDE с сессией.")
                            updated = True
                        else:
                            if existing.get("refresh_token") != refresh_token:
                                existing["refresh_token"] = refresh_token
                                updated = True
                            if existing.get("db_value") != val:
                                existing["db_value"] = val
                                updated = True
                                
                        if updated:
                            with open(accounts_path, "w", encoding="utf-8") as f:
                                json.dump(accounts, f, indent=4, ensure_ascii=False)
                            print(f"Сессия/токен для аккаунта {email} синхронизирована с IDE.")
                        break
            except Exception:
                pass
    except Exception:
        pass

def main():
    dir_path = os.path.dirname(os.path.realpath(__file__))
    accounts_path = os.path.join(dir_path, "accounts.json")
    quotas_path = os.path.join(dir_path, "quotas.json")
    
    # Автоматически синхронизируем токен с текущей запущенной IDE
    sync_accounts_with_ide(accounts_path)
    
    if not os.path.exists(accounts_path):
        print(f"Файл аккаунтов не найден: {accounts_path}")
        print("Пожалуйста, сначала добавьте аккаунт через auth.py")
        sys.exit(1)
        
    with open(accounts_path, "r", encoding="utf-8") as f:
        accounts = json.load(f)
        
    if not accounts:
        print("Список аккаунтов пуст.")
        sys.exit(1)

    client_id = DEFAULT_CLIENT_ID
    default_secret = DEFAULT_CLIENT_SECRET

    results = []
    
    for account in accounts:
        email = account["email"]
        alias = account["alias"]
        refresh_token = account["refresh_token"]
        # Берем секрет, сохраненный при авторизации, или дефолтный
        client_secret = account.get("client_secret", default_secret)
        
        print(f"\nОбновление лимитов для: {alias} ({email})...")
        access_token = refresh_access_token(client_id, client_secret, refresh_token)
        
        if access_token and not account.get("db_value"):
            try:
                from auth import build_credentials_proto, build_outer_proto
                cred_proto = build_credentials_proto(access_token, refresh_token)
                account["db_value"] = build_outer_proto(cred_proto)
                with open(accounts_path, "w", encoding="utf-8") as f:
                    json.dump(accounts, f, indent=4, ensure_ascii=False)
                print(f"  Сессия для {email} автоматически сгенерирована и сохранена.")
            except Exception as e:
                print(f"  Ошибка автогенерации сессии для {email}: {e}")
        
        if not access_token:
            print(f"Пропуск аккаунта {email}: не удалось получить access_token.")
            results.append({
                "email": email,
                "alias": alias,
                "status": "auth_error",
                "quotas": None
            })
            continue
            
        print("Запрос loadCodeAssist...")
        load_assist = query_google_api(access_token, "loadCodeAssist")
        print("Запрос fetchAvailableModels...")
        models = query_google_api(access_token, "fetchAvailableModels")
        print("Запрос retrieveUserQuotaSummary...")
        quota_summary = query_google_api(access_token, "retrieveUserQuotaSummary")
        
        if load_assist:
            debug_la_path = os.path.join(dir_path, f"debug_loadCodeAssist_{email}.json")
            with open(debug_la_path, "w", encoding="utf-8") as f:
                json.dump(load_assist, f, indent=4, ensure_ascii=False)
        if models:
            debug_m_path = os.path.join(dir_path, f"debug_fetchAvailableModels_{email}.json")
            with open(debug_m_path, "w", encoding="utf-8") as f:
                json.dump(models, f, indent=4, ensure_ascii=False)
        if quota_summary:
            debug_qs_path = os.path.join(dir_path, f"debug_retrieveUserQuotaSummary_{email}.json")
            with open(debug_qs_path, "w", encoding="utf-8") as f:
                json.dump(quota_summary, f, indent=4, ensure_ascii=False)
                
        quotas = parse_quota_data(load_assist, quota_summary)
        
        results.append({
            "email": email,
            "alias": alias,
            "status": "ok",
            "quotas": quotas
        })
        
    with open(quotas_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=4, ensure_ascii=False)
        
    print(f"\nВсе лимиты обновлены и сохранены в {quotas_path}")

    # Триггерим автоматическое обновление SwiftBar
    try:
        os.system("open -g swiftbar://refreshallplugins")
    except Exception:
        pass

if __name__ == "__main__":
    main()
