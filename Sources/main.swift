import Cocoa

final class PowerButton: NSView {
    var on = false { didSet { needsDisplay = true } }
    var busy = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ r: NSRect) {
        let green = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.55, alpha: 1)
        (on ? green.withAlphaComponent(0.18) : NSColor(calibratedWhite: 1, alpha: 0.05)).setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let inner = bounds.insetBy(dx: 14, dy: 14)
        (on ? green : NSColor(calibratedWhite: 0.22, alpha: 1)).setFill()
        NSBezierPath(ovalIn: inner).fill()
        let c = NSPoint(x: bounds.midX, y: bounds.midY), rad: CGFloat = 26
        let ic = NSBezierPath()
        ic.appendArc(withCenter: c, radius: rad, startAngle: 125, endAngle: 55, clockwise: false)
        ic.move(to: NSPoint(x: c.x, y: c.y + 4)); ic.line(to: NSPoint(x: c.x, y: c.y + rad + 8))
        ic.lineWidth = 6; ic.lineCapStyle = .roundLineCapStyle
        NSColor.white.withAlphaComponent(busy ? 0.5 : 1).setStroke(); ic.stroke()
    }
    override func mouseDown(with e: NSEvent) { if !busy { onClick?() } }
}

func makeLabel(_ s: String, _ size: CGFloat, _ color: NSColor, _ f: NSRect, bold: Bool = false) -> NSTextField {
    let t = NSTextField(labelWithString: s)
    t.frame = f; t.alignment = .center; t.textColor = color
    t.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    return t
}

func powerGlyph(_ color: NSColor?) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18))
    img.lockFocus()
    (color ?? NSColor.black).setStroke()
    let p = NSBezierPath()
    p.appendArc(withCenter: NSPoint(x: 9, y: 8.5), radius: 5.5, startAngle: 125, endAngle: 55, clockwise: false)
    p.move(to: NSPoint(x: 9, y: 9.5)); p.line(to: NSPoint(x: 9, y: 15.5))
    p.lineWidth = 1.9; p.lineCapStyle = .roundLineCapStyle
    p.stroke()
    img.unlockFocus()
    img.isTemplate = (color == nil)
    return img
}

func serverHost(_ ob: [String: Any]) -> String? {
    let s = ob["settings"] as? [String: Any]
    if let v = (s?["vnext"] as? [[String: Any]])?.first { return v["address"] as? String }
    if let v = (s?["servers"] as? [[String: Any]])?.first { return v["address"] as? String }
    return nil
}

func ipv4s(_ h: String) -> [String] {
    if h.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789.").inverted) == nil { return [h] }
    return Host(name: h).addresses.filter { $0.split(separator: ".").count == 4 && !$0.contains(":") }
}

