#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import base64
import requests

PROJECT_DIR = os.path.dirname(os.path.realpath(__file__))
ACCOUNTS_PATH = os.path.join(PROJECT_DIR, "accounts.json")

# Загружаем учетные данные из файла .env
DEFAULT_CLIENT_ID = ""
DEFAULT_CLIENT_SECRET = ""

env_path = os.path.join(PROJECT_DIR, ".env")
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
    # Field 1: Access Token
    acc_bytes = access_token.encode('utf-8')
    f1 = b'\x0a' + encode_varint(len(acc_bytes)) + acc_bytes
    
    # Field 2: Token Type
    f2 = b'\x12\x06Bearer'
    
    # Field 3: Refresh Token
    rt_bytes = refresh_token.encode('utf-8')
    f3 = b'\x1a' + encode_varint(len(rt_bytes)) + rt_bytes
    
    # Field 4: Expiration/Metadata (константа)
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

def refresh_access_token(client_id, client_secret, refresh_token):
    url = "https://oauth2.googleapis.com/token"
    payload = {
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token"
    }
    try:
        response = requests.post(url, data=payload, timeout=10)
        if response.status_code == 200:
            return response.json().get("access_token")
    except Exception:
        pass
    return None

def main():
    if not os.path.exists(ACCOUNTS_PATH):
        print("accounts.json not found")
        return
        
    with open(ACCOUNTS_PATH, "r", encoding="utf-8") as f:
        accounts = json.load(f)
        
    updated = False
    for acc in accounts:
        email = acc["email"]
        rt = acc["refresh_token"]
        secret = acc.get("client_secret") or DEFAULT_CLIENT_SECRET
        
        print(f"Генерация сессии для {email}...")
        access_token = refresh_access_token(DEFAULT_CLIENT_ID, secret, rt)
        if not access_token:
            print(f"  Не удалось получить access_token для {email}")
            continue
            
        cred_proto = build_credentials_proto(access_token, rt)
        db_val = build_outer_proto(cred_proto)
        
        acc["db_value"] = db_val
        updated = True
        print(f"  Успешно сгенерирована и сохранена сессия для {email}")
        
    if updated:
        with open(ACCOUNTS_PATH, "w", encoding="utf-8") as f:
            json.dump(accounts, f, indent=4, ensure_ascii=False)
        print("Файл accounts.json успешно обновлен с новыми слепками сессий.")

if __name__ == "__main__":
    main()
