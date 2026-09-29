import Foundation

struct BracketMatch: Decodable, Hashable, Identifiable {
  let matchId: String?
  let round: Int
  let index: Int?
  let playerAId: String?
  let playerBId: String?
  let playerAUserId: String?
  let playerBUserId: String?
  let playerAPartnerUserId: String?
  let playerBPartnerUserId: String?
  let playerAName: String?
  let playerBName: String?
  let playerAMembers: String?
  let playerBMembers: String?
  let playerAPictureUrl: String?
  let playerBPictureUrl: String?
  let playerAPartnerPictureUrl: String?
  let playerBPartnerPictureUrl: String?
  let playerAHasPartner: Bool
  let playerBHasPartner: Bool
  let singles: Bool
  let winnerId: String?
  let scoreA: Int?
  let scoreB: Int?
  let isFinal: Bool?
  let courtNumber: Int?
  let refereeUserId: String?
  let refereeName: String?
  let startedAt: String?
  let endedAt: String?

  var id: String { matchId ?? "r\(round)-i\(index ?? 0)" }

  static func slot(round: Int, index: Int, singles: Bool) -> BracketMatch {
    BracketMatch(
      matchId: nil,
      round: round,
      index: index,
      playerAId: nil,
      playerBId: nil,
      playerAUserId: nil,
      playerBUserId: nil,
      playerAPartnerUserId: nil,
      playerBPartnerUserId: nil,
      playerAName: nil,
      playerBName: nil,
      playerAMembers: nil,
      playerBMembers: nil,
      playerAPictureUrl: nil,
      playerBPictureUrl: nil,
      playerAPartnerPictureUrl: nil,
      playerBPartnerPictureUrl: nil,
      playerAHasPartner: false,
      playerBHasPartner: false,
      singles: singles,
      winnerId: nil,
      scoreA: nil,
      scoreB: nil,
      isFinal: nil,
      courtNumber: nil,
      refereeUserId: nil,
      refereeName: nil,
      startedAt: nil,
      endedAt: nil
    )
  }
}

struct BracketFlowNode: Decodable, Hashable {
  let match: BracketMatch?

  enum CodingKeys: String, CodingKey {
    case type
    case data
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    if type == "match" {
      match = try container.decode(BracketMatch.self, forKey: .data)
    } else {
      match = nil
    }
  }
}

struct BracketFlow: Decodable, Hashable {
  let nodes: [BracketFlowNode]
}

struct TournamentItem: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let status: String
  let bracketSize: Int
  let bannerUrl: String?
  let startsAt: String?
  let endsAt: String?
  let courtName: String?
  let courtIds: [String]?
  let venueName: String?
  let venueLatitude: Double?
  let venueLongitude: Double?
  let courtCount: Int?
  let createdById: String?
  let createdByName: String?
  let createdByPictureUrl: String?
  let division: String?
  let registrationFee: Int?
  let registrationFeeCurrency: String?
  let prizes: [TournamentPrize]?
  let firstPlacePhotoUrl: String?
  let secondPlacePhotoUrl: String?
  let thirdPlacePhotoUrl: String?
  let flow: BracketFlow?
  let playFormat: String?
  let spectatorCount: Int?
  let spectating: Bool?
}

extension TournamentItem {
  var formatTag: String? {
    switch division {
    case "mixed_doubles":
      return "[MIXED DOUBLES]"
    case "mens_doubles", "womens_doubles":
      return "[DOUBLES]"
    case "mens_singles", "womens_singles":
      return "[SINGLES]"
    default:
      if playFormat == "singles" { return "[SINGLES]" }
      if playFormat == "doubles" { return "[DOUBLES]" }
      return nil
    }
  }

  var titledName: String {
    guard let formatTag else { return name }
    return "\(name) \(formatTag)"
  }
}

struct TournamentPrize: Codable, Hashable {
  let place: String
  let prize: String
}

enum PrizeTotal {
  static func php(_ prizes: [TournamentPrize]?) -> String? {
    guard let prizes else { return nil }
    var sum = 0
    var counted = 0
    for prize in prizes {
      let digits = prize.prize.filter(\.isNumber)
      guard let value = Int(digits) else { continue }
      sum += value
      counted += 1
    }
    guard counted > 0 else { return nil }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    guard let text = formatter.string(from: NSNumber(value: sum)) else { return nil }
    return "₱\(text)"
  }
}

