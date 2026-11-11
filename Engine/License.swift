//
//  License.swift
//  WorseFiles
//

import Foundation
import Network

enum License {
    static let expiry = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 11, day: 30, hour: 23, minute: 59, second: 59))!

    private(set) static var networkTime: Date?

    static var expired: Bool { referenceTime >= expiry }

    // Expiry is judged only against the NTP answer; without a network answer
    // we cannot trust the device clock, so access stays closed until a valid
    // time arrives.
    static var referenceTime: Date? { networkTime }

    private static let ntpOffset: TimeInterval = 2_208_988_800 // 1900 -> 1970

    // Minimal SNTP client over UDP :123. One request per call; falls back to
    // the device clock when the server is unreachable.
    static func fetchNetworkTime() async {
        let seconds = await requestNTPSeconds()
        if let seconds {
            networkTime = Date(timeIntervalSince1970: seconds - ntpOffset)
        }
    }

    static var hasTime: Bool { networkTime != nil }

    private static func requestNTPSeconds() async -> UInt64? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: "ntp.aliyun.com", port: 123,
                                          using: .udp)
            var finished = false
            let complete: (UInt64?) -> Void = { value in
                if !finished {
                    finished = true
                    connection.cancel()
                    continuation.resume(returning: value)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var packet = [UInt8](repeating: 0, count: 48)
                    packet[0] = 0x1B // LI=0, VN=4, Mode=3 (client)
                    connection.send(content: Data(packet), completion: .contentProcessed { error in
                        if error != nil {
                            complete(nil)
                            return
                        }
                        connection.receive(minimumIncompleteLength: 48,
                                           maximumLength: 48) { data, _, _, error in
                            guard error == nil, let data, data.count >= 48 else {
                                complete(nil)
                                return
                            }
                            let bytes = [UInt8](data)
                            let seconds = (UInt64(bytes[40]) << 24)
                                | (UInt64(bytes[41]) << 16)
                                | (UInt64(bytes[42]) << 8)
                                | UInt64(bytes[43])
                            complete(seconds == 0 ? nil : seconds)
                        }
                    })
                case .failed, .cancelled:
                    complete(nil)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }
}
