import os
import sys
import json
import requests
import sqlite3
import re
import base64
import subprocess
import urllib3
from datetime import datetime, timezone

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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

def query_google_api(access_token, endpoint, base_url=None):
    if not base_url:
        if endpoint == "retrieveUserQuotaSummary":
            base_url = "https://cloudcode-pa.googleapis.com"
        else:
            base_url = "https://daily-cloudcode-pa.googleapis.com"
    url = f"{base_url}/v1internal:{endpoint}"
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

def generate_desc_from_reset_time(reset_time_str):
    if not reset_time_str:
        return ""
    try:
        r_str = reset_time_str
        if r_str.endswith("Z"):
            r_str = r_str[:-1] + "+00:00"
        dt = datetime.fromisoformat(r_str)
        now = datetime.now(timezone.utc)
        diff = dt - now
        total_seconds = int(diff.total_seconds())
        if total_seconds <= 0:
            return ""
        
        days = total_seconds // 86400
        hours = (total_seconds % 86400) // 3600
        minutes = (total_seconds % 3600) // 60
        
        if days > 0:
            if hours > 0:
                return f"refresh in {days} days, {hours} hours."
            else:
                return f"refresh in {days} days."
        elif hours > 0:
            if minutes > 0:
                return f"refresh in {hours} hours, {minutes} minutes."
            else:
                return f"refresh in {hours} hours."
        else:
            return f"refresh in {minutes} minutes."
    except Exception:
        return ""

