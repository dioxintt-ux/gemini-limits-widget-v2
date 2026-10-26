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
    var remainingPercent: Int? = nil
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 22))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Определяем цвет иконки в зависимости от оставшихся лимитов
        let color: NSColor
        if let pct = remainingPercent {
            if pct < 5 {
                color = NSColor(hex: "#FF3B30") // Apple Red
            } else if pct < 20 {
                color = NSColor(hex: "#FFCC00") // Apple Yellow
            } else {
                color = isActive ? NSColor(hex: "#30D158") : NSColor.controlTextColor
            }
        } else {
            color = isActive ? NSColor(hex: "#30D158") : NSColor.controlTextColor
        }
        
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
    override var allowsVibrancy: Bool {
        return true
    }
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    
    init(title: String, iconName: String, iconColor: NSColor, textColor: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
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

// Кастомный выделенный синей каемкой блок для Argon (Google AI Ultra)
class ArgonCardView: NSView {
    override var allowsVibrancy: Bool { return true }
    
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let emailLabel = NSTextField(labelWithString: "")
    
    // 5-часовой лимит
    let icon5h = NSImageView()
    let label5h = NSTextField(labelWithString: "5-часовой лимит")
    let percent5hLabel = NSTextField(labelWithString: "")
    var percent5h: Double = 100
    var color5h: NSColor = NSColor(hex: "#0A84FF")
    
    // Недельный лимит
    let iconWeekly = NSImageView()
    let labelWeekly = NSTextField(labelWithString: "Недельный лимит")
    let percentWeeklyLabel = NSTextField(labelWithString: "")
    var percentWeekly: Double = 100
    var colorWeekly: NSColor = NSColor(hex: "#0A84FF")
    
    // Таймер сброса
    let iconTimer = NSImageView()
    let labelTimer = NSTextField(labelWithString: "")
    var hasTimer: Bool = false
    
    let borderColor = NSColor(hex: "#0A84FF") // акцентный синий цвет Apple
    
    init(email: String, isActive: Bool, percent5h: Double, color5h: NSColor, percentWeekly: Double, colorWeekly: NSColor, timerText: String) {
        self.hasTimer = !timerText.isEmpty
        self.percent5h = percent5h
        self.color5h = color5h
        self.percentWeekly = percentWeekly
        self.colorWeekly = colorWeekly
        
        let cardHeight: CGFloat = hasTimer ? 98 : 78
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: cardHeight))
        self.autoresizingMask = [.width]
        
        // Header elements
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(emailLabel)
        
        // 5h elements
        addSubview(icon5h)
        addSubview(label5h)
        addSubview(percent5hLabel)
        
        // Weekly elements
        addSubview(iconWeekly)
        addSubview(labelWeekly)
        addSubview(percentWeeklyLabel)
        
        if hasTimer {
            addSubview(iconTimer)
            addSubview(labelTimer)
        }
        
        // Setup Icon & Title
        let iconName = isActive ? "checkmark.circle.fill" : "person.crop.circle.fill"
        let iconColor = isActive ? NSColor(hex: "#30D158") : borderColor
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        if #available(macOS 12.0, *) {
            iconView.image = iconView.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
        }
        
        titleLabel.stringValue = "Argon"
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        
        emailLabel.stringValue = email
        emailLabel.font = NSFont.systemFont(ofSize: 11)
        emailLabel.textColor = NSColor.secondaryLabelColor
        emailLabel.isEditable = false
        emailLabel.isBordered = false
        emailLabel.drawsBackground = false
        
        // 5h row
        icon5h.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        if #available(macOS 12.0, *) {
            icon5h.image = icon5h.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [borderColor]))
        }
        label5h.font = NSFont.systemFont(ofSize: 12)
        label5h.textColor = NSColor.labelColor
        label5h.isEditable = false
        label5h.isBordered = false
        label5h.drawsBackground = false
        
        percent5hLabel.stringValue = "\(Int(round(percent5h)))%"
        percent5hLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percent5hLabel.textColor = NSColor.secondaryLabelColor
        percent5hLabel.alignment = .right
        percent5hLabel.isEditable = false
        percent5hLabel.isBordered = false
        percent5hLabel.drawsBackground = false
        
        // Weekly row
        iconWeekly.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        if #available(macOS 12.0, *) {
            iconWeekly.image = iconWeekly.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [borderColor]))
        }
        labelWeekly.font = NSFont.systemFont(ofSize: 12)
        labelWeekly.textColor = NSColor.labelColor
        labelWeekly.isEditable = false
        labelWeekly.isBordered = false
        labelWeekly.drawsBackground = false
        
        percentWeeklyLabel.stringValue = "\(Int(round(percentWeekly)))%"
        percentWeeklyLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percentWeeklyLabel.textColor = NSColor.secondaryLabelColor
        percentWeeklyLabel.alignment = .right
        percentWeeklyLabel.isEditable = false
        percentWeeklyLabel.isBordered = false
        percentWeeklyLabel.drawsBackground = false
        
        // Timer row
        if hasTimer {
            iconTimer.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
            if #available(macOS 12.0, *) {
                iconTimer.image = iconTimer.image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))
            }
            labelTimer.stringValue = timerText
            labelTimer.font = NSFont.systemFont(ofSize: 11)
            labelTimer.textColor = NSColor.secondaryLabelColor
            labelTimer.isEditable = false
            labelTimer.isBordered = false
            labelTimer.drawsBackground = false
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        
        // Header
        iconView.frame = NSRect(x: 18, y: h - 24, width: 14, height: 14)
        titleLabel.frame = NSRect(x: 36, y: h - 26, width: 50, height: 18)
        emailLabel.frame = NSRect(x: 88, y: h - 25, width: w - 100, height: 16)
        
        // 5h row
        let row5hY = h - 48
        icon5h.frame = NSRect(x: 18, y: row5hY, width: 13, height: 13)
        label5h.frame = NSRect(x: 36, y: row5hY - 2, width: 120, height: 16)
        percent5hLabel.frame = NSRect(x: w - 50, y: row5hY - 2, width: 35, height: 16)
        
        // Weekly row
        let rowWY: CGFloat = hasTimer ? (h - 70) : 8
        iconWeekly.frame = NSRect(x: 18, y: rowWY, width: 13, height: 13)
        labelWeekly.frame = NSRect(x: 36, y: rowWY - 2, width: 120, height: 16)
        percentWeeklyLabel.frame = NSRect(x: w - 50, y: rowWY - 2, width: 35, height: 16)
        
        // Timer row
        if hasTimer {
            iconTimer.frame = NSRect(x: 18, y: 7, width: 12, height: 12)
            labelTimer.frame = NSRect(x: 36, y: 5, width: w - 55, height: 14)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let w = bounds.width
        let h = bounds.height
        let insetRect = NSRect(x: 8, y: 3, width: w - 16, height: h - 6)
        let borderPath = NSBezierPath(roundedRect: insetRect, xRadius: 8, yRadius: 8)
        
        // Легкая подложка
        borderColor.withAlphaComponent(0.08).setFill()
        borderPath.fill()
        
        // Четкая синяя каемочка
        borderColor.withAlphaComponent(0.85).setStroke()
        borderPath.lineWidth = 1.4
        borderPath.stroke()
        
        let barX: CGFloat = 160
        let barWidth = w - barX - 55
        
        // 5h прогресс-бар
        let row5hY = h - 48
        let bar5hY = row5hY + 3
        let track5h = NSRect(x: barX, y: bar5hY, width: barWidth, height: 6)
        NSColor.quaternaryLabelColor.set()
        NSBezierPath(roundedRect: track5h, xRadius: 3, yRadius: 3).fill()
        if percent5h > 0 {
            let fillWidth = max(6, CGFloat(percent5h / 100.0) * barWidth)
            color5h.set()
            NSBezierPath(roundedRect: NSRect(x: barX, y: bar5hY, width: fillWidth, height: 6), xRadius: 3, yRadius: 3).fill()
        }
        
        // Weekly прогресс-бар
        let rowWY: CGFloat = hasTimer ? (h - 70) : 8
        let barWY = rowWY + 3
        let trackW = NSRect(x: barX, y: barWY, width: barWidth, height: 6)
        NSColor.quaternaryLabelColor.set()
        NSBezierPath(roundedRect: trackW, xRadius: 3, yRadius: 3).fill()
        if percentWeekly > 0 {
            let fillWidth = max(6, CGFloat(percentWeekly / 100.0) * barWidth)
            colorWeekly.set()
            NSBezierPath(roundedRect: NSRect(x: barX, y: barWY, width: fillWidth, height: 6), xRadius: 3, yRadius: 3).fill()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let menuItem = self.enclosingMenuItem {
            if menuItem.isEnabled, let action = menuItem.action, let target = menuItem.target {
                _ = target.perform(action, with: menuItem)
                menuItem.menu?.cancelTracking()
            }
        } else {
            super.mouseDown(with: event)
        }
    }
}

