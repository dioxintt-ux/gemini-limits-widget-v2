# Experience & Harness Quirks

## [2026-10-21] Gemini Weekly Quota Bridge & REST Quota Limitation

- **Симптом / Проблема**: В UI виджета пропали недельные лимиты моделей Gemini, отображались только 5-часовые.
- **Причина**: REST-эндпоинт Google Cloud Code (`v1internal:retrieveUserQuotaSummary`) при внешнем вызове возвращает только группу `Claude and GPT models` без `Gemini Models`. После фильтрации по подстроке `gemini` ключ `weekly` отсутствовал в `quotas.json`, из-за чего `app/main.swift` скрывал строку недельного лимита (`if let weekly = q.limitsWeekly`) и отсекал аккаунт из расчета общих средних процентов.
- **Решение / Правило**:
  1. Опрашивать локальный Connect-RPC `language_server_macos_arm` (`RetrieveUserQuotaSummary` на `127.0.0.1:<port>` с токеном `X-Codeium-Csrf-Token`) для активного аккаунта IDE — он содержит актуальные квоты `gemini-weekly` и `gemini-5h`.
  2. В `parse_quota_data` гарантировать обязательное наличие бакета `weekly` (fallback 100% при отсутствии в API), предотвращая `nil` в UI-рендерере.