def get_ide_language_server_quotas():
    try:
        ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        csrf_match = re.search(r"--csrf_token\s+([a-f0-9\-]+)", ps_out)
        if not csrf_match:
            return None
        csrf_token = csrf_match.group(1)

        lsof_out = subprocess.check_output(["lsof", "-Pan", "-c", "language_server_macos_arm", "-i"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        ports = re.findall(r":(\d+)\s+\(LISTEN\)", lsof_out)
        if not ports:
            return None

        headers = {
            "Connect-Protocol-Version": "1",
            "Content-Type": "application/json",
            "X-Codeium-Csrf-Token": csrf_token
        }

        for port in ports:
            try:
                r_user = requests.post(
                    f"https://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/GetUserStatus",
                    headers=headers, json={}, verify=False, timeout=2
                )
                if r_user.status_code != 200:
                    continue
                email = r_user.json().get("userStatus", {}).get("email")
                if not email:
                    continue

                r_quota = requests.post(
                    f"https://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
                    headers=headers, json={"forceRefresh": True}, verify=False, timeout=3
                )
                if r_quota.status_code != 200:
                    continue
                return {
                    "email": email,
                    "quota_summary": r_quota.json().get("response", {})
                }
            except Exception:
                continue
    except Exception:
        pass
    return None

def parse_quota_data(load_assist_data, quota_summary_data, models_data=None):
    parsed_quotas = {
        "tier": "unknown",
        "groups": []
    }
    
    # Парсим тир аккаунта
    if load_assist_data and "allowedTiers" in load_assist_data:
        tiers = load_assist_data["allowedTiers"]
        if tiers:
            parsed_quotas["tier"] = tiers[0].get("id", "unknown")
            
    # 1. Извлекаем реальную квоту для Gemini моделей из fetchAvailableModels
    gemini_quota_info = None
    if models_data and isinstance(models_data, dict):
        models_dict = models_data.get("models", {})
        for m_id, m_val in models_dict.items():
            if ("gemini" in m_id or m_val.get("modelProvider") == "MODEL_PROVIDER_GOOGLE") and m_val.get("quotaInfo"):
                gemini_quota_info = m_val["quotaInfo"]
                break

    if gemini_quota_info:
        remaining_fraction = gemini_quota_info.get("remainingFraction", 1.0)
        remaining_percent = int(round(remaining_fraction * 100))
        reset_time = gemini_quota_info.get("resetTime", "")
        desc = ""
        if remaining_fraction < 1.0 and remaining_percent < 100 and reset_time:
            desc = generate_desc_from_reset_time(reset_time)
            
        gemini_group = {
            "displayName": "Gemini models",
            "description": "Models within this group: Gemini 2.5 Flash, Gemini 2.5 Pro, Gemini 3 Flash",
            "limits": {
                "5h": {
                    "displayName": "Five Hour Limit Remaining",
                    "remaining_fraction": remaining_fraction,
                    "used_percent": remaining_percent,
                    "reset_time": reset_time,
                    "description": desc
                }
            }
        }
        # Подтягиваем лимиты из quota_summary_data строго для Gemini Models
        if quota_summary_data and "groups" in quota_summary_data:
            for g in quota_summary_data["groups"]:
                if "gemini" not in g.get("displayName", "").lower():
                    continue
                for b in g.get("buckets", []):
                    w_window = b.get("window")
                    w_fraction = b.get("remainingFraction", 1.0)
                    w_percent = int(round(w_fraction * 100))
                    w_reset = b.get("resetTime", "")
                    w_desc = b.get("description", "")
                    if not w_desc and w_fraction < 1.0 and w_percent < 100 and w_reset:
                        w_desc = generate_desc_from_reset_time(w_reset)
                    if w_window == "weekly":
                        gemini_group["limits"]["weekly"] = {
                            "displayName": b.get("displayName", "Weekly Limit Remaining"),
                            "remaining_fraction": w_fraction,
                            "used_percent": w_percent,
                            "reset_time": w_reset,
                            "description": w_desc
                        }
                    elif w_window == "5h":
                        gemini_group["limits"]["5h"] = {
                            "displayName": b.get("displayName", "Five Hour Limit Remaining"),
                            "remaining_fraction": w_fraction,
                            "used_percent": w_percent,
                            "reset_time": w_reset,
                            "description": w_desc
                        }
                break

        # Гарантируем наличие weekly лимита, чтобы SwiftBar виджет не скрывал строку и корректно рассчитывал средние значения
        if "weekly" not in gemini_group["limits"]:
            gemini_group["limits"]["weekly"] = {
                "displayName": "Weekly Limit Remaining",
                "remaining_fraction": 1.0,
                "used_percent": 100,
                "reset_time": "",
                "description": ""
            }

        parsed_quotas["groups"].append(gemini_group)

    # 2. Если models_data не предоставила группу Gemini, берем из retrieveUserQuotaSummary
    if not parsed_quotas["groups"] and quota_summary_data and "groups" in quota_summary_data:
        for group in quota_summary_data["groups"]:
            group_name = group.get("displayName", "Unknown Group")
            if "gemini" not in group_name.lower():
                continue
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
                remaining_percent = int(round(remaining_fraction * 100))
                reset_time = bucket.get("resetTime", "")
                desc = bucket.get("description", "")
                if remaining_fraction >= 1.0 or remaining_percent >= 100:
                    desc = ""
                elif not desc and reset_time:
                    desc = generate_desc_from_reset_time(reset_time)
                
                parsed_group["limits"][window] = {
                    "displayName": display_name,
                    "remaining_fraction": remaining_fraction,
                    "used_percent": remaining_percent,
                    "reset_time": reset_time,
                    "description": desc
                }
            if "weekly" not in parsed_group["limits"]:
                parsed_group["limits"]["weekly"] = {
                    "displayName": "Weekly Limit Remaining",
                    "remaining_fraction": 1.0,
                    "used_percent": 100,
                    "reset_time": "",
                    "description": ""
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
                        if userinfo_resp.status_code == 200:
                            email = userinfo_resp.json().get("email", "unknown")
                            if email != "unknown" and "@" in email:
                                accounts = []
                                if os.path.exists(accounts_path):
                                    try:
                                        with open(accounts_path, "r", encoding="utf-8") as f:
                                            accounts = json.load(f)
                                    except Exception:
                                        pass
                                        
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

    # Опрашиваем запущенный в Antigravity IDE Language Server для получения актуальных Gemini квот
    ide_quota_data = get_ide_language_server_quotas()
    if ide_quota_data:
        print(f"Обнаружен активный Antigravity Language Server для аккаунта: {ide_quota_data.get('email')}")
    
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

        if ide_quota_data and ide_quota_data.get("email") == email and ide_quota_data.get("quota_summary"):
            quota_summary = ide_quota_data["quota_summary"]
            print(f"  Используются live квоты Gemini из Language Server для {email}")
        else:
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
                
        quotas = parse_quota_data(load_assist, quota_summary, models)
        
        results.append({
            "email": email,
            "alias": alias,
            "status": "ok",
            "quotas": quotas
        })
        
    with open(quotas_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=4, ensure_ascii=False)
        
    print(f"\nВсе лимиты обновлены и сохранены в {quotas_path}")

    try:
        os.system("open -g swiftbar://refreshallplugins")
    except Exception:
        pass

if __name__ == "__main__":
    main()
