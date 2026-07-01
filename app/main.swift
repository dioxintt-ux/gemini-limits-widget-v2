import Cocoa
import Foundation

// Расширение для работы с Hex цветами в AppKit
extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hexSanitized.hasPrefix("#") {
            hexSanitized.remove(at: hexSanitized.startIndex)
        }
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// Класс для отрисовки кастомного лоудера Radar Pulse в статус-баре
class StatusBarLoaderView: NSView {
    var radarRadius: CGFloat = 3.0
    var isActive = false
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // В активном состоянии красим лоудер в фирменный зеленый Apple (#30D158), в неактивном - в стандартный цвет текста
        let color = isActive ? NSColor(hex: "#30D158") : NSColor.controlTextColor
        
        // Статический внешний круг вокруг центральной точки (крупнее и четче)
        let staticRadius: CGFloat = 8.0
        let staticColor = color.withAlphaComponent(0.4) // Полупрозрачный круг
        staticColor.set()
        let staticRect = NSRect(x: 12 - staticRadius, y: 11 - staticRadius, width: staticRadius * 2, height: staticRadius * 2)
        let staticPath = NSBezierPath(ovalIn: staticRect)
        staticPath.lineWidth = 1.2
        staticPath.stroke()
        
        // Central dot (diameter 6px instead of 4px)
        color.set()
        let dotPath = NSBezierPath(ovalIn: NSRect(x: 9, y: 8, width: 6, height: 6))
        dotPath.fill()
        
        // Расширяющийся затухающий круг (эффект радара) - рисуется только в активном состоянии
        if isActive {
            let ringColor = color.withAlphaComponent(max(0, 1.0 - (radarRadius - 3.0) / 8.0))
            ringColor.set()
            let ringRect = NSRect(x: 12 - radarRadius, y: 11 - radarRadius, width: radarRadius * 2, height: radarRadius * 2)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = 1.2
            ringPath.stroke()
        }
    }
    
    func tick() {
        guard isActive else { return }
        radarRadius += 0.35 // Анимация адаптирована под больший радиус
        if radarRadius > 11.0 {
            radarRadius = 3.0
        }
        needsDisplay = true
    }
}

// Класс для выравнивания заголовков по левому краю вровень с лимитами
class MenuHeaderView: NSView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    
    init(title: String, iconName: String, iconColor: NSColor, textColor: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 28))
        self.autoresizingMask = [.width]
        
        addSubview(iconView)
        addSubview(titleLabel)
        
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        if #available(macOS 12.0, *) {
            iconView.image = iconView.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
        }
        
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.textColor = textColor
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        // Иконка строго на x: 9, текст строго на x: 32 (идеальное выравнивание со шкалами)
        iconView.frame = NSRect(x: 9, y: 7, width: 14, height: 14)
        titleLabel.frame = NSRect(x: 32, y: 6, width: bounds.width - 45, height: 18)
    }
    
    // Пересылаем событие клика по кастомному вью соответствующему пункту NSMenuItem
    override func mouseDown(with event: NSEvent) {
        if let menuItem = self.enclosingMenuItem {
            if menuItem.isEnabled {
                if let action = menuItem.action, let target = menuItem.target {
                    _ = target.perform(action, with: menuItem)
                }
                menuItem.menu?.cancelTracking()
            }
        } else {
            super.mouseDown(with: event)
        }
    }
}

