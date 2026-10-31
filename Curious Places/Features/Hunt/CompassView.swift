//
//  CompassView.swift
//  Curious Places
//

import CoreLocation
import SwiftUI

/// The hunt's compass page: a dial that turns with the phone, a needle pointing
/// at the target, the distance, and both positions in degrees and minutes.
struct CompassView: View {
    let model: HuntModel

    var body: some View {
        VStack(spacing: 20) {
            if !model.isHeadingAvailable {
                notice("This device has no compass, so the needle can't point the way. Use the map instead.",
                       systemImage: "exclamationmark.triangle")
            }

            Spacer(minLength: 0)
            CompassDial(
                dialRotation: model.dialRotation,
                arrowRotation: model.heading != nil ? model.arrowRotation : nil,
                distance: model.progress.distance,
                accuracy: model.location?.horizontalAccuracy
            )
            .frame(maxWidth: 300)
            .padding(.horizontal, 40)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            Spacer(minLength: 0)

            if model.isHeadingAvailable && model.needsCalibration {
                notice("Move your phone in a figure-8 to improve compass accuracy",
                       systemImage: "exclamationmark.triangle.fill")
            }

            HStack(alignment: .top) {
                coordinates("MY LOCATION", model.location?.coordinate)
                coordinates("MY DESTINATION", model.target.coordinate)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.3)))
            .padding(.horizontal, 24)
    }

    private func coordinates(_ title: String, _ coordinate: CLLocationCoordinate2D?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .tracking(1)
                .foregroundStyle(.secondary)
            if let coordinate {
                Text(HuntMath.formatted(coordinate.latitude, isLatitude: true))
                Text(HuntMath.formatted(coordinate.longitude, isLatitude: false))
            } else {
                Text("Locating…")
            }
        }
        .font(.body.weight(.light))
        .monospacedDigit()
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var accessibilitySummary: String {
        guard let distance = model.progress.distance, let bearing = model.bearing else {
            return "Finding your location"
        }
        return "\(HuntMath.formattedDistance(distance)) away, to the \(HuntMath.cardinal(bearing))"
    }
}

/// The dial, its tick marks and cardinal labels, and the needle.
private struct CompassDial: View {
    let dialRotation: Double
    /// Nil hides the needle (no heading yet, or no compass).
    let arrowRotation: Double?
    let distance: CLLocationDistance?
    let accuracy: CLLocationAccuracy?

    private static let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    var body: some View {
        ZStack {
            Canvas { context, size in
                let radius = min(size.width, size.height) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for degrees in stride(from: 0, to: 360, by: 5) {
                    let isMajor = degrees % 45 == 0
                    let angle = Angle.degrees(Double(degrees) - 90).radians
                    let outer = radius - 8
                    let inner = radius - (isMajor ? 24 : 16)
                    var tick = Path()
                    tick.move(to: point(center, outer, angle))
                    tick.addLine(to: point(center, inner, angle))
                    context.stroke(tick, with: .color(.white.opacity(isMajor ? 1 : 0.6)), lineWidth: isMajor ? 2 : 1)
                    if isMajor {
                        let label = Text(Self.labels[degrees / 45])
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(degrees == 0 ? HuntPalette.needle : .white)
                        context.draw(label, at: point(center, radius - 42, angle))
                    }
                }
            }
            .rotationEffect(.degrees(dialRotation))

            Circle()
                .fill(HuntPalette.surface)
                .scaleEffect(0.55)
            VStack(spacing: 4) {
                Text(distance.map { "\(Int($0.rounded()))" } ?? "---")
                    .font(.system(size: 56, weight: .light))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("METRES")
                    .font(.subheadline.weight(.medium))
                    .tracking(2)
                if let accuracy, accuracy >= 0 {
                    Text("± \(Int(accuracy.rounded())) m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 140)

            if let arrowRotation {
                VStack {
                    Needle()
                        .fill(HuntPalette.needle)
                        .frame(width: 24, height: 24)
                        .offset(y: -4)
                    Spacer()
                }
                .rotationEffect(.degrees(arrowRotation))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dialRotation)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: arrowRotation)
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
}

private struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
