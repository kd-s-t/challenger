import Foundation

struct Standing: Identifiable, Hashable {
  let id: String
  let place: Int
  let name: String
  let wins: Int
  let losses: Int
  let pointDifferential: Int

  var record: String {
    "\(wins)–\(losses)"
  }

  var differentialLabel: String {
    if pointDifferential > 0 {
      return "+\(pointDifferential)"
    }
    if pointDifferential < 0 {
      return "−\(abs(pointDifferential))"
    }
    return "0"
  }
}

enum ScoreDifferential {
  static func standings(matches: [BracketMatch]) -> [Standing] {
    var states: [String: TeamState] = [:]
    for match in matches {
      guard let aId = match.playerAId, let bId = match.playerBId,
            let scoreA = match.scoreA, let scoreB = match.scoreB,
            scoreA != scoreB else {
        continue
      }
      play(&states, id: aId, name: match.playerAName, opponentId: bId, scored: scoreA, allowed: scoreB)
      play(&states, id: bId, name: match.playerBName, opponentId: aId, scored: scoreB, allowed: scoreA)
    }
    let named = states.values.filter { $0.name != nil }
    let groups = rank(Array(named))
    var place = 1
    var rows: [Standing] = []
    for group in groups {
      for team in group {
        guard let name = team.name else { continue }
        rows.append(
          Standing(
            id: team.id,
            place: place,
            name: name,
            wins: team.wins,
            losses: team.losses,
            pointDifferential: team.differential
          )
        )
      }
      place += group.count
    }
    return rows
  }

  static func championId(matches: [BracketMatch]) -> String? {
    guard let finalRound = matches.map(\.round).max() else { return nil }
    let finals = matches.filter { $0.round == finalRound }
    guard finals.count == 1, let final = finals.first,
          let scoreA = final.scoreA, let scoreB = final.scoreB, scoreA != scoreB,
          let aId = final.playerAId, let bId = final.playerBId else {
      return nil
    }
    return scoreA > scoreB ? aId : bId
  }

  private static func play(
    _ states: inout [String: TeamState],
    id: String,
    name: String?,
    opponentId: String,
    scored: Int,
    allowed: Int
  ) {
    var team = states[id] ?? TeamState(id: id)
    if let name {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        team.name = trimmed
      }
    }
    team.games.append(Game(opponentId: opponentId, scored: scored, allowed: allowed))
    states[id] = team
  }

  private static func rank(_ teams: [TeamState]) -> [[TeamState]] {
    let buckets = Dictionary(grouping: teams, by: \.wins)
    var placed: [TeamState] = []
    var groups: [[TeamState]] = []
    for wins in buckets.keys.sorted(by: >) {
      guard let bucket = buckets[wins] else { continue }
      let broken = breakGroup(bucket, above: placed)
      groups.append(contentsOf: broken)
      placed.append(contentsOf: broken.flatMap { $0 })
    }
    return groups
  }

  private static func breakGroup(_ group: [TeamState], above: [TeamState]) -> [[TeamState]] {
    if group.count <= 1 {
      return [group]
    }
    let ids = Set(group.map(\.id))
    let splits: [[TeamState]]? =
      split(group, by: { RecordMark(wins: h2hWins($0, ids: ids), losses: h2hLosses($0, ids: ids)) })
      ?? split(group, by: { $0.differential })
      ?? split(group, by: { h2hDifferential($0, ids: ids) })
      ?? split(group, by: { differential(against: above, team: $0) })
      ?? split(group, by: { $0.scored })
    guard let splits else {
      return [group]
    }
    var ordered: [[TeamState]] = []
    var higher = above
    for subset in splits {
      let resolved = subset.count == 1 ? [subset] : breakGroup(subset, above: higher)
      ordered.append(contentsOf: resolved)
      higher.append(contentsOf: resolved.flatMap { $0 })
    }
    return ordered
  }

  private static func split<T: Hashable & Comparable>(
    _ group: [TeamState],
    by key: (TeamState) -> T?
  ) -> [[TeamState]]? {
    var marks: [(TeamState, T)] = []
    for team in group {
      guard let mark = key(team) else { return nil }
      marks.append((team, mark))
    }
    let unique = Set(marks.map(\.1))
    if unique.count <= 1 {
      return nil
    }
    return unique.sorted(by: >).map { mark in
      marks.filter { $0.1 == mark }.map(\.0)
    }
  }

  private static func h2hWins(_ team: TeamState, ids: Set<String>) -> Int {
    team.games.filter { ids.contains($0.opponentId) && $0.scored > $0.allowed }.count
  }

  private static func h2hLosses(_ team: TeamState, ids: Set<String>) -> Int {
    team.games.filter { ids.contains($0.opponentId) && $0.scored < $0.allowed }.count
  }

  private static func h2hDifferential(_ team: TeamState, ids: Set<String>) -> Int {
    team.games.filter { ids.contains($0.opponentId) }.reduce(0) { $0 + $1.scored - $1.allowed }
  }

  private static func differential(against above: [TeamState], team: TeamState) -> Int? {
    guard let nextWins = above.map(\.wins).filter({ $0 > team.wins }).min() else { return nil }
    let opponents = Set(above.filter { $0.wins == nextWins }.map(\.id))
    let games = team.games.filter { opponents.contains($0.opponentId) }
    if games.isEmpty {
      return nil
    }
    return games.reduce(0) { $0 + $1.scored - $1.allowed }
  }
}

private struct Game: Hashable {
  let opponentId: String
  let scored: Int
  let allowed: Int
}

private struct TeamState: Hashable {
  let id: String
  var name: String?
  var games: [Game] = []

  var wins: Int { games.filter { $0.scored > $0.allowed }.count }
  var losses: Int { games.filter { $0.scored < $0.allowed }.count }
  var scored: Int { games.reduce(0) { $0 + $1.scored } }
  var allowed: Int { games.reduce(0) { $0 + $1.allowed } }
  var differential: Int { scored - allowed }
}

private struct RecordMark: Hashable, Comparable {
  let wins: Int
  let losses: Int

  static func < (lhs: RecordMark, rhs: RecordMark) -> Bool {
    if lhs.wins != rhs.wins {
      return lhs.wins < rhs.wins
    }
    return lhs.losses > rhs.losses
  }
}
