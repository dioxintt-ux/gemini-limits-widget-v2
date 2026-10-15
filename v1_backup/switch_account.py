#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import sqlite3
import time

def main():
    if len(sys.argv) < 2:
        print("Ошибка: Не указан email аккаунта для переключения.")
        sys.exit(1)
        
    target_email = sys.argv[1].strip().lower()
    
    dir_path = os.path.dirname(os.path.realpath(__file__))
    accounts_path = os.path.join(dir_path, "accounts.json")
    
    if not os.path.exists(accounts_path):
        print(f"Ошибка: Файл аккаунтов не найден: {accounts_path}")
        sys.exit(1)
        
    with open(accounts_path, "r", encoding="utf-8") as f:
        accounts = json.load(f)
        
    account = next((a for a in accounts if a["email"].lower() == target_email), None)
    if not account:
        print(f"Ошибка: Аккаунт {target_email} не найден в списке.")
        sys.exit(1)
        
    db_value = account.get("db_value")
    if not db_value:
        print(f"Ошибка: Слепок сессии для {target_email} отсутствует. Пожалуйста, зайдите под ним в IDE один раз.")
        sys.exit(1)
        
    print(f"Переключение на аккаунт: {target_email}...")
    
    # 1. Закрываем Antigravity IDE
    print("Закрытие Antigravity IDE...")
    os.system("osascript -e 'tell application id \"com.google.antigravity-ide\" to quit'")
    
    # 2. Ожидаем завершения процесса
    time.sleep(2.0)
    
    # 3. Обновляем SQLite базу данных
    db_path = os.path.expanduser("~/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb")
    if not os.path.exists(db_path):
        print(f"Ошибка: База данных IDE не найдена по пути {db_path}")
        sys.exit(1)
        
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        # Вставляем или обновляем токен сессии
        cursor.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.oauthToken', ?)", (db_value,))
        conn.commit()
        conn.close()
        print("База данных IDE успешно обновлена.")
    except Exception as e:
        print(f"Ошибка при работе с SQLite: {e}")
        sys.exit(1)
        
    # 4. Запускаем Antigravity IDE
    print("Запуск Antigravity IDE...")
    os.system("open -b com.google.antigravity-ide")
    
    # 5. Принудительно обновляем SwiftBar
    print("Обновление виджета SwiftBar...")
    os.system("open -g swiftbar://refreshallplugins")
    print("Готово!")

if __name__ == "__main__":
    main()