// Кастомный графический прогресс-бар в стиле Apple
class QuotaProgressView: NSView {
    override var allowsVibrancy: Bool {
        return true
    }
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
        
        // Начальная ширина 360pt для нормального размещения русского текста
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: height))
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
        titleLabel.frame = NSRect(x: 32, y: row1Y - 1, width: 125, height: 16)
        
        // Прижимаем проценты к правому краю
        percentLabel.frame = NSRect(x: w - 45, y: row1Y - 1, width: 35, height: 16)
        
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
        
        // Прогресс-бар начинаем с x: 160 (после названия "Недельный лимит")
        let barX: CGFloat = 160
        let barWidth = w - barX - 50
        
        // Отрисовка подложки (трека)
        let trackRect = NSRect(x: barX, y: barY, width: barWidth, height: 6)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3)
        NSColor.quaternaryLabelColor.set()
        trackPath.fill()
        
        // Отрисовка заполненной части прогресс-бара
        if percent > 0 {
            let fillWidth = max(6, CGFloat(percent / 100.0) * barWidth)
            let fillRect = NSRect(x: barX, y: barY, width: fillWidth, height: 6)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
            barColor.set()
            fillPath.fill()
        }
    }
}

// MARK: - Workstation Models & Views

enum WidgetMode: Int {
    case gemini = 0
    case workstation = 1
}

