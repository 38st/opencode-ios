import Foundation

/// ISO/IEC 7816-4 padding to 512, 1,024 or 2,048 bytes: the plaintext, 0x80, then zero bytes.
public enum PushPadding {
    public enum Failure: Error, Equatable {
        case tooLarge, invalid
    }

    public static var buckets: [Int] { PushContract.shared.padding.buckets }

    public static func bucket(for length: Int) -> Int? { buckets.first { length + 1 <= $0 } }

    public static func pad(_ plaintext: Data) throws -> Data {
        guard let bucket = bucket(for: plaintext.count) else { throw Failure.tooLarge }
        var padded = plaintext
        padded.append(PushContract.shared.padding.marker)
        padded.append(Data(count: bucket - padded.count))
        return padded
    }

    public static func unpad(_ padded: Data) throws -> Data {
        guard buckets.contains(padded.count), let last = padded.lastIndex(where: { $0 != 0 }),
              padded[last] == PushContract.shared.padding.marker else { throw Failure.invalid }
        return Data(padded[padded.startIndex..<last])
    }
}
