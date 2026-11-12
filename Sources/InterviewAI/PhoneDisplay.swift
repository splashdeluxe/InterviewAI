import Foundation
import Network
import InterviewAIKit

/// C-lite: the phone as a second screen for a live session.
///
/// A tiny web server on the local network. The Mac app keeps hearing
/// and thinking; a phone browser on the same Wi-Fi shows the live
/// answer, the tail of the transcript, and the action row, and its
/// taps run the same actions as the keyboard. Nothing leaves the
/// local network, and there is no account or pairing: while the
/// switch is on, anyone on the same network can open the page, so
/// it is off by default and the Settings text says so plainly.
@Observable
final class PhoneDisplay {
    static let port: UInt16 = 8734

    /// The address the phone opens, set while the server runs.
    var pageAddress: String?
    /// A plain-words problem, shown in Settings ("port is in use").
    var problem: String?

    @ObservationIgnored private weak var session: LiveSession?
    @ObservationIgnored private var listener: NWListener?

    func bind(session: LiveSession) {
        self.session = session
    }

    func apply(enabled: Bool) {
        enabled ? start() : stop()
    }

    func start() {
        guard listener == nil else { return }
        problem = nil
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { self?.pageAddress = Self.lanAddress() }
                case .failed(let error):
                    DispatchQueue.main.async {
                        self?.problem = "The phone page could not start. (\(error.localizedDescription))"
                        self?.listener = nil
                        self?.pageAddress = nil
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            // The main queue on purpose: the app target isolates its
            // types to the main actor, and this server is tiny (one
            // phone polling), so serving on main costs nothing and
            // keeps every callback in the actor's context.
            listener.start(queue: .main)
        } catch {
            problem = "The phone page could not start. (\(error.localizedDescription))"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        pageAddress = nil
    }

    // MARK: Connections

    private nonisolated func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, into: Data())
    }

    private nonisolated func receive(_ connection: NWConnection, into buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                respond(connection, to: request)
            } else if isComplete || error != nil || buffer.count > 65_536 {
                connection.cancel()
            } else {
                receive(connection, into: buffer)
            }
        }
    }

    /// A parsed request once the headers and the full body have arrived.
    private struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var body: String
    }

    private nonisolated static func parse(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerText = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var contentLength = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                contentLength = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyData = data[headerEnd.upperBound...]
        guard bodyData.count >= contentLength else { return nil }
        let body = String(decoding: bodyData.prefix(contentLength), as: UTF8.self)
        let target = String(parts[1])
        let split = target.split(separator: "?", maxSplits: 1)
        var query: [String: String] = [:]
        if split.count == 2 {
            for pair in split[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    query[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        }
        return Request(method: String(parts[0]), path: String(split[0]), query: query, body: body)
    }

    private nonisolated func respond(_ connection: NWConnection, to request: Request) {
        switch (request.method, request.path) {
        case ("GET", "/"):
            send(connection, status: "200 OK", type: "text/html; charset=utf-8", body: Self.page)
        case ("GET", "/state"):
            DispatchQueue.main.async { [weak self] in
                self?.send(connection, status: "200 OK", type: "application/json", body: self?.snapshot() ?? "{}")
            }
        case ("POST", "/action"):
            let number = Int(request.query["n"] ?? "") ?? 0
            DispatchQueue.main.async { [weak self] in
                if let action = AnswerAction.action(forNumber: number) {
                    self?.session?.runAction(action, typedQuestion: nil)
                }
                self?.send(connection, status: "200 OK", type: "application/json", body: "{}")
            }
        case ("POST", "/ask"):
            let question = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in
                if !question.isEmpty { self?.session?.ask(question) }
                self?.send(connection, status: "200 OK", type: "application/json", body: "{}")
            }
        case ("POST", "/toggle"):
            DispatchQueue.main.async { [weak self] in
                self?.session?.toggle()
                self?.send(connection, status: "200 OK", type: "application/json", body: "{}")
            }
        default:
            send(connection, status: "404 Not Found", type: "text/plain", body: "Not found")
        }
    }

    private nonisolated func send(_ connection: NWConnection, status: String, type: String, body: String) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: State

    /// The page's view of the session, read on the main thread.
    private func snapshot() -> String {
        guard let session else { return "{}" }
        let lines: [[String: Any]] = session.displaySegments.suffix(12).map { segment in
            let who = segment.channel == "them" ? "them" : "me"
            let name = segment.channel == "them" ? (segment.speakerLabel ?? "Them") : "Me"
            return ["who": who, "name": name, "text": segment.text, "final": segment.isFinal]
        }
        let state: [String: Any] = [
            "listening": session.isListening,
            "status": session.status,
            "answer": session.answer,
            "answering": session.isAnswering,
            "error": session.answerError ?? "",
            "lines": lines,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Address

    /// The Mac's Wi-Fi (or first LAN) IPv4 address, for the phone URL.
    private static func lanAddress() -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return "http://localhost:\(port)" }
        defer { freeifaddrs(interfaces) }
        var fallback: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if name == "en0" { return "http://\(ip):\(port)" }
            if fallback == nil { fallback = "http://\(ip):\(port)" }
        }
        return fallback ?? "http://localhost:\(port)"
    }

    // MARK: The page

    private nonisolated static let page = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="theme-color" content="#10151b">
    <title>InterviewAI</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
      body { margin: 0; background: #10151b; color: #e8ecf1; font: 17px/1.45 -apple-system, system-ui, sans-serif; padding: 14px 14px 40px; }
      header { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
      .dot { width: 10px; height: 10px; border-radius: 50%; background: #5a6672; flex: none; }
      .dot.live { background: #e2574c; }
      .dot.thinking { background: #8fc1ea; animation: pulse 1s ease-in-out infinite; }
      @keyframes pulse { 50% { opacity: .35; } }
      #status { color: #9aa6b2; font-size: 14px; }
      #answer { background: #171e26; border: 1px solid #232d38; border-radius: 12px; padding: 16px; font-size: 20px; white-space: pre-wrap; min-height: 120px; }
      #answer:empty::before { content: "The answer appears here."; color: #5a6672; }
      #error { color: #e28a8a; font-size: 14px; margin-top: 8px; white-space: pre-wrap; }
      .row { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 12px; }
      button { background: #1d2631; color: #e8ecf1; border: 1px solid #2b3644; border-radius: 10px; padding: 13px 10px; font-size: 16px; }
      button:active { background: #283444; }
      button.primary { background: #3e6b8a; border-color: #3e6b8a; grid-column: 1 / -1; }
      form { display: flex; gap: 8px; margin-top: 12px; }
      input { flex: 1; background: #171e26; border: 1px solid #232d38; border-radius: 10px; color: #e8ecf1; padding: 13px; font-size: 16px; }
      h2 { font-size: 13px; text-transform: uppercase; letter-spacing: .08em; color: #5a6672; margin: 22px 0 8px; }
      .line { margin: 0 0 8px; font-size: 15px; }
      .line .name { color: #8fc1ea; font-weight: 600; }
      .line.me .name { color: #9aa6b2; }
      .line.partial { opacity: .55; }
    </style>
    </head>
    <body>
    <header><span class="dot" id="dot"></span><span id="status">Connecting</span></header>
    <div id="answer"></div>
    <div id="error"></div>
    <div class="row" id="actions"></div>
    <form id="askform"><input id="ask" type="text" placeholder="Ask something" autocomplete="off"><button type="submit">Ask</button></form>
    <h2>Conversation</h2>
    <div id="lines"></div>
    <script>
      const titles = [\(AnswerAction.allCases.map { "\"\($0.title)\"" }.joined(separator: ","))];
      const actions = document.getElementById('actions');
      titles.forEach((title, i) => {
        const b = document.createElement('button');
        b.textContent = title;
        b.onclick = () => post('/action?n=' + (i + 1));
        actions.appendChild(b);
      });
      const toggle = document.createElement('button');
      toggle.className = 'primary';
      toggle.id = 'toggle';
      toggle.textContent = 'Start Listening';
      toggle.onclick = () => post('/toggle');
      actions.appendChild(toggle);
      async function post(path, body) {
        try { await fetch(path, { method: 'POST', body: body || '' }); } catch (e) {}
        setTimeout(tick, 120);
      }
      document.getElementById('askform').onsubmit = (e) => {
        e.preventDefault();
        const input = document.getElementById('ask');
        if (input.value.trim()) { post('/ask', input.value.trim()); input.value = ''; }
      };
      async function tick() {
        try {
          const r = await fetch('/state', { cache: 'no-store' });
          const s = await r.json();
          const dot = document.getElementById('dot');
          dot.className = 'dot' + (s.answering ? ' thinking' : (s.listening ? ' live' : ''));
          document.getElementById('status').textContent = s.status || '';
          document.getElementById('answer').textContent = s.answer || '';
          document.getElementById('error').textContent = s.error || '';
          document.getElementById('toggle').textContent = s.listening ? 'Stop Listening' : 'Start Listening';
          const box = document.getElementById('lines');
          box.textContent = '';
          (s.lines || []).forEach(line => {
            const p = document.createElement('p');
            p.className = 'line ' + line.who + (line.final ? '' : ' partial');
            const name = document.createElement('span');
            name.className = 'name';
            name.textContent = line.name + ': ';
            p.appendChild(name);
            p.appendChild(document.createTextNode(line.text));
            box.appendChild(p);
          });
        } catch (e) {
          document.getElementById('status').textContent = 'Not connected';
        }
      }
      tick();
      setInterval(tick, 800);
    </script>
    </body>
    </html>
    """
}