struct ScheduleDay: Decodable {
  let date: String
  let slots: [String]
  let courts: [ScheduleCourt]
}

struct ScheduleCourt: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let number: Int
}

private struct TournamentListBody: Decodable {
  let tournaments: [TournamentItem]
}

private struct TournamentDetailBody: Decodable {
  let tournament: TournamentItem
}

private struct AvailabilityBody: Decodable {
  let day: ScheduleDay
}

private struct DeleteBody: Decodable {
  let ok: Bool
}

enum DrawAccess {
  static func roles(_ user: User) -> [String] {
    if let roles = user.roles, !roles.isEmpty {
      return roles
    }
    return [user.role]
  }

  static func canManage(_ user: User) -> Bool {
    roles(user).contains { ["super_admin", "admin", "dev", "qa", "staff"].contains($0) }
  }

  static func canCreate(_ user: User) -> Bool {
    roles(user).contains { ["super_admin", "admin", "dev", "qa"].contains($0) }
  }

  static func canDelete(_ user: User) -> Bool {
    canCreate(user)
  }
}

enum VenueClock {
  static let zone = TimeZone(secondsFromGMT: 8 * 60 * 60)!

  static func dateKey(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  static func date(fromDateKey key: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: key)
  }

  static func parse(_ iso: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    if let date = formatter.date(from: iso) {
      return date
    }
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return formatter.date(from: iso)
  }

  static func stamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = zone
    return formatter.string(from: date)
  }

  static func parts(_ iso: String) -> (dateKey: String, slot: String)? {
    guard let date = parse(iso) else { return nil }
    let day = DateFormatter()
    day.calendar = Calendar(identifier: .gregorian)
    day.timeZone = zone
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "yyyy-MM-dd"
    let slot = DateFormatter()
    slot.calendar = Calendar(identifier: .gregorian)
    slot.timeZone = zone
    slot.locale = Locale(identifier: "en_US_POSIX")
    slot.dateFormat = "HH:mm"
    return (day.string(from: date), slot.string(from: date))
  }

  static func phase(_ item: TournamentItem, now: Date = Date()) -> String {
    if item.status == "draft" {
      return "Draft"
    }
    if item.status == "completed" {
      return "Completed"
    }
    guard let startsAt = item.startsAt, let start = parse(startsAt) else {
      return item.status == "draft" ? "Draft" : item.status.capitalized
    }
    if start > now {
      return "Upcoming"
    }
    if let endsAt = item.endsAt, let end = parse(endsAt), end <= now {
      return "Completed"
    }
    return "Ongoing"
  }

  static func phaseTitle(_ item: TournamentItem, now: Date = Date()) -> String {
    let value = phase(item, now: now)
    return value == "Ongoing" ? "Live now" : value
  }

  static func label(_ iso: String) -> String {
    guard let date = parse(iso) else { return iso }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: date)
  }

  static func span(start: String, end: String) -> String? {
    guard let startDate = parse(start), let endDate = parse(end) else { return nil }
    let day = DateFormatter()
    day.calendar = Calendar(identifier: .gregorian)
    day.timeZone = zone
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "MMM d"
    let clock = DateFormatter()
    clock.calendar = Calendar(identifier: .gregorian)
    clock.timeZone = zone
    clock.locale = Locale(identifier: "en_US_POSIX")
    clock.dateFormat = "h:mm a"
    if day.string(from: startDate) == day.string(from: endDate) {
      return "\(day.string(from: startDate)), \(clock.string(from: startDate)) – \(clock.string(from: endDate))"
    }
    return "\(label(start)) – \(label(end))"
  }

  static func hoursRequired(players: Int, courts: Int) -> Int? {
    guard players >= 2, courts >= 1, players & (players - 1) == 0 else { return nil }
    var matches = players / 2
    var hours = 0
    while matches >= 1 {
      hours += (matches + courts - 1) / courts
      matches /= 2
    }
    return hours
  }

  static func scheduleLimit(players: Int, courts: Int, window: Int) -> String? {
    guard let need = hoursRequired(players: players, courts: courts), window < need else {
      return nil
    }
    let courtWord = courts == 1 ? "court" : "courts"
    return "\(players) players, \(courts) \(courtWord): need \(need) hours"
  }

  static func hoursBetween(start: String, until: String) -> Int? {
    guard let startHour = hour(start) else { return nil }
    var cursor = startHour
    var count = 0
    repeat {
      count += 1
      cursor = (cursor + 1) % 24
      if count > 24 { return nil }
    } while padded(cursor) != until
    return count
  }

  static func endISO(dateKey: String, start: String, until: String) -> String? {
    guard let hours = hoursBetween(start: start, until: until), hours >= 1 else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let startDate = formatter.date(from: "\(dateKey)T\(start):00+08:00") else { return nil }
    return stamp(startDate.addingTimeInterval(Double(hours) * 3600))
  }

  private static func hour(_ slot: String) -> Int? {
    let parts = slot.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), (0..<24).contains(hour) else { return nil }
    return hour
  }

  private static func padded(_ hour: Int) -> String {
    String(format: "%02d:00", hour)
  }
}

