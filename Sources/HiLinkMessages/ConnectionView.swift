import SwiftUI

/// Fills the window while the app cannot be used: no stick found, no usable SIM, or no signal.
/// It goes away by itself once the stick is connected, the SIM is ready and there is service.
struct ConnectionView: View {
    let status: ModemStatus

    private enum Problem { case noStick, noSIM, noSignal }

    private var problem: Problem {
        if !status.isConnected { return .noStick }
        return status.simReady ? .noSignal : .noSIM
    }

    private var symbol: String {
        switch problem {
        case .noStick: "cable.connector.slash"
        case .noSIM: "simcard"
        case .noSignal: "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var title: String {
        switch problem {
        case .noStick: "Connect Your LTE Stick"
        case .noSIM: "No SIM Card"
        case .noSignal: "No Signal"
        }
    }

    private var explanation: String {
        switch problem {
        case .noStick: "Plug the Huawei LTE stick into this Mac to send and receive messages."
        case .noSIM: "The stick is connected, but it has no SIM card it can use. Insert a SIM to send and receive messages."
        case .noSignal: "The stick is connected, but it has no mobile signal. Try moving it somewhere with better reception."
        }
    }

    private var waiting: String {
        switch problem {
        case .noStick: "Looking for the stick…"
        case .noSIM: "Waiting for a SIM card…"
        case .noSignal: "Waiting for signal…"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Theme.outgoingBubble.opacity(0.14))
                    .frame(width: 112, height: 112)
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(Theme.outgoingBubble)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 22)

            Text(title)
                .font(.system(size: 26, weight: .bold))
                .padding(.bottom, 8)

            Text(explanation)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(waiting)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 26)

            if problem == .noStick {
                Text("Already plugged in? Give it a few seconds to start up, and check that HiLink Messages is allowed under System Settings › Privacy & Security › Local Network.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.threadBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: problem)
    }
}