// Кастомный графический прогресс-бар в стиле Apple
class QuotaProgressView: NSView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let percentLabel = NSTextField(labelWithString: "")
    
    // Элементы строки сброса лимита (для идеального выравнивания)
    let timerIconView = NSImageView()
    let timerLabel = NSTextField(labelWithString: "")
    
    var percent: Double = 0.0
    var barColor: NSColor = .systemGreen
    var hasTimer = false
    
    init(title: String, percent: Double, iconName: String, iconColor: NSColor, barColor: NSColor, timeRemaining: String = "") {
        let timerText = timeRemaining
        self.hasTimer = !timerText.isEmpty
        let height: CGFloat = hasTimer ? 44 : 28
        
        // Начальная ширина 330pt для увеличения масштаба
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: height))
        self.percent = percent
        self.barColor = barColor
        
        // Разрешаем вью автоматически растягиваться по ширине меню
        self.autoresizingMask = [.width]
        
        // Добавляем дочерние элементы
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(percentLabel)
        
        // Настройка иконки
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        if #available(macOS 12.0, *) {
            iconView.image = iconView.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
        }
        
        // Настройка названия (регулярный шрифт, 12pt)
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        
        // Настройка процентов (регулярный шрифт, 12pt)
        percentLabel.stringValue = "\(Int(round(percent)))%"
        percentLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.isEditable = false
        percentLabel.isBordered = false
        percentLabel.drawsBackground = false
        
        // Настройка строки сброса лимита, если она есть
        if hasTimer {
            addSubview(timerIconView)
            addSubview(timerLabel)
            
            timerIconView.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
            if #available(macOS 12.0, *) {
                timerIconView.image = timerIconView.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
            }
            
            timerLabel.stringValue = timerText
            timerLabel.font = NSFont.systemFont(ofSize: 11)
            timerLabel.textColor = .secondaryLabelColor
            timerLabel.isEditable = false
            timerLabel.isBordered = false
            timerLabel.drawsBackground = false
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        let w = bounds.width
        let row1Y: CGFloat = hasTimer ? 22 : 6
        
        // Выравнивание по левой сетке стандартных NSMenuItem: иконка на x: 9, текст на x: 32
        iconView.frame = NSRect(x: 9, y: row1Y, width: 14, height: 14)
        titleLabel.frame = NSRect(x: 32, y: row1Y - 1, width: 105, height: 16)
        
        // Прижимаем проценты к правому краю с отступом 50
        percentLabel.frame = NSRect(x: w - 50, y: row1Y - 1, width: 35, height: 16)
        
        if hasTimer {
            timerIconView.frame = NSRect(x: 9, y: 4, width: 12, height: 12)
            timerLabel.frame = NSRect(x: 32, y: 2, width: w - 45, height: 14)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let w = bounds.width
        let row1Y: CGFloat = hasTimer ? 22 : 6
        let barY = row1Y + 4
        
        // Прогресс-бар растягивается динамически
        let barWidth = w - 145 - 60
        
        // Отрисовка подложки (трека)
        let trackRect = NSRect(x: 145, y: barY, width: barWidth, height: 6)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.08).set()
        trackPath.fill()
        
        // Отрисовка заполненной части прогресс-бара
        if percent > 0 {
            let fillWidth = max(6, CGFloat(percent / 100.0) * barWidth)
            let fillRect = NSRect(x: 145, y: barY, width: fillWidth, height: 6)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
            barColor.set()
            fillPath.fill()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var spinner: NSProgressIndicator!
    var loaderView: StatusBarLoaderView!
    
    // Пути к проекту
    let projectDir = "/Users/daniilchugunnikov/Desktop/work/gemini_limits_widget_v2"

    var quotasPath: String { "\(projectDir)/quotas.json" }
    var accountsPath: String { "\(projectDir)/accounts.json" }
    var dbPath: String { NSHomeDirectory() + "/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb" }
    
    // Премиальные цвета Apple
    let colorPurple = NSColor(hex: "#AF52DE")
    let colorGreen  = NSColor(hex: "#30D158")
    let colorYellow = NSColor.systemYellow
    let colorRed    = NSColor.systemRed
    
    // Статусы активности
    enum AgentStatus {
        case idle
        case active
        case waitingPermission
    }
    
    var currentStatus: AgentStatus = .idle
    var activeCount = 0
    var waitingCount = 0
    
    // Кэш путей к логам для оптимизации CPU
    var cachedLogPaths: [String] = []
    var lastScanTime: TimeInterval = 0
    
    // Время последнего запроса квот через fetcher.py
    var lastQuotaUpdateTime: TimeInterval = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Создаем элемент в статус-баре
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Настраиваем нативный спиннер внутри кнопки статус-бара
        if let button = statusItem.button {
            loaderView = StatusBarLoaderView()
            loaderView.isHidden = true
            button.addSubview(loaderView)
            
            spinner = NSProgressIndicator(frame: NSRect(x: 4, y: 3, width: 16, height: 16))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isHidden = true
            button.addSubview(spinner)
        }
        
        // Создаем выпадающее меню
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        
        // Устанавливаем дефолтное состояние
        updateStatusBarIcon()
        
        // Таймер для опроса логов (каждую секунду)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusAndMenu()
        }
        
        // Таймер анимации лоудера (25 FPS - каждые 40мс)
        let animTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.animateActiveLoader()
        }
        RunLoop.current.add(animTimer, forMode: .common)
        
        // Таймер автоматического фонового обновления (раз в 10 секунд проверяем необходимость обновления)
        let quotaTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkAndRunFetcher()
        }
        RunLoop.current.add(quotaTimer, forMode: .common)
        
        // Запускаем фоновое обновление лимитов сразу при старте приложения
        lastQuotaUpdateTime = Date().timeIntervalSince1970
        runPythonScript("fetcher.py")
        
        // Первоначальное обновление локального меню
        updateStatusAndMenu()
    }
    
    func animateActiveLoader() {
        guard currentStatus == .active else { return }
        loaderView.tick()
    }
    
    func checkAndRunFetcher() {
        let now = Date().timeIntervalSince1970
        // Если ИИ-агент активен - обновляем раз в 1 минуту (60с), если отдыхает - раз в 5 минут (300с)
        let interval: TimeInterval = (currentStatus == .active) ? 60.0 : 300.0
        if now - lastQuotaUpdateTime >= interval {
            lastQuotaUpdateTime = now
            runPythonScript("fetcher.py")
        }
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        // При открытии меню запускаем быстрое асинхронное обновление в фоне
        // Обновляем метку времени, чтобы фоновый таймер не дублировал запрос сразу после этого
        lastQuotaUpdateTime = Date().timeIntervalSince1970
        runPythonScript("fetcher.py")
    }
    
    func updateStatusAndMenu() {
        let (active, waiting) = scanDialogues()
        self.activeCount = active
        self.waitingCount = waiting
        
        let newStatus: AgentStatus
        if waiting > 0 {
            newStatus = .waitingPermission
        } else if active > 0 {
            newStatus = .active
        } else {
            newStatus = .idle
        }
        
        let statusChanged = (newStatus != currentStatus)
        currentStatus = newStatus
        
        if statusChanged || currentStatus != .active {
            updateStatusBarIcon()
        }
        
        rebuildMenu()
    }
    
    func updateStatusBarIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch self.currentStatus {
            case .idle:
                self.spinner.isHidden = true
                self.spinner.stopAnimation(nil)
                
                // Делаем лоудер видимым, но переводим в неактивное состояние (просто точка)
                self.loaderView.isActive = false
                self.loaderView.isHidden = false
                self.loaderView.needsDisplay = true
                
                self.statusItem.length = 24
                self.statusItem.button?.title = ""
                self.statusItem.button?.image = nil
                self.statusItem.button?.contentTintColor = nil
                
            case .waitingPermission:
                self.spinner.isHidden = true
                self.spinner.stopAnimation(nil)
                self.loaderView.isHidden = true
                
                self.statusItem.length = NSStatusItem.variableLength
                self.statusItem.button?.title = ""
                self.statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Waiting")
                let isOrange = (Int(Date().timeIntervalSince1970) % 2 == 0)
                self.statusItem.button?.contentTintColor = isOrange ? NSColor.systemOrange : NSColor.systemYellow
                
            case .active:
                self.spinner.isHidden = true
                self.spinner.stopAnimation(nil)
                
                // Переводим лоудер в активное состояние (радар "оживает")
                self.loaderView.isActive = true
                self.loaderView.isHidden = false
                
                self.statusItem.length = 24
                self.statusItem.button?.title = ""
                self.statusItem.button?.image = nil
            }
        }
    }
    
    // Чтение состояния диалогов из transcript.jsonl
    func scanDialogues() -> (active: Int, waiting: Int) {
        let now = Date().timeIntervalSince1970
        
        // Обновляем список путей к логам раз в 10 секунд
        if now - lastScanTime > 10.0 || cachedLogPaths.isEmpty {
            lastScanTime = now
            var tempPaths: [String] = []
            let brainPattern = NSHomeDirectory() + "/.gemini/antigravity-ide/brain"
            if FileManager.default.fileExists(atPath: brainPattern) {
                let brainURL = URL(fileURLWithPath: brainPattern)
                if let enumerator = FileManager.default.enumerator(at: brainURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles], errorHandler: nil) {
                    for case let url as URL in enumerator {
                        let logPath = url.appendingPathComponent(".system_generated/logs/transcript.jsonl").path
                        if FileManager.default.fileExists(atPath: logPath) {
                            tempPaths.append(logPath)
                        }
                    }
                }
            }
            cachedLogPaths = tempPaths
        }
        
        var localActive = 0
        var localWaiting = 0
        
        for logPath in cachedLogPaths {
            guard FileManager.default.fileExists(atPath: logPath) else { continue }
            
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
                  let mdate = attributes[.modificationDate] as? Date else {
                continue
            }
            
            let mtime = mdate.timeIntervalSince1970
            let timeDiff = now - mtime
            
            // Если лог не обновлялся 35 секунд — считаем диалог неактивным
            if timeDiff > 35 {
                continue
            }
            
            // Читаем конец лога для парсинга
            guard let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: logPath)) else { continue }
            let fileSize = fileHandle.seekToEndOfFile()
            let seekPos = max(0, Int64(fileSize) - 4096)
            fileHandle.seek(toFileOffset: UInt64(seekPos))
            let data = fileHandle.readDataToEndOfFile()
            fileHandle.closeFile()
            
            guard let tail = String(data: data, encoding: .utf8) else { continue }
            let lines = tail.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty })
            
            guard let lastLineStr = lines.last else { continue }
            guard let jsonData = lastLineStr.data(using: .utf8),
                  let lastStep = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                continue
            }
            
            let source = lastStep["source"] as? String
            let type = lastStep["type"] as? String
            
            // Если последний шаг — это ответ от модели без вызовов инструментов (финальное сообщение),
            // то агент уже закончил работу (idle).
            if source == "MODEL" && type == "PLANNER_RESPONSE" {
                let toolCalls = lastStep["tool_calls"] as? [[String: Any]]
                if toolCalls == nil || toolCalls!.isEmpty {
                    continue
                }
            }
            
            // Проверяем, ждет ли агент подтверждения
            if source == "MODEL" && type == "PLANNER_RESPONSE" {
                if let toolCalls = lastStep["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                    let hasApprovalTool = toolCalls.contains { tc in
                        if let name = tc["name"] as? String {
                            return name == "run_command" || name == "ask_permission"
                        }
                        return false
                    }
                    if hasApprovalTool && timeDiff > 3 {
                        localWaiting += 1
                        continue
                    }
                }
            }
            
            localActive += 1
        }
        
        return (localActive, localWaiting)
    }
    
    // Структуры для лимитов
    struct LimitInfo {
        let displayName: String
        let usedPercent: Int
        let description: String
    }
    
    struct AccountQuota {
        let email: String
        let status: String
        var limits5h: LimitInfo?
        var limitsWeekly: LimitInfo?
    }
    
    func sortKey(email1: String) -> String {
        let email = email1.lowercased()
        guard let atIdx = email.firstIndex(of: "@") else { return email }
        let user = String(email[..<atIdx])
        
        var textPart = ""
        var numPart = ""
        for char in user {
            if char.isNumber {
                numPart.append(char)
            } else {
                textPart.append(char)
            }
        }
        let num = Int(numPart) ?? 0
        return String(format: "%@%05d", textPart, num)
    }
    
    func loadQuotas() -> [AccountQuota] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: quotasPath)),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            return []
        }
        
        var result: [AccountQuota] = []
        for item in json {
            guard let email = item["email"] as? String,
                  let status = item["status"] as? String else { continue }
                  
            var quota = AccountQuota(email: email, status: status, limits5h: nil, limitsWeekly: nil)
            
            if status == "ok",
               let quotasDict = item["quotas"] as? [String: Any],
               let groups = quotasDict["groups"] as? [[String: Any]] {
               
                let geminiGroups = groups.filter { g in
                    if let name = g["displayName"] as? String {
                        return name.lowercased().contains("gemini")
                    }
                    return false
                }
                
                if let group = geminiGroups.first,
                   let limits = group["limits"] as? [String: Any] {
                   
                    if let h5 = limits["5h"] as? [String: Any] {
                        let dName = h5["displayName"] as? String ?? "Five Hour Limit"
                        let used = h5["used_percent"] as? Int ?? 0
                        let desc = h5["description"] as? String ?? ""
                        quota.limits5h = LimitInfo(displayName: dName, usedPercent: used, description: desc)
                    }
                    if let weekly = limits["weekly"] as? [String: Any] {
                        let dName = weekly["displayName"] as? String ?? "Weekly Limit"
                        let used = weekly["used_percent"] as? Int ?? 0
                        let desc = weekly["description"] as? String ?? ""
                        quota.limitsWeekly = LimitInfo(displayName: dName, usedPercent: used, description: desc)
                    }
                }
            }
            result.append(quota)
        }
        
        result.sort { sortKey(email1: $0.email) < sortKey(email1: $1.email) }
        return result
    }
    
    func loadAccounts() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: accountsPath)),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            return []
        }
        return json
    }
    
    func getActiveEmail(accounts: [[String: Any]]) -> String? {
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken';"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let rawValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
                return nil
            }
            
            // 1. Сначала ищем точное совпадение с db_value из accounts.json
            for acc in accounts {
                if let dbVal = acc["db_value"] as? String, !dbVal.isEmpty {
                    if rawValue == dbVal || rawValue.contains(dbVal) || dbVal.contains(rawValue) {
                        return acc["email"] as? String
                    }
                }
            }
            
            // 2. Если не нашли, декодируем base64 для поиска refresh_token внутри JSON-структуры
            var base64Str = rawValue.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            let remainder = base64Str.count % 4
            if remainder > 0 {
                base64Str += String(repeating: "=", count: 4 - remainder)
            }
            
            if let decodedData = Data(base64Encoded: base64Str),
               let decodedString = String(data: decodedData, encoding: .utf8) {
                for acc in accounts {
                    if let rToken = acc["refresh_token"] as? String, !rToken.isEmpty {
                        if decodedString.contains(rToken) {
                            return acc["email"] as? String
                        }
                    }
                }
            }
        } catch {
            print("Error reading SQLite: \(error)")
        }
        return nil
    }
    
    func formatTimeRemaining(_ description: String) -> String {
        if description.isEmpty { return "" }
        
        let pattern = "refresh in ([^\\.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: description, options: [], range: NSRange(description.startIndex..., in: description)) else {
            return ""
        }
        
        if let range = Range(match.range(at: 1), in: description) {
            var timeStr = String(description[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            timeStr = timeStr.replacingOccurrences(of: ",", with: "")
            timeStr = timeStr.replacingOccurrences(of: "days", with: "дн.")
            timeStr = timeStr.replacingOccurrences(of: "day", with: "дн.")
            timeStr = timeStr.replacingOccurrences(of: "hours", with: "ч.")
            timeStr = timeStr.replacingOccurrences(of: "hour", with: "ч.")
            timeStr = timeStr.replacingOccurrences(of: "minutes", with: "мин.")
            timeStr = timeStr.replacingOccurrences(of: "minute", with: "мин.")
            timeStr = timeStr.replacingOccurrences(of: "seconds", with: "сек.")
            timeStr = timeStr.replacingOccurrences(of: "second", with: "сек.")
            return "Сброс через: \(timeStr)"
        }
        return ""
    }
    
    func getLimitColor(percent: Int) -> NSColor {
        if percent < 15 {
            return colorRed
        } else if percent < 40 {
            return colorYellow
        } else {
            return colorGreen
        }
    }
    
    // Вспомогательная функция сборки текстовых пунктов меню (без жирных шрифтов вообще)
    func createStyledItem(title: String, fontName: String = "System", fontSize: CGFloat = 14, color: NSColor? = nil, action: Selector? = nil, representedObject: Any? = nil, sfSymbol: String? = nil, sfColor: NSColor? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let obj = representedObject {
            item.representedObject = obj
        }
        
        let font: NSFont
        if fontName == "System" || fontName == "System-Bold" {
            font = NSFont.systemFont(ofSize: fontSize)
        } else {
            font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        }
        
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let c = color {
            attributes[.foregroundColor] = c
        }
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        
        if let symbol = sfSymbol {
            if #available(macOS 12.0, *), let sColor = sfColor {
                let config = NSImage.SymbolConfiguration(paletteColors: [sColor])
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            } else {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
        }
        
        return item
    }
    
    func rebuildMenu() {
        menu.removeAllItems()
        
        let quotas = loadQuotas()
        let accounts = loadAccounts()
        let activeEmail = getActiveEmail(accounts: accounts)
        
        // 1. Сводные общие лимиты
        var totalWeekly = 0
        var total5h = 0
        var validCount = 0
        
        for q in quotas {
            if q.status == "ok" {
                let weeklyPercent = q.limitsWeekly?.usedPercent ?? 0
                var fiveHourPercent = q.limits5h?.usedPercent ?? 0
                if weeklyPercent < 10 {
                    fiveHourPercent = 0
                }
                totalWeekly += weeklyPercent
                total5h += fiveHourPercent
                validCount += 1
            }
        }
        
        if validCount > 0 {
            let avgWeekly = Double(totalWeekly) / Double(validCount)
            let avg5h = Double(total5h) / Double(validCount)
            
            // Заголовок общей секции выровнен по левому краю с помощью MenuHeaderView
            let headerItem = NSMenuItem()
            headerItem.view = MenuHeaderView(
                title: "ОБЩИЕ ЛИМИТЫ",
                iconName: "chart.bar.doc.horizontal.fill",
                iconColor: colorPurple,
                textColor: colorPurple
            )
            menu.addItem(headerItem)
            
            // Планка Five Hour Limit
            let item5h = NSMenuItem()
            item5h.view = QuotaProgressView(title: "Five Hour Limit", percent: avg5h, iconName: "clock", iconColor: colorPurple, barColor: colorPurple, timeRemaining: "")
            menu.addItem(item5h)
            
            // Планка Weekly Limit
            let itemWeekly = NSMenuItem()
            itemWeekly.view = QuotaProgressView(title: "Weekly Limit", percent: avgWeekly, iconName: "calendar", iconColor: colorPurple, barColor: colorPurple, timeRemaining: "")
            menu.addItem(itemWeekly)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // 2. Лимиты по каждому аккаунту
        let emailToDbValue = accounts.reduce(into: [String: String]()) { dict, acc in
            if let email = acc["email"] as? String, let dbVal = acc["db_value"] as? String {
                dict[email.lowercased()] = dbVal
            }
        }
        
        for (idx, q) in quotas.enumerated() {
            if idx > 0 {
                menu.addItem(NSMenuItem.separator())
            }
            
            let emailLower = q.email.lowercased()
            let isActive = (activeEmail?.lowercased() == emailLower)
            let dbValue = emailToDbValue[emailLower]
            
            // Название аккаунта (стандартный NSMenuItem с иконкой для нативной синей подсветки при наведении)
            let emailItem: NSMenuItem
            if isActive {
                emailItem = createStyledItem(
                    title: q.email,
                    fontName: "System",
                    fontSize: 13,
                    color: colorGreen,
                    sfSymbol: "checkmark.circle.fill",
                    sfColor: colorGreen
                )
            } else if dbValue != nil {
                // Активная строка-кнопка для входа
                emailItem = createStyledItem(
                    title: q.email,
                    fontName: "System",
                    fontSize: 13,
                    color: NSColor.labelColor,
                    action: #selector(switchAccountClicked(_:)),
                    representedObject: q.email,
                    sfSymbol: "person.crop.circle.fill",
                    sfColor: NSColor.secondaryLabelColor
                )
            } else {
                emailItem = createStyledItem(
                    title: q.email,
                    fontName: "System",
                    fontSize: 13,
                    color: NSColor.secondaryLabelColor,
                    sfSymbol: "person.crop.circle.fill",
                    sfColor: NSColor.secondaryLabelColor
                )
            }
            menu.addItem(emailItem)
            
            if !isActive && dbValue == nil {
                menu.addItem(createStyledItem(
                    title: "  Сессия не импортирована (войдите один раз в IDE)",
                    fontName: "System",
                    fontSize: 11,
                    color: NSColor.secondaryLabelColor
                ))
            }
            
            if q.status == "auth_error" {
                menu.addItem(createStyledItem(
                    title: "  Ошибка авторизации. Обновите токен",
                    fontName: "System",
                    fontSize: 12,
                    color: colorRed
                ))
                continue
            }
            
            // Вывод лимитов
            let weeklyPercent = q.limitsWeekly?.usedPercent ?? 100
            
            var timeRem5h = ""
            var timeRemWeekly = ""
            
            if let h5 = q.limits5h {
                let desc = weeklyPercent < 10 ? "Недельный лимит исчерпан" : h5.description
                timeRem5h = formatTimeRemaining(desc)
            }
            if let weekly = q.limitsWeekly {
                timeRemWeekly = formatTimeRemaining(weekly.description)
            }
            
            if let h5 = q.limits5h {
                var used = Double(h5.usedPercent)
                if weeklyPercent < 10 {
                    used = 0
                }
                
                let limitColor = getLimitColor(percent: Int(used))
                let itemH5 = NSMenuItem()
                itemH5.view = QuotaProgressView(
                    title: "Five Hour Limit",
                    percent: used,
                    iconName: "clock",
                    iconColor: NSColor.secondaryLabelColor,
                    barColor: limitColor,
                    timeRemaining: timeRem5h
                )
                menu.addItem(itemH5)
            }
            
            if let weekly = q.limitsWeekly {
                let limitColor = getLimitColor(percent: weekly.usedPercent)
                let itemW = NSMenuItem()
                itemW.view = QuotaProgressView(
                    title: "Weekly Limit",
                    percent: Double(weekly.usedPercent),
                    iconName: "calendar",
                    iconColor: NSColor.secondaryLabelColor,
                    barColor: limitColor,
                    timeRemaining: timeRemWeekly
                )
                menu.addItem(itemW)
            }
        }
        
        // 3. Системные действия внизу
        menu.addItem(NSMenuItem.separator())
        
        let mtime = (try? FileManager.default.attributesOfItem(atPath: quotasPath)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let updateStr = formatter.string(from: Date(timeIntervalSince1970: mtime))
        
        menu.addItem(createStyledItem(
            title: "Последнее обновление: \(updateStr)",
            fontName: "System",
            fontSize: 11,
            color: NSColor.secondaryLabelColor,
            sfSymbol: "arrow.clockwise.circle",
            sfColor: NSColor.secondaryLabelColor
        ))
        
        menu.addItem(createStyledItem(
            title: "Обновить квоты сейчас",
            fontName: "System",
            fontSize: 14,
            action: #selector(refreshClicked(_:)),
            sfSymbol: "arrow.clockwise",
            sfColor: colorGreen
        ))
        
        menu.addItem(createStyledItem(
            title: "Добавить/Обновить аккаунт",
            fontName: "System",
            fontSize: 14,
            action: #selector(authClicked(_:)),
            sfSymbol: "person.badge.plus",
            sfColor: NSColor.systemBlue
        ))
        
        menu.addItem(createStyledItem(
            title: "Открыть папку проекта",
            fontName: "System",
            fontSize: 14,
            action: #selector(openFolderClicked(_:)),
            sfSymbol: "folder",
            sfColor: NSColor.systemYellow
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(createStyledItem(
            title: "Выйти",
            fontName: "System",
            fontSize: 14,
            action: #selector(quitClicked(_:)),
            sfSymbol: "power",
            sfColor: colorRed
        ))
    }
    
    // Вспомогательная функция запуска Python скриптов
    func runPythonScript(_ scriptName: String, arguments: [String] = []) {
        var pythonBin = "python3"
        let candidates = [
            "\(projectDir)/.venv/bin/python3",
            "\(projectDir)/venv/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                pythonBin = candidate
                break
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonBin)
        process.arguments = ["\(projectDir)/\(scriptName)"] + arguments
        
        do {
            try process.run()
        } catch {
            print("Error running script \(scriptName): \(error)")
        }
    }
    
    @objc func switchAccountClicked(_ sender: NSMenuItem) {
        guard let email = sender.representedObject as? String else { return }
        runPythonScript("switch_account.py", arguments: [email])
    }
    
    @objc func refreshClicked(_ sender: NSMenuItem) {
        runPythonScript("fetcher.py")
    }
    
    @objc func authClicked(_ sender: NSMenuItem) {
        let scriptPath = "\(projectDir)/auth.py"
        var pythonBin = "python3"
        let candidates = [
            "\(projectDir)/.venv/bin/python3",
            "\(projectDir)/venv/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                pythonBin = candidate
                break
            }
        }
        
        let appleScript = "tell application \"Terminal\" to do script \"'\(pythonBin)' '\(scriptPath)'\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try? process.run()
    }
    
    @objc func openFolderClicked(_ sender: NSMenuItem) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [projectDir]
        try? process.run()
    }
    
    @objc func quitClicked(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}

// Запуск приложения
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
