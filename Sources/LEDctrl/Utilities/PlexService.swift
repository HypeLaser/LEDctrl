import Foundation

struct PlexNowPlaying: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let type: String // movie, episode, track
    let grandparentTitle: String? // show name for episodes
    let parentTitle: String? // season for episodes
    let user: String
    let state: String // playing, paused, buffering
    let progressPercent: Int
    let durationMs: Int
    let viewOffsetMs: Int

    var displayTitle: String {
        switch type {
        case "episode":
            if let show = grandparentTitle {
                return "\(show) - \(title)"
            }
            return title
        case "track":
            if let artist = grandparentTitle {
                return "\(artist) - \(title)"
            }
            return title
        default:
            return title
        }
    }

    var timeRemainingFormatted: String {
        let remainingMs = max(0, durationMs - viewOffsetMs)
        let totalMinutes = remainingMs / 1000 / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var endTimeFormatted: String {
        let remainingMs = max(0, durationMs - viewOffsetMs)
        let endDate = Date().addingTimeInterval(Double(remainingMs) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: endDate)
    }
}

actor PlexService {
    private let urlSession: URLSession
    private var serverURL: String = ""
    private var token: String = ""

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        self.urlSession = URLSession(configuration: config)
    }

    func configure(serverURL: String, token: String) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchNowPlaying() async -> Result<[PlexNowPlaying], PlexError> {
        guard !serverURL.isEmpty else {
            return .failure(.notConfigured)
        }

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        let urlString = "\(base)/status/sessions?X-Plex-Token=\(token)"

        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.network("Non-HTTP response"))
            }
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    return .failure(.unauthorized)
                }
                return .failure(.network("HTTP \(httpResponse.statusCode)"))
            }
            let items = try parseSessionsXML(data)
            return .success(items)
        } catch let error as URLError {
            return .failure(.network(error.localizedDescription))
        } catch {
            return .failure(.parse(error.localizedDescription))
        }
    }

    private func parseSessionsXML(_ data: Data) throws -> [PlexNowPlaying] {
        let parser = PlexSessionsParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        // Filter out stopped/completed sessions, sort by active state priority
        let active = parser.items.filter { item in
            let activeStates = ["playing", "paused", "buffering"]
            return activeStates.contains(item.state.lowercased()) && item.progressPercent < 99
        }
        return active.sorted { a, b in
            let priority = ["playing": 0, "paused": 1, "buffering": 2]
            return (priority[a.state.lowercased()] ?? 3) < (priority[b.state.lowercased()] ?? 3)
        }
    }
}

enum PlexError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case unauthorized
    case network(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Plex server not configured"
        case .invalidURL: return "Invalid server URL"
        case .unauthorized: return "Invalid or missing Plex token"
        case .network(let msg): return "Network error: \(msg)"
        case .parse(let msg): return "Parse error: \(msg)"
        }
    }
}

private final class PlexSessionsParser: NSObject, XMLParserDelegate {
    var items: [PlexNowPlaying] = []
    private var currentVideo: [String: String] = [:]
    private var currentUser: String = ""
    private var inVideo = false
    private var inUser = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "Video", "Track":
            inVideo = true
            currentVideo = [:]
            currentVideo["type"] = attributeDict["type"] ?? ""
            currentVideo["title"] = attributeDict["title"] ?? ""
            currentVideo["grandparentTitle"] = attributeDict["grandparentTitle"]
            currentVideo["parentTitle"] = attributeDict["parentTitle"]
            currentVideo["viewOffset"] = attributeDict["viewOffset"]
            currentVideo["duration"] = attributeDict["duration"]
            currentUser = ""
        case "User":
            inUser = true
            currentUser = attributeDict["title"] ?? ""
        case "Player":
            if let state = attributeDict["state"] {
                currentVideo["state"] = state
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Video", "Track":
            inVideo = false
            let title = currentVideo["title"] ?? "Unknown"
            let type = currentVideo["type"] ?? ""
            let duration = Int(currentVideo["duration"] ?? "0") ?? 0
            let viewOffset = Int(currentVideo["viewOffset"] ?? "0") ?? 0
            let percent = duration > 0 ? Int((Double(viewOffset) / Double(duration)) * 100) : 0

            let item = PlexNowPlaying(
                title: title,
                type: type,
                grandparentTitle: currentVideo["grandparentTitle"],
                parentTitle: currentVideo["parentTitle"],
                user: currentUser.isEmpty ? "Local" : currentUser,
                state: currentVideo["state"] ?? "playing",
                progressPercent: percent,
                durationMs: duration,
                viewOffsetMs: viewOffset
            )
            items.append(item)
        case "User":
            inUser = false
        default:
            break
        }
    }
}