struct WorkstationData: Decodable {
    let status: String
    let updated_at: Double?
    let host: HostStats?
    let container: ContainerStats?
    let summary: SummaryStats?
    let sessions: [SessionItem]?
    let error: String?
}

struct HostStats: Decodable {
    let load_1m: Double
    let load_5m: Double
    let load_15m: Double
    let ram_total_mb: Int
    let ram_used_mb: Int
    let swap_total_mb: Int
    let swap_used_mb: Int
}

struct ContainerStats: Decodable {
    let ram_used_mb: Double
    let ram_limit_mb: Double
    let ram_percent: Double
    let pids_count: Int
}

struct SummaryStats: Decodable {
    let total: Int
    let running: Int?
    let idle: Int?
    let new: Int?
    let orphan: Int?
}

struct SessionItem: Decodable {
    let pid: Int
    let tty: String
    let is_active: Bool
    let cpu: Double
    let rss_mb: Double
    let etime: String
    let project: String
    let cwd: String
    let cid: String
    let title: String
    let profile: String
    let indicator_color: String?
    let indicator_text: String?
    let status_code: String?
}

class ModeSwitchView: NSView {
    override var allowsVibrancy: Bool { return true }
    let segmentedControl = NSSegmentedControl(labels: ["Лимиты Gemini", "Agy Workstation"], trackingMode: .selectOne, target: nil, action: nil)
    
