import MapKit
import SwiftUI

struct VenueLocation: Equatable {
  var latitude: Double
  var longitude: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

struct VenueMap: View {
  var name: String
  var latitude: Double
  var longitude: Double

  var body: some View {
    Map(
      position: .constant(
        .region(
          MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
          )
        )
      )
    ) {
      Marker(name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }
    .frame(height: 220)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }
}

struct VenueSearch: View {
  var markerName: String
  @Binding var location: VenueLocation?
  @State private var query = ""
  @State private var lockedQuery: String?
  @State private var hits: [MKMapItem] = []
  @State private var searching = false
  @State private var position: MapCameraPosition = .region(
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 10.3157, longitude: 123.8854),
      span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
    )
  )

  var body: some View {
    ZStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 10) {
        AuthField(title: "Venue location", text: $query)
        MapReader { proxy in
          Map(position: $position) {
            if let location {
              Marker(markerTitle, coordinate: location.coordinate)
            }
          }
          .onTapGesture { point in
            guard let coordinate = proxy.convert(point, from: .local) else { return }
            let next = VenueLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            location = next
            hits = []
            focus(next)
          }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        }
      }
      if !hits.isEmpty {
        dropdown
          .padding(.top, 78)
      }
    }
    .onAppear {
      if let location { focus(location) }
    }
    .onChange(of: query) { _, text in
      if text == lockedQuery { return }
      lockedQuery = nil
      Task { await search(text) }
    }
  }

  private var dropdown: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(hits.enumerated()), id: \.offset) { _, item in
        let title = item.name ?? item.placemark.name ?? ""
        if !title.isEmpty {
          Button {
            choose(item, title: title)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
              if let line = item.placemark.title, line != title {
                Text(line)
                  .font(.system(size: 13))
                  .foregroundStyle(Theme.mute)
                  .lineLimit(1)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
    .shadow(color: Theme.ink.opacity(0.12), radius: 12, y: 6)
  }

  private var markerTitle: String {
    let trimmed = markerName.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Pinned" }
    return trimmed
  }

  private func search(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else {
      hits = []
      return
    }
    searching = true
    defer { searching = false }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = trimmed
    do {
      let response = try await MKLocalSearch(request: request).start()
      if query == text {
        hits = Array(response.mapItems.prefix(6))
      }
    } catch {
      hits = []
    }
  }

  private func choose(_ item: MKMapItem, title: String) {
    let next = VenueLocation(
      latitude: item.placemark.coordinate.latitude,
      longitude: item.placemark.coordinate.longitude
    )
    lockedQuery = title
    location = next
    query = title
    hits = []
    focus(next)
  }

  private func focus(_ location: VenueLocation) {
    position = .region(
      MKCoordinateRegion(
        center: location.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
      )
    )
  }
}