struct TournamentService {
  private let client = APIClient.shared

  func list(managing: Bool) async throws -> [TournamentItem] {
    let path = managing ? "/api/admin/tournaments" : "/api/tournaments?includeChallenger=1"
    let body: TournamentListBody = try await client.get(path: path)
    return body.tournaments
  }

  func mine() async throws -> (joined: [TournamentItem], created: [TournamentItem], spectated: [TournamentItem], refereed: [TournamentItem]) {
    struct Body: Decodable {
      let tournaments: [TournamentItem]
      let created: [TournamentItem]
      let spectated: [TournamentItem]
      let refereed: [TournamentItem]
    }
    let body: Body = try await client.get(path: "/api/tournaments/mine")
    return (body.tournaments, body.created, body.spectated, body.refereed)
  }

  func setSpectating(id: String, on: Bool) async throws -> (spectating: Bool, spectatorCount: Int) {
    struct Empty: Encodable {}
    struct Response: Decodable {
      let spectating: Bool
      let spectatorCount: Int
    }
    let body: Response
    if on {
      body = try await client.post(path: "/api/tournaments/\(id)/spectate", body: Empty())
    } else {
      body = try await client.delete(path: "/api/tournaments/\(id)/spectate")
    }
    return (body.spectating, body.spectatorCount)
  }

  func joinRequests(id: String) async throws -> (requested: Bool, requests: [JoinRequest]) {
    let body: JoinRequestBody = try await client.get(path: "/api/tournaments/\(id)/requests")
    return (body.requested, body.requests)
  }

  func requestToJoin(id: String) async throws -> (requested: Bool, requests: [JoinRequest]) {
    struct Body: Encodable {}
    let body: JoinRequestBody = try await client.post(
      path: "/api/tournaments/\(id)/requests",
      body: Body()
    )
    return (body.requested, body.requests)
  }

  func clearJoinRequest(id: String, userId: String) async throws -> [JoinRequest] {
    var parts = URLComponents()
    parts.path = "/api/tournaments/\(id)/requests"
    parts.queryItems = [URLQueryItem(name: "userId", value: userId)]
    guard let path = parts.string else { throw APIError.invalidURL }
    let body: JoinRequestBody = try await client.delete(path: path)
    return body.requests
  }

  func detail(id: String, managing: Bool) async throws -> TournamentItem {
    let path = managing ? "/api/admin/tournaments/\(id)" : "/api/tournaments/\(id)?includeChallenger=1"
    let body: TournamentDetailBody = try await client.get(path: path)
    return body.tournament
  }

  func availability(dateKey: String, excludeId: String?) async throws -> ScheduleDay {
    var parts = URLComponents()
    parts.path = "/api/admin/tournaments/availability"
    var query = [URLQueryItem(name: "date", value: dateKey)]
    if let excludeId, !excludeId.isEmpty {
      query.append(URLQueryItem(name: "excludeId", value: excludeId))
    }
    parts.queryItems = query
    guard let path = parts.string else {
      throw APIError.invalidURL
    }
    let body: AvailabilityBody = try await client.get(path: path)
    return body.day
  }