    init(selectedMode: WidgetMode, target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 36))
        self.autoresizingMask = [.width]
        
        segmentedControl.selectedSegment = selectedMode.rawValue
        segmentedControl.target = target
        segmentedControl.action = action
        segmentedControl.segmentStyle = .rounded
        segmentedControl.controlSize = .regular
        segmentedControl.frame = NSRect(x: 14, y: 5, width: 332, height: 26)
        
        addSubview(segmentedControl)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class SessionRowView: NSView {
    override var allowsVibrancy: Bool { return true }
    
    let statusDot = NSTextField(labelWithString: "●")
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    
    init(session: SessionItem) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 42))
        self.autoresizingMask = [.width]
        
        statusDot.font = NSFont.systemFont(ofSize: 10)
        switch session.indicator_color {
        case "green":
            statusDot.textColor = NSColor(hex: "#30D158") // Зеленый: работает в моменте
        case "yellow":
            statusDot.textColor = NSColor(hex: "#FFCC00") // Желтый: диалог открыт, в ожидании
        case "red":
            statusDot.textColor = NSColor(hex: "#FF3B30") // Красный: ошибка или висит
        case "gray":
            statusDot.textColor = NSColor(hex: "#8E8E93") // Серый: новый диалог, ожидает
        default:
            statusDot.textColor = session.is_active ? NSColor(hex: "#8E8E93") : NSColor(hex: "#FF3B30")
        }
        
        titleLabel.font = NSFont.systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        let projText = "[\(session.project)] "
        let titleAttr = NSMutableAttributedString(string: projText, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor(hex: "#0A84FF")
        ])
        titleAttr.append(NSAttributedString(string: "\(session.profile): \(session.title)", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]))
        titleLabel.attributedStringValue = titleAttr
        
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        let statusDesc = session.indicator_text ?? (session.is_active ? "Активен" : "Висит")
        subtitleLabel.stringValue = "PID: \(session.pid)  •  \(session.rss_mb) MB  •  \(statusDesc)  •  \(session.etime)"
        
        addSubview(statusDot)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        let w = bounds.width
        statusDot.frame = NSRect(x: 10, y: 22, width: 14, height: 16)
        titleLabel.frame = NSRect(x: 28, y: 20, width: w - 38, height: 18)
        subtitleLabel.frame = NSRect(x: 28, y: 3, width: w - 38, height: 16)
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
    var workstationStatusPath: String { "\(projectDir)/workstation_status.json" }
    var dbPath: String { NSHomeDirectory() + "/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb" }
    
    var currentMode: WidgetMode = .gemini
    
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
    var lastBrainMtime: TimeInterval = 0
    
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
            runPythonScript("fetch_workstation.py")
        }
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        // При открытии меню запускаем быстрое асинхронное обновление в фоне
        // Обновляем метку времени, чтобы фоновый таймер не дублировал запрос сразу после этого
        lastQuotaUpdateTime = Date().timeIntervalSince1970
        runPythonScript("fetcher.py")
        runPythonScript("fetch_workstation.py")
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
        
        currentStatus = newStatus
        updateStatusBarIcon()
        
        rebuildMenu()
    }
    
    func updateStatusBarIcon() {
        let minPercent = getActiveAccountMinLimitPercent()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.loaderView.remainingPercent = minPercent
            
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
                self.loaderView.needsDisplay = true
                
                self.statusItem.length = 24
                self.statusItem.button?.title = ""
                self.statusItem.button?.image = nil
            }
        }
    }
    
    func getActiveAccountMinLimitPercent() -> Int? {
        let quotas = loadQuotas()
        let accounts = loadAccounts()
        guard let activeEmail = getActiveEmail(accounts: accounts) else { return nil }
        
        if let activeQuota = quotas.first(where: { $0.email.lowercased() == activeEmail.lowercased() }) {
            if activeQuota.status == "ok", let limits5h = activeQuota.limits5h {
                return limits5h.usedPercent
            }
        }
        return nil
    }
    
    // Чтение состояния диалогов из transcript.jsonl
    func scanDialogues() -> (active: Int, waiting: Int) {
        let now = Date().timeIntervalSince1970
        let brainPattern = NSHomeDirectory() + "/.gemini/antigravity-ide/brain"
        let currentBrainMtime = (try? FileManager.default.attributesOfItem(atPath: brainPattern)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        
        // Обновляем список путей к логам, только если изменилась папка brain (создан новый диалог) или раз в 10 секунд для надежности
        if currentBrainMtime != lastBrainMtime || now - lastScanTime > 10.0 || cachedLogPaths.isEmpty {
            lastBrainMtime = currentBrainMtime
            lastScanTime = now
            var tempPaths: [String] = []
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
            
            // Если лог не обновлялся 300 секунд (5 минут) — считаем диалог неактивным.
            // При завершении диалога (финальный ответ модели) он перейдет в неактивный статус мгновенно ниже.
            if timeDiff > 300.0 {
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
                
                if let group = geminiGroups.first ?? groups.first,
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
    
    // MARK: - Workstation Menu
    
    func loadWorkstationStatus() -> WorkstationData? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: workstationStatusPath)),
              let ws = try? JSONDecoder().decode(WorkstationData.self, from: data) else {
            return nil
        }
        return ws
    }
    
    func buildWorkstationMenu() {
        let ws = loadWorkstationStatus()
        
        let isOnline = (ws?.status == "online")
        let hostStatusColor = isOnline ? colorGreen : colorRed
        
        // 1. Заголовок сервера DIO
        let headerItem = NSMenuItem()
        headerItem.view = MenuHeaderView(
            title: isOnline ? "СЕРВЕР DIO: ОНЛАЙН" : "СЕРВЕР DIO: ОФФЛАЙН",
            iconName: isOnline ? "server.rack" : "exclamationmark.triangle.fill",
            iconColor: hostStatusColor,
            textColor: hostStatusColor
        )
        menu.addItem(headerItem)
        
        if let ws = ws, isOnline {
            if let host = ws.host {
                // Load Average строка
                let loadColor: NSColor
                if host.load_1m > 12.0 {
                    loadColor = colorRed
                } else if host.load_1m > 6.0 {
                    loadColor = colorYellow
                } else {
                    loadColor = colorGreen
                }
                
                let loadItem = createStyledItem(
                    title: String(format: "Load Average: %.2f, %.2f, %.2f (1m, 5m, 15m)", host.load_1m, host.load_5m, host.load_15m),
                    fontName: "System",
                    fontSize: 12,
                    color: NSColor.labelColor,
                    sfSymbol: "cpu",
                    sfColor: loadColor
                )
                menu.addItem(loadItem)
                
                // Swap строка
                let swapColor = (host.swap_used_mb > 100) ? colorRed : colorGreen
                let swapItem = createStyledItem(
                    title: "Swap: \(host.swap_used_mb) MB / \(host.swap_total_mb) MB",
                    fontName: "System",
                    fontSize: 12,
                    color: (host.swap_used_mb > 100) ? colorRed : NSColor.secondaryLabelColor,
                    sfSymbol: "arrow.triangle.swap",
                    sfColor: swapColor
                )
                menu.addItem(swapItem)
            }
            
            if let cont = ws.container {
                // Контейнер RAM прогресс-бар
                let ramUsedGb = String(format: "%.1f", cont.ram_used_mb / 1024.0)
                let ramLimitGb = String(format: "%.1f", cont.ram_limit_mb / 1024.0)
                let ramColor: NSColor
                if cont.ram_percent > 85.0 {
                    ramColor = colorRed
                } else if cont.ram_percent > 70.0 {
                    ramColor = colorYellow
                } else {
                    ramColor = NSColor(hex: "#0A84FF")
                }
                
                let contItem = NSMenuItem()
                contItem.view = QuotaProgressView(
                    title: "RAM контейнера",
                    percent: cont.ram_percent,
                    iconName: "shippingbox.fill",
                    iconColor: ramColor,
                    barColor: ramColor,
                    timeRemaining: "\(ramUsedGb)G / \(ramLimitGb)G (\(cont.pids_count) PID)"
                )
                menu.addItem(contItem)
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // 2. Список сессий
            let total = ws.summary?.total ?? 0
            let running = ws.summary?.running ?? 0
            let idle = ws.summary?.idle ?? 0
            let newCount = ws.summary?.new ?? 0
            let orphan = ws.summary?.orphan ?? 0
            
            let sessionsHeader = NSMenuItem()
            let sHeaderColor = (orphan > 0) ? colorRed : (running > 0 ? colorGreen : colorPurple)
            sessionsHeader.view = MenuHeaderView(
                title: "СЕССИИ AGY (В работе: \(running) | Ожидают: \(idle) | Новых: \(newCount) | Всего: \(total))",
                iconName: "terminal.fill",
                iconColor: sHeaderColor,
                textColor: sHeaderColor
            )
            menu.addItem(sessionsHeader)
            
            if let sessions = ws.sessions, !sessions.isEmpty {
                for s in sessions {
                    let sItem = NSMenuItem()
                    sItem.view = SessionRowView(session: s)
                    menu.addItem(sItem)
                }
            } else {
                let emptyItem = createStyledItem(
                    title: "Нет запущенных сессий agy",
                    fontName: "System",
                    fontSize: 12,
                    color: NSColor.secondaryLabelColor,
                    sfSymbol: "checkmark.circle",
                    sfColor: colorGreen
                )
                menu.addItem(emptyItem)
            }
        } else {
            let errorItem = createStyledItem(
                title: ws?.error ?? "Не удалось получить данные по SSH",
                fontName: "System",
                fontSize: 12,
                color: colorRed,
                sfSymbol: "xmark.octagon.fill",
                sfColor: colorRed
            )
            menu.addItem(errorItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Действия управления Workstation
        let timeStr: String
        if let ts = ws?.updated_at, ts > 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            timeStr = formatter.string(from: Date(timeIntervalSince1970: ts))
        } else {
            timeStr = "—"
        }
        
        menu.addItem(createStyledItem(
            title: "Последнее обновление: \(timeStr)",
            fontName: "System",
            fontSize: 11,
            color: NSColor.secondaryLabelColor,
            sfSymbol: "clock",
            sfColor: NSColor.secondaryLabelColor
        ))
        
        menu.addItem(createStyledItem(
            title: "Обновить статус Workstation",
            fontName: "System",
            fontSize: 14,
            action: #selector(refreshWorkstationClicked(_:)),
            sfSymbol: "arrow.clockwise",
            sfColor: colorGreen
        ))
        
        menu.addItem(createStyledItem(
            title: "Перезапустить контейнер agy-workstation",
            fontName: "System",
            fontSize: 14,
            action: #selector(restartWorkstationClicked(_:)),
            sfSymbol: "arrow.clockwise.circle",
            sfColor: colorRed
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
    
    func rebuildMenu() {
        menu.removeAllItems()
        
        // 0. Верхний переключатель режимов: Лимиты Gemini | Agy Workstation
        let modeItem = NSMenuItem()
        modeItem.view = ModeSwitchView(selectedMode: currentMode, target: self, action: #selector(modeChanged(_:)))
        menu.addItem(modeItem)
        menu.addItem(NSMenuItem.separator())
        
        if currentMode == .workstation {
            buildWorkstationMenu()
            return
        }
        
        let quotas = loadQuotas()
        let accounts = loadAccounts()
        let activeEmail = getActiveEmail(accounts: accounts)
        
        let emailToDbValue = accounts.reduce(into: [String: String]()) { dict, acc in
            if let email = acc["email"] as? String, let dbVal = acc["db_value"] as? String {
                dict[email.lowercased()] = dbVal
            }
        }
        let emailToAlias = accounts.reduce(into: [String: String]()) { dict, acc in
            if let email = acc["email"] as? String, let alias = acc["alias"] as? String {
                dict[email.lowercased()] = alias
            }
        }
        
        // Разделяем Argon и воркеров (1-7)
        let argonQuota = quotas.first { $0.email.lowercased() == "dioxintt@gmail.com" }
        let workerQuotas = quotas.filter { $0.email.lowercased() != "dioxintt@gmail.com" }
        
        // 1. Блок Argon (Google AI Ultra), выделенный синей каемкой над общими лимитами
        if let argon = argonQuota {
            let emailLower = argon.email.lowercased()
            let isActive = (activeEmail?.lowercased() == emailLower)
            
            let weeklyPercent = argon.limitsWeekly?.usedPercent ?? 100
            var timeRemWeekly = ""
            if let weekly = argon.limitsWeekly {
                let desc = weekly.usedPercent < 100 ? weekly.description : ""
                timeRemWeekly = formatTimeRemaining(desc)
            }
            
            var used5h: Double = 100
            var color5h = NSColor(hex: "#0A84FF")
            if let h5 = argon.limits5h {
                used5h = Double(h5.usedPercent)
                if weeklyPercent < 10 { used5h = 0 }
                color5h = getLimitColor(percent: Int(used5h))
            }
            
            var usedWeekly: Double = 100
            var colorWeekly = NSColor(hex: "#0A84FF")
            if let w = argon.limitsWeekly {
                usedWeekly = Double(w.usedPercent)
                colorWeekly = getLimitColor(percent: Int(w.usedPercent))
            }
            
            let cardView = ArgonCardView(
                email: argon.email,
                isActive: isActive,
                percent5h: used5h,
                color5h: color5h,
                percentWeekly: usedWeekly,
                colorWeekly: colorWeekly,
                timerText: timeRemWeekly
            )
            
            let argonItem = NSMenuItem()
            argonItem.view = cardView
            argonItem.target = self
            argonItem.action = #selector(switchAccountClicked(_:))
            argonItem.representedObject = argon.email
            menu.addItem(argonItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // 2. Сводные общие лимиты (строго по воркерам 1-7, Аргон исключен)
        var totalWeekly = 0
        var total5h = 0
        var validCount = 0
        
        for q in workerQuotas {
            if q.status == "ok", let w = q.limitsWeekly, let h5 = q.limits5h {
                let weeklyPercent = w.usedPercent
                var fiveHourPercent = h5.usedPercent
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
            
            let headerItem = NSMenuItem()
            headerItem.view = MenuHeaderView(
                title: "ОБЩИЕ ЛИМИТЫ (ВОРКЕРЫ 1-7)",
                iconName: "chart.bar.doc.horizontal.fill",
                iconColor: colorPurple,
                textColor: colorPurple
            )
            menu.addItem(headerItem)
            
            let item5h = NSMenuItem()
            item5h.view = QuotaProgressView(title: "5-часовой лимит", percent: avg5h, iconName: "clock", iconColor: colorPurple, barColor: colorPurple, timeRemaining: "")
            menu.addItem(item5h)
            
            let itemWeekly = NSMenuItem()
            itemWeekly.view = QuotaProgressView(title: "Недельный лимит", percent: avgWeekly, iconName: "calendar", iconColor: colorPurple, barColor: colorPurple, timeRemaining: "")
            menu.addItem(itemWeekly)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // 3. Лимиты по каждому аккаунту воркера
        let workersHeader = NSMenuItem()
        workersHeader.view = MenuHeaderView(
            title: "АККАУНТЫ ВОРКЕРОВ",
            iconName: "person.3.fill",
            iconColor: NSColor.secondaryLabelColor,
            textColor: NSColor.secondaryLabelColor
        )
        menu.addItem(workersHeader)
        
        for (idx, q) in workerQuotas.enumerated() {
            if idx > 0 {
                menu.addItem(NSMenuItem.separator())
            }
            
            let emailLower = q.email.lowercased()
            let isActive = (activeEmail?.lowercased() == emailLower)
            let dbValue = emailToDbValue[emailLower]
            let displayTitle = emailToAlias[emailLower] ?? q.email
            
            let emailItem: NSMenuItem
            if isActive {
                emailItem = createStyledItem(
                    title: displayTitle,
                    fontName: "System",
                    fontSize: 13,
                    color: colorGreen,
                    sfSymbol: "checkmark.circle.fill",
                    sfColor: colorGreen
                )
            } else if dbValue != nil {
                emailItem = createStyledItem(
                    title: displayTitle,
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
                    title: displayTitle,
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
                let desc = weeklyPercent < 10 ? "Недельный лимит исчерпан" : (h5.usedPercent < 100 ? h5.description : "")
                timeRem5h = formatTimeRemaining(desc)
            }
            if let weekly = q.limitsWeekly {
                let desc = weekly.usedPercent < 100 ? weekly.description : ""
                timeRemWeekly = formatTimeRemaining(desc)
            }
            
            if let h5 = q.limits5h {
                var used = Double(h5.usedPercent)
                if weeklyPercent < 10 {
                    used = 0
                }
                
                let limitColor = getLimitColor(percent: Int(used))
                let itemH5 = NSMenuItem()
                itemH5.view = QuotaProgressView(
                    title: "5-часовой лимит",
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
                    title: "Недельный лимит",
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
    
    @objc func modeChanged(_ sender: NSSegmentedControl) {
        if let mode = WidgetMode(rawValue: sender.selectedSegment) {
            currentMode = mode
            if currentMode == .workstation {
                runPythonScript("fetch_workstation.py")
            }
            rebuildMenu()
        }
    }
    
    @objc func refreshWorkstationClicked(_ sender: NSMenuItem) {
        runPythonScript("fetch_workstation.py")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.rebuildMenu()
        }
    }
    
    @objc func reapSessionsClicked(_ sender: NSMenuItem) {
        runPythonScript("fetch_workstation.py", arguments: ["--reap"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.rebuildMenu()
        }
    }
    
    @objc func restartWorkstationClicked(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Перезапуск agy-workstation"
        alert.informativeText = "Вы уверены, что хотите перезапустить контейнер на сервере dio? Это сбросит все активные процессы."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Перезапустить")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn {
            runPythonScript("fetch_workstation.py", arguments: ["--restart"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.rebuildMenu()
            }
        }
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
