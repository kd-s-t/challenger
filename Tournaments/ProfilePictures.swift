import Foundation

struct AvatarEligibility: Decodable, Equatable {
  let canUseExclusive: Bool
  let canUseBooker: Bool
  let canUseVeteran: Bool
  let canUseDev: Bool

  static let locked = AvatarEligibility(
    canUseExclusive: false,
    canUseBooker: false,
    canUseVeteran: false,
    canUseDev: false
  )
}

enum ProfilePictures {
  static let standard = [
    "pickleball-joola.png",
    "pickleball-vpro.png",
    "pickleball-gearbox.png",
    "pickleball-usapa.png",
    "pickleball-franklin.png",
  ]
  static let booker = [
    "paddle-enflexy-mjolnir.png",
    "paddle-juciao-vioe-x.png",
    "paddle-kuikma-open.png",
    "paddle-luzz-cannon.png",
    "paddle-warping-point-neon.png",
  ]
  static let veteran = [
    "paddle-selkirk-luxx.png",
    "paddle-selkirk-boomstik.png",
    "paddle-joola-razer.png",
    "paddle-joola-pro-v-perseus.png",
    "paddle-crbn-trufoam-genesis-2.png",
    "paddle-selkirk-omni.png",
    "paddle-wilson-vesper.png",
    "paddle-joola-perseus-pro-iv.png",
    "paddle-luzz-pro-4-inferno.png",
    "paddle-six-zero-dbd.png",
    "paddle-gearbox-pro-ultimate.png",
    "paddle-bread-butter-loco.png",
  ]
  static let exclusive = [
    "paddle-selkirk.jpg",
    "paddle-joola.jpg",
  ]
  static let dev = [
    "paddle-adidas-metalbone.png",
    "paddle-adidas-metalbone-sketch.png",
  ]

  static var all: [String] { standard + booker + veteran + exclusive + dev }

  private static let assets = URL(string: "https://xcourtcebu-assets.s3.ap-southeast-1.amazonaws.com")!

  static func imageURL(_ filename: String) -> URL? {
    let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    if name.hasPrefix("http://") || name.hasPrefix("https://") {
      return URL(string: name)
    }
    if name.hasPrefix("/") {
      return URL(string: name, relativeTo: APIConfig.baseURL)?.absoluteURL
    }
    let file = name.hasPrefix("profiles/") ? String(name.dropFirst("profiles/".count)) : name
    return assets.appending(path: "profiles").appending(path: file)
  }

  static func isUnlocked(_ file: String, eligibility: AvatarEligibility, stored: String?) -> Bool {
    if stored == file { return true }
    if standard.contains(file) { return true }
    if booker.contains(file) { return eligibility.canUseBooker }
    if veteran.contains(file) { return eligibility.canUseVeteran }
    if exclusive.contains(file) { return eligibility.canUseExclusive }
    if dev.contains(file) { return eligibility.canUseDev }
    return false
  }
}