  func create(
    name: String,
    size: Int,
    startsAt: String,
    endsAt: String,
    courtIds: [String],
    fee: Int?,
    prizes: [TournamentPrize],
    venueName: String,
    latitude: Double,
    longitude: Double,
    courtCount: Int,
    playFormat: String,
    division: String,
    banner: (data: Data, mime: String, name: String)?
  ) async throws -> TournamentItem {
      guard let encoded = String(data: try JSONEncoder().encode(prizes), encoding: .utf8) else {
        throw APIError.invalidResponse
      }
      var fields = [
      "name": name,
      "size": String(size),
      "startsAt": startsAt,
      "endsAt": endsAt,
      "courtIds": "[]",
      "prizes": encoded,
      "registrationFeeCurrency": "php",
      "venueName": venueName,
      "venueLatitude": String(latitude),
      "venueLongitude": String(longitude),
      "courtCount": String(courtCount),
      "playFormat": playFormat,
      "division": division,
      "source": "challenger",
    ]
    if let fee {
      fields["registrationFee"] = String(fee)
    }
    let body: TournamentDetailBody = try await client.uploadMultipart(
      path: "/api/admin/tournaments",
      method: "POST",
      fields: fields,
      fileField: banner == nil ? nil : "banner",
      fileName: banner?.name ?? "banner.jpg",
      mimeType: banner?.mime ?? "image/jpeg",
      fileData: banner?.data
    )
    return body.tournament
  }

  func update(
    id: String,
    name: String,
    startsAt: String,
    endsAt: String,
    courtIds: [String],
    fee: Int?,
    prizes: [TournamentPrize],
    venueName: String,
    latitude: Double,
    longitude: Double,
    courtCount: Int,
    playFormat: String,
    division: String,
    banner: (data: Data, mime: String, name: String)?
  ) async throws -> TournamentItem {
      guard let encoded = String(data: try JSONEncoder().encode(prizes), encoding: .utf8) else {
        throw APIError.invalidResponse
      }
      var fields = [
      "action": "update_details",
      "name": name,
      "startsAt": startsAt,
      "endsAt": endsAt,
      "courtIds": "[]",
      "prizes": encoded,
      "registrationFeeCurrency": "php",
      "venueName": venueName,
      "venueLatitude": String(latitude),
      "venueLongitude": String(longitude),
      "courtCount": String(courtCount),
      "playFormat": playFormat,
      "division": division,
    ]
    if let fee {
      fields["registrationFee"] = String(fee)
    }
    let body: TournamentDetailBody = try await client.uploadMultipart(
      path: "/api/admin/tournaments/\(id)",
      method: "PATCH",
      fields: fields,
      fileField: banner == nil ? nil : "banner",
      fileName: banner?.name ?? "banner.jpg",
      mimeType: banner?.mime ?? "image/jpeg",
      fileData: banner?.data
    )
    return body.tournament
  }

  func delete(id: String) async throws {
    let body: DeleteBody = try await client.delete(path: "/api/admin/tournaments/\(id)")
    if !body.ok {
      throw APIError.invalidResponse
    }
  }

  func setWinnerPhoto(id: String, place: String, data: Data) async throws -> TournamentItem {
    let body: TournamentDetailBody = try await client.uploadMultipart(
      path: "/api/admin/tournaments/\(id)",
      method: "PATCH",
      fields: ["action": "update_winner_photos"],
      fileField: "winnerPhoto\(place)",
      fileName: "winner-\(place).jpg",
      mimeType: "image/jpeg",
      fileData: data
    )
    return body.tournament
  }

