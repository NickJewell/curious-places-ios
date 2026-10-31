//
//  HuntMapView.swift
//  Curious Places
//

import MapKit
import SwiftUI

/// The hunt's map page: the user, the target, and rings around the target that
/// pulse faster as the user closes in (HuntMapView.tsx).
struct HuntMapView: View {
    let model: HuntModel
    @State private var position: MapCameraPosition
    @State private var hasFramed = false

    init(model: HuntModel) {
        self.model = model
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: model.target.coordinate, latitudinalMeters: 1300, longitudinalMeters: 1300
        )))
    }

    var body: some View {
        Map(position: $position) {
            // Drawn from the hunt's own fix (the one the distance uses); MapKit's
            // UserAnnotation didn't appear on this map in the simulator.
            if let location = model.location {
                Annotation("You", coordinate: location.coordinate, anchor: .center) {
                    UserDot()
                }
                .annotationTitles(.hidden)
            }
            Annotation(model.target.name, coordinate: model.target.coordinate, anchor: .center) {
                HuntTargetMarker(distance: model.progress.distance)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
        }
        .overlay(alignment: .bottom) {
            Text(summary)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(.black.opacity(0.78), in: .capsule)
                .overlay(Capsule().stroke(Theme.gold.opacity(0.35)))
                .padding(.bottom, 20)
        }
        .onChange(of: model.location != nil) { frameUserAndTarget() }
        .onAppear { frameUserAndTarget() }
    }

    private var summary: String {
        guard let distance = model.progress.distance else { return "Locating…" }
        let cardinal = model.bearing.map { "  ·  \(HuntMath.cardinal($0))" } ?? ""
        return HuntMath.formattedDistance(distance) + cardinal
    }

    /// Fits both points once, when the first fix arrives.
    private func frameUserAndTarget() {
        guard !hasFramed, let user = model.location?.coordinate else { return }
        hasFramed = true
        withAnimation { position = .region(MKCoordinateRegion(fitting: user, model.target.coordinate)) }
    }
}

extension MKCoordinateRegion {
    /// A square region around two points with room to spare, never closer in than about 300 m.
    init(fitting a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) {
        let span = max(abs(a.latitude - b.latitude), abs(a.longitude - b.longitude)) * 1.8
        self.init(
            center: CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2,
                                           longitude: (a.longitude + b.longitude) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(span, 0.003), longitudeDelta: max(span, 0.003))
        )
    }
}

private struct UserDot: View {
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 3)
            .accessibilityLabel("Your location")
    }
}

/// A gold dot, with pulse rings once within 1 km.
private struct HuntTargetMarker: View {
    let distance: CLLocationDistance?

    var body: some View {
        ZStack {
            if let distance, distance < HuntMath.pulseDistance {
                PulseRings(duration: HuntMath.pulseDuration(distance: distance))
                    // A new tier restarts the rings at its own speed.
                    .id(HuntMath.pulseTier(distance: distance))
            }
            Circle()
                .fill(Theme.gold)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: Theme.gold.opacity(0.8), radius: 6)
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel("Destination")
    }
}

private struct PulseRings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fixed for the life of the view; the parent changes `id` to change speed.
    @State private var duration: TimeInterval
    @State private var start = Date()

    init(duration: TimeInterval) {
        _duration = State(initialValue: duration)
    }

    var body: some View {
        if reduceMotion {
            ring(phase: 0.5)
        } else {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(start) / duration
                ZStack {
                    ForEach([0, 0.45], id: \.self) { offset in
                        ring(phase: (elapsed + offset).truncatingRemainder(dividingBy: 1))
                    }
                }
            }
        }
    }

    private func ring(phase: Double) -> some View {
        let eased = 1 - (1 - phase) * (1 - phase)
        let diameter = 24 + eased * 140
        return Circle()
            .stroke(Theme.gold.opacity(0.85 * (1 - phase)), lineWidth: 2.5)
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }
}