func pinned(_ ob: [String: Any], ip: String, host: String) -> [String: Any] {
    var o = ob
    var s = (o["settings"] as? [String: Any]) ?? [:]
    for key in ["vnext", "servers"] {
        if var arr = s[key] as? [[String: Any]], !arr.isEmpty { arr[0]["address"] = ip; s[key] = arr }
    }
    o["settings"] = s
    if var ss = o["streamSettings"] as? [String: Any] {
        if var t = ss["tlsSettings"] as? [String: Any], ((t["serverName"] as? String) ?? "").isEmpty {
            t["serverName"] = host; ss["tlsSettings"] = t
        }
        o["streamSettings"] = ss
    }
    return o
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let power = PowerButton(frame: NSRect(x: 90, y: 340, width: 180, height: 180))
    var status: NSTextField!
    let popup = NSPopUpButton(frame: NSRect(x: 40, y: 230, width: 280, height: 28), pullsDown: false)
    var tunBox: NSButton!
    var statusItem: NSStatusItem!
    var toggleItem: NSMenuItem!
    let xray = XrayManager()
    var servers: [Server] = []
    let stopPath = "/tmp/stizyy.stop"
    let green = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.55, alpha: 1)

    func applicationDidFinishLaunching(_ n: Notification) {
        if let d = UserDefaults.standard.data(forKey: "servers"),
           let s = try? JSONDecoder().decode([Server].self, from: d) { servers = s }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        window.appearance = NSAppearance(named: .vibrantDark)
        window.center()
        let v = window.contentView!
        v.addSubview(makeLabel("stizyy", 22, .white, NSRect(x: 0, y: 535, width: 360, height: 30), bold: true))
        v.addSubview(power)
        status = makeLabel("Disabled", 18, NSColor(calibratedWhite: 0.6, alpha: 1), NSRect(x: 0, y: 295, width: 360, height: 26))
        v.addSubview(status)
        popup.target = self; popup.action = #selector(pick)
        v.addSubview(popup)
        for (i, t) in ["From clipboard", "Subscription"].enumerated() {
            let b = NSButton(title: t, target: self, action: i == 0 ? #selector(addClipboard) : #selector(addSub))
            b.frame = NSRect(x: 40 + i * 145, y: 175, width: 135, height: 32)
            b.bezelStyle = .rounded
            v.addSubview(b)
        }
        tunBox = NSButton(checkboxWithTitle: "TUN-mode", target: self, action: #selector(tunChanged))
        tunBox.frame = NSRect(x: 40, y: 125, width: 280, height: 22)
        tunBox.state = UserDefaults.standard.bool(forKey: "tun") ? .on : .off
        v.addSubview(tunBox)
        v.addSubview(makeLabel("made with 💗 by ahoska", 11,
                               NSColor(calibratedWhite: 0.4, alpha: 1), NSRect(x: 0, y: 30, width: 360, height: 16)))
        power.onClick = { [weak self] in self?.toggle() }
        xray.onExit = { [weak self] in self?.disconnect("Error / disconnect") }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = powerGlyph(nil)
        let m = NSMenu()
        toggleItem = NSMenuItem(title: "Connect", action: #selector(toggleMenu), keyEquivalent: "")
        m.addItem(toggleItem)
        m.addItem(NSMenuItem(title: "Open stizyy", action: #selector(showWindow), keyEquivalent: ""))
        m.addItem(NSMenuItem.separator())
        m.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for i in m.items where i.action != #selector(NSApplication.terminate(_:)) { i.target = self }
        statusItem.menu = m

        reload()
        showWindow()
    }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleMenu() { toggle() }
    @objc func tunChanged() { UserDefaults.standard.set(tunBox.state == .on, forKey: "tun") }

    func reload() {
        popup.removeAllItems()
        popup.addItems(withTitles: servers.isEmpty ? ["No servers"] : servers.map { $0.name })
        let sel = min(UserDefaults.standard.integer(forKey: "sel"), max(servers.count - 1, 0))
        popup.selectItem(at: sel)
        if let d = try? JSONEncoder().encode(servers) { UserDefaults.standard.set(d, forKey: "servers") }
    }

    @objc func pick() { UserDefaults.standard.set(popup.indexOfSelectedItem, forKey: "sel") }

    func setState(_ on: Bool, _ text: String? = nil) {
        power.on = on; power.busy = false
        status.stringValue = text ?? (on ? "Connected" : "Disconnected")
        status.textColor = on ? green : NSColor(calibratedWhite: 0.6, alpha: 1)
        toggleItem.title = on ? "Disconnect" : "Connect"
        statusItem.button?.image = on ? powerGlyph(green) : powerGlyph(nil)
    }

    func disconnect(_ text: String? = nil) {
        FileManager.default.createFile(atPath: stopPath, contents: Data())
        xray.stop()
        DispatchQueue.global().async { SystemProxy.set(on: false) }
        setState(false, text)
    }

    func toggle() {
        if xray.isRunning || power.on { disconnect(); return }
        let i = popup.indexOfSelectedItem
        guard i >= 0, i < servers.count, let p = Core.parse(servers[i].link) else { alert("Add a server"); return }
        power.busy = true; status.stringValue = "Connecting…"
        let tun = tunBox.state == .on
        DispatchQueue.global().async {
            var ob = p.outbound
            var err: String? = nil
            if tun {
                if let h = serverHost(ob) {
                    let ips = ipv4s(h)
                    if let first = ips.first {
                        if first != h { ob = pinned(ob, ip: first, host: h) }
                        err = self.startTun(ob, ips.joined(separator: ","))
                    } else { err = "IP don't resolve" }
                } else { err = "Can't read server adress" }
            } else {
                do { try self.xray.start(outbound: ob); SystemProxy.set(on: true) }
                catch { err = "Cannot load xray core: \(error.localizedDescription)" }
            }
            DispatchQueue.main.async {
                if let e = err { self.xray.stop(); self.setState(false); self.alert(e) }
                else if self.xray.isRunning { self.setState(true) }
                else { self.setState(false, "Error / disconnect") }
            }
        }
    }

    func startTun(_ ob: [String: Any], _ ips: String) -> String? {
        let res = Bundle.main.resourcePath ?? "."
        if !FileManager.default.fileExists(atPath: res + "/tun2socks") { return "Dont have a file tun2socks in xray folder" }
        try? FileManager.default.removeItem(atPath: stopPath)
        do { try xray.start(outbound: ob) } catch { return "Cannot start xray: \(error.localizedDescription)" }
        let pid = ProcessInfo.processInfo.processIdentifier
        let cmd = "'\(res)/tun.sh' '\(ips)' \(pid) \(stopPath) '\(res)' >/tmp/stizyy-tun.log 2>&1 &"
        var e: NSDictionary?
        _ = NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")?.executeAndReturnError(&e)
        if let e = e { return "TUN отменён: \((e["NSAppleScriptErrorMessage"] as? String) ?? "нет прав")" }
        Thread.sleep(forTimeInterval: 3)
        let c = Process(); c.launchPath = "/sbin/ifconfig"; c.arguments = ["utun123"]
        c.standardOutput = FileHandle.nullDevice; c.standardError = FileHandle.nullDevice
        try? c.run(); c.waitUntilExit()
        if c.terminationStatus != 0 { return "tun2socks don't start (log: /tmp/stizyy-tun.log)" }
        return nil
    }

    @objc func addClipboard() {
        let t = NSPasteboard.general.string(forType: .string) ?? ""
        let new = Core.servers(from: t)
        if new.isEmpty { alert("You dont have vless:// vmess:// trojan:// links in clipboard") } else { servers += new; reload() }
    }

    @objc func addSub() {
        let a = NSAlert(); a.messageText = "Subscription URL"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); a.accessoryView = f
        a.addButton(withTitle: "Add"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn, let u = URL(string: f.stringValue) else { return }
        Core.fetchSubscription(u) { [weak self] s in
            if s.isEmpty { self?.alert("Can't get servers") } else { self?.servers += s; self?.reload() }
        }
    }

    func alert(_ s: String) { let a = NSAlert(); a.messageText = s; a.runModal() }
    func applicationWillTerminate(_ n: Notification) {
        FileManager.default.createFile(atPath: stopPath, contents: Data())
        xray.stop(); SystemProxy.set(on: false)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { return false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { showWindow(); return true }
}

let app = NSApplication.shared
let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item)
let sub = NSMenu()
sub.addItem(NSMenuItem(title: "Quit stizyy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
item.submenu = sub; app.mainMenu = menu
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
