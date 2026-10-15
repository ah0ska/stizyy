import Foundation

struct Server: Codable { var name: String; var link: String }

enum Core {
    static func b64(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    static func stream(_ q: [String: String]) -> [String: Any] {
        let net = q["type"] ?? "tcp"
        let sec = q["security"] ?? "none"
        var s: [String: Any] = ["network": net, "security": sec]
        if sec == "tls" {
            var t: [String: Any] = ["serverName": q["sni"] ?? q["host"] ?? "", "fingerprint": q["fp"] ?? "chrome"]
            if let a = q["alpn"] { t["alpn"] = a.components(separatedBy: ",") }
            s["tlsSettings"] = t
        }
        if sec == "reality" {
            s["realitySettings"] = ["serverName": q["sni"] ?? "", "fingerprint": q["fp"] ?? "chrome",
                                    "publicKey": q["pbk"] ?? "", "shortId": q["sid"] ?? "", "spiderX": q["spx"] ?? ""]
        }
        switch net {
        case "ws": s["wsSettings"] = ["path": q["path"] ?? "/", "headers": ["Host": q["host"] ?? ""]]
        case "grpc": s["grpcSettings"] = ["serviceName": q["serviceName"] ?? ""]
        default: break
        }
        return s
    }

    static func parse(_ link: String) -> (name: String, outbound: [String: Any])? {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.hasPrefix("vmess://") { return vmess(String(l.dropFirst(8))) }
        guard let u = URLComponents(string: l), let host = u.host, let port = u.port, let user = u.user else { return nil }
        var q: [String: String] = [:]
        u.queryItems?.forEach { q[$0.name] = $0.value ?? "" }
        let name = u.fragment ?? host
        switch u.scheme ?? "" {
        case "vless":
            var usr: [String: Any] = ["id": user, "encryption": q["encryption"] ?? "none"]
            if let f = q["flow"], !f.isEmpty { usr["flow"] = f }
            return (name, ["protocol": "vless",
                           "settings": ["vnext": [["address": host, "port": port, "users": [usr]]]],
                           "streamSettings": stream(q)])
        case "trojan":
            var qq = q; if qq["security"] == nil { qq["security"] = "tls" }
            return (name, ["protocol": "trojan",
                           "settings": ["servers": [["address": host, "port": port, "password": user]]],
                           "streamSettings": stream(qq)])
        default: return nil
        }
    }

    static func vmess(_ b: String) -> (String, [String: Any])? {
        guard let d = b64(b), let obj = try? JSONSerialization.jsonObject(with: d),
              let j = obj as? [String: Any],
              let host = j["add"] as? String, let id = j["id"] as? String else { return nil }
        let port = Int("\(j["port"] ?? 443)") ?? 443
        var q: [String: String] = ["type": (j["net"] as? String) ?? "tcp",
                                   "security": ((j["tls"] as? String) == "tls") ? "tls" : "none",
                                   "host": (j["host"] as? String) ?? "", "path": (j["path"] as? String) ?? "/",
                                   "sni": (j["sni"] as? String) ?? ""]
        if let sn = j["path"] as? String, q["type"] == "grpc" { q["serviceName"] = sn }
        let user: [String: Any] = ["id": id, "alterId": Int("\(j["aid"] ?? 0)") ?? 0,
                                   "security": (j["scy"] as? String) ?? "auto"]
        return ((j["ps"] as? String) ?? host,
                ["protocol": "vmess", "settings": ["vnext": [["address": host, "port": port, "users": [user]]]],
                 "streamSettings": stream(q)])
    }

    static func servers(from text: String) -> [Server] {
        return text.components(separatedBy: .newlines).flatMap { (line: String) -> [Server] in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard let p = parse(l) else { return [] }
            return [Server(name: p.name, link: l)]
        }
    }

    static func fetchSubscription(_ url: URL, done: @escaping ([Server]) -> Void) {
        URLSession.shared.dataTask(with: url) { d, _, _ in
            var out: [Server] = []
            if let d = d, let t = String(data: d, encoding: .utf8) {
                let tr = t.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = b64(tr).flatMap { String(data: $0, encoding: .utf8) } ?? tr
                out = servers(from: body)
            }
            DispatchQueue.main.async { done(out) }
        }.resume()
    }

    static func config(_ outbound: [String: Any]) -> Data {
        var ob = outbound; ob["tag"] = "proxy"
        let cfg: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [
                ["tag": "socks", "listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": ["udp": true]],
                ["tag": "http", "listen": "127.0.0.1", "port": 10809, "protocol": "http"]],
            "outbounds": [ob, ["tag": "direct", "protocol": "freedom"]]]
        return (try? JSONSerialization.data(withJSONObject: cfg, options: .prettyPrinted)) ?? Data()
    }
}

final class XrayManager {
    private var proc: Process?
    var onExit: (() -> Void)?
    var isRunning: Bool { if let p = proc { return p.isRunning }; return false }

    func start(outbound: [String: Any]) throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("stizyy")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = dir.appendingPathComponent("config.json")
        try Core.config(outbound).write(to: cfg)
        let res = Bundle.main.resourcePath ?? "."
        let p = Process()
        p.launchPath = res + "/xray"
        p.arguments = ["run", "-c", cfg.path]
        p.environment = ["XRAY_LOCATION_ASSET": res]
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.proc = nil; self?.onExit?() } }
        try p.run()
        proc = p
    }

    func stop() { proc?.terminationHandler = nil; proc?.terminate(); proc = nil }
}

enum SystemProxy {
    @discardableResult
    static func run(_ args: [String]) -> String {
        let p = Process(); p.launchPath = "/usr/sbin/networksetup"; p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try? p.run()
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    static func set(on: Bool) {
        let svcs = run(["-listallnetworkservices"]).components(separatedBy: "\n").dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        for s in svcs {
            if on {
                run(["-setsocksfirewallproxy", s, "127.0.0.1", "10808"])
                run(["-setwebproxy", s, "127.0.0.1", "10809"])
                run(["-setsecurewebproxy", s, "127.0.0.1", "10809"])
            }
            let st = on ? "on" : "off"
            run(["-setsocksfirewallproxystate", s, st])
            run(["-setwebproxystate", s, st])
            run(["-setsecurewebproxystate", s, st])
        }
    }
}
