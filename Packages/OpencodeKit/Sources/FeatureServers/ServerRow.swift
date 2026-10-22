import SwiftUI
import OCDesign
import Foundation
import OCModels
import OCSync

public struct ServerRow: View {
    let name: String
    let state: ConnectionState
    let endpoints: [EndpointRecord]
    let expiresSoon: Bool
    let now: ContinuousClock.Instant
    public init(name: String, state: ConnectionState, endpoints: [EndpointRecord], expiresSoon: Bool = false,
                now: ContinuousClock.Instant = .now) {
        self.name = name; self.state = state; self.endpoints = endpoints
        self.expiresSoon = expiresSoon; self.now = now
    }
    public var body: some View {
        let status = ServerStatus(state: state, endpoints: endpoints, now: now)
        VStack(alignment: .leading, spacing: OCSpacing.sm) {
            Text(name).font(OCType.heading).foregroundStyle(OCColor.text)
            StatusPill(status: status)
            if let detail = status.detail {
                Text(detail).font(OCType.body).foregroundStyle(OCColor.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            if isUnencrypted {
                OCLabel("Unencrypted", icon: "lock")
                    .font(OCType.small).foregroundStyle(OCColor.textMuted)
                    .accessibilityLabel("Unencrypted HTTP connection")
            }
            if expiresSoon {
                OCLabel("Pairing expires soon", icon: "lock")
                    .font(OCType.body).foregroundStyle(OCColor.warning)
            }
        }
        .padding(.vertical, OCSpacing.sm)
        .accessibilityElement(children: .contain)
    }
    private var isUnencrypted: Bool {
        if case .connected(let id, _) = state { return endpoints.first { $0.id == id }?.url.scheme == "http" }
        return endpoints.contains { $0.url.scheme == "http" }
    }
}

struct StatusPill: View {
    let status: ServerStatus
    private var tone: OCTone {
        switch status.tone {
        case .good: .success
        case .progress: .info
        case .warning: .warning
        case .neutral: .neutral
        }
    }
    var body: some View {
        OCPill(status.title, tone: tone)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.title + (status.detail.map { ", " + $0 } ?? ""))
            .accessibilityIdentifier("serverConnectionStatus")
            .accessibilityValue(status.stateIdentifier)
    }
}