  func post(id: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let action: String
    }
    let body: TournamentDetailBody = try await client.patch(
      path: "/api/admin/tournaments/\(id)",
      body: Body(action: "open_registration")
    )
    return body.tournament
  }

  func accounts(query: String) async throws -> [AccountHit] {
    var parts = URLComponents()
    parts.path = "/api/admin/tournaments/accounts"
    parts.queryItems = [URLQueryItem(name: "q", value: query)]
    guard let path = parts.string else {
      throw APIError.invalidURL
    }
    let body: AccountListBody = try await client.get(path: path)
    return body.accounts
  }

  func assignPlayer(tournamentId: String, matchId: String, slot: String, name: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let slot: String
      let name: String
    }
    let body: TournamentDetailBody = try await client.post(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)/slot",
      body: Body(slot: slot, name: name)
    )
    return body.tournament
  }

  func setCourt(tournamentId: String, matchId: String, courtNumber: Int?) async throws -> TournamentItem {
    struct Body: Encodable {
      let courtNumber: Int?
      func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let courtNumber {
          try container.encode(courtNumber, forKey: .courtNumber)
        } else {
          try container.encodeNil(forKey: .courtNumber)
        }
      }
      enum CodingKeys: String, CodingKey { case courtNumber }
    }
    let body: TournamentDetailBody = try await client.patch(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)",
      body: Body(courtNumber: courtNumber)
    )
    return body.tournament
  }

  func startMatch(tournamentId: String, matchId: String) async throws -> TournamentItem {
    struct Body: Encodable {}
    let body: TournamentDetailBody = try await client.post(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)/start",
      body: Body()
    )
    return body.tournament
  }

  func clearResult(tournamentId: String, matchId: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let clear: Bool
    }
    let body: TournamentDetailBody = try await client.post(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)",
      body: Body(clear: true)
    )
    return body.tournament
  }

  func recordResult(
    tournamentId: String,
    matchId: String,
    winnerSlot: String,
    scoreA: Int,
    scoreB: Int
  ) async throws -> TournamentItem {
    struct Body: Encodable {
      let winnerSlot: String
      let scoreA: Int
      let scoreB: Int
    }
    let body: TournamentDetailBody = try await client.post(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)/result",
      body: Body(winnerSlot: winnerSlot, scoreA: scoreA, scoreB: scoreB)
    )
    return body.tournament
  }

  func setReferee(tournamentId: String, matchId: String, name: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let refereeName: String
    }
    let body: TournamentDetailBody = try await client.patch(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)",
      body: Body(refereeName: name)
    )
    return body.tournament
  }

  func setReferee(tournamentId: String, matchId: String, userId: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let refereeUserId: String
    }
    let body: TournamentDetailBody = try await client.patch(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)",
      body: Body(refereeUserId: userId)
    )
    return body.tournament
  }

  func clearReferee(tournamentId: String, matchId: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let refereeUserId: String?
      func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .refereeUserId)
      }
      enum CodingKeys: String, CodingKey { case refereeUserId }
    }
    let body: TournamentDetailBody = try await client.patch(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)",
      body: Body(refereeUserId: nil)
    )
    return body.tournament
  }

  func clearPlayer(tournamentId: String, matchId: String, slot: String) async throws -> TournamentItem {
    struct Body: Encodable {
      let slot: String
      let clear: Bool
    }
    let body: TournamentDetailBody = try await client.post(
      path: "/api/admin/tournaments/\(tournamentId)/matches/\(matchId)/slot",
      body: Body(slot: slot, clear: true)
    )
    return body.tournament
  }

  func notices() async throws -> [JoinNotice] {
    struct Body: Decodable {
      let notifications: [JoinNotice]
    }
    let body: Body = try await client.get(path: "/api/tournaments/notifications")
    return body.notifications
  }

  func readNotices(all: Bool, id: String?) async throws {
    struct Body: Encodable {
      let all: Bool?
      let id: String?
    }
    struct Response: Decodable {
      let updated: Int
    }
    let _: Response = try await client.patch(
      path: "/api/tournaments/notifications",
      body: Body(all: all ? true : nil, id: id)
    )
  }
}

struct JoinRequest: Decodable, Identifiable, Hashable {
  let id: String
  let userId: String
  let name: String
  let email: String
  let pictureUrl: String?
}

private struct JoinRequestBody: Decodable {
  let requested: Bool
  let requests: [JoinRequest]
}

struct AccountHit: Decodable, Identifiable, Hashable {
  let id: String
  let name: String
  let email: String
  let pictureUrl: String?
}

private struct AccountListBody: Decodable {
  let accounts: [AccountHit]
}
