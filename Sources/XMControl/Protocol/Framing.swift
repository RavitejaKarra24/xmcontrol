import Foundation

// Sony MDR wire framing, shared between protocol V1 (XM3/XM4) and V2 (XM5).
//
//   0x3E | escaped( type, seq, len[4 BE], payload, checksum ) | 0x3C
//
// checksum = byte-sum(type, seq, len, payload) & 0xFF
// Any 0x3C / 0x3D / 0x3E in the body is escaped as 0x3D followed by
// (byte & 0xEF); decoding ORs the following byte with 0x10 to restore it.

enum Wire {
  static let sof: UInt8 = 0x3E
  static let eof: UInt8 = 0x3C
  static let esc: UInt8 = 0x3D

  /// DATA_MDR — command/response channel.
  static let dataMDR: UInt8 = 0x0C
  /// ACK frames.
  static let dataAck: UInt8 = 0x01
}

struct MDRFrame {
  let type: UInt8
  let seq: UInt8
  let payload: [UInt8]

  /// First payload byte — the response opcode (e.g. 0x67 for an ANC report).
  var opcode: UInt8? { payload.first }
  /// Second payload byte — the inquired/parameter type the opcode refers to.
  var subType: UInt8? { payload.count > 1 ? payload[1] : nil }
}

enum MDRFraming {
  static func encode(type: UInt8, seq: UInt8, payload: [UInt8]) -> Data {
    var inner: [UInt8] = [type, seq]
    let n = UInt32(payload.count)
    inner += [
      UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF),
      UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF),
    ]
    inner += payload
    inner.append(inner.reduce(UInt8(0)) { $0 &+ $1 })

    var out: [UInt8] = [Wire.sof]
    out.reserveCapacity(inner.count + 8)
    for b in inner {
      if b == Wire.sof || b == Wire.eof || b == Wire.esc {
        out.append(Wire.esc)
        out.append(b & 0xEF)
      } else {
        out.append(b)
      }
    }
    out.append(Wire.eof)
    return Data(out)
  }
}

/// Incremental parser — the RFCOMM stream arrives with arbitrary chunk
/// boundaries, so frames may be split across reads.
final class MDRFrameParser {
  /// Control replies are small. Never retain an unbounded Bluetooth stream.
  static let maximumPayloadLength = 4096
  private(set) var bufferedByteCount = 0
  private var inner: [UInt8] = []
  private var receiving = false
  private var escaped = false

  func reset() {
    inner.removeAll(keepingCapacity: true)
    bufferedByteCount = 0
    receiving = false
    escaped = false
  }

  func feed(_ data: Data) -> [MDRFrame] {
    var frames: [MDRFrame] = []
    for byte in data {
      // An unescaped start marker always resynchronizes a damaged stream.
      if byte == Wire.sof {
        reset()
        receiving = true
        continue
      }
      guard receiving else { continue }
      if byte == Wire.eof {
        if !escaped, let frame = decode() { frames.append(frame) }
        reset()
        continue
      }
      if escaped {
        guard [UInt8(0x2C), 0x2D, 0x2E].contains(byte) else {
          reset()
          continue
        }
        inner.append(byte | 0x10)
        escaped = false
      } else if byte == Wire.esc {
        escaped = true
      } else {
        inner.append(byte)
      }
      bufferedByteCount = inner.count
      if inner.count > Self.maximumPayloadLength + 7 {
        reset()
      } else if inner.count == 6, declaredLength > Self.maximumPayloadLength {
        reset()
      }
    }
    return frames
  }

  private var declaredLength: Int {
    (Int(inner[2]) << 24) | (Int(inner[3]) << 16)
      | (Int(inner[4]) << 8) | Int(inner[5])
  }

  private func decode() -> MDRFrame? {
    guard inner.count >= 7 else { return nil }
    let length = declaredLength
    guard length <= Self.maximumPayloadLength, inner.count == length + 7,
      inner[1] <= 1,
      inner[0] == Wire.dataMDR || inner[0] == Wire.dataAck,
      inner[0] != Wire.dataAck || length == 0,
      inner.dropLast().reduce(UInt8(0), &+) == inner.last
    else { return nil }
    return MDRFrame(type: inner[0], seq: inner[1], payload: Array(inner[6..<(6 + length)]))
  }
}
