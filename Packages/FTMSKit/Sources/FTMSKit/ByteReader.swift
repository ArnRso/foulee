/// Erreur de décodage d'une trame FTMS.
public enum FTMSError: Error, Equatable, Sendable {
    /// La trame s'arrête avant la fin d'un champ annoncé par ses flags.
    case truncated(expectedAtLeast: Int, actual: Int)
    /// La trame ne correspond pas au format attendu.
    case malformed(String)
}

/// Lit des entiers little-endian à la suite dans une trame, sans jamais lire au-delà de la fin.
struct ByteReader {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: some Sequence<UInt8>) {
        self.bytes = Array(bytes)
    }

    var remaining: Int {
        bytes.count - offset
    }

    mutating func uint8() throws(FTMSError) -> UInt8 {
        UInt8(try unsigned(size: 1))
    }

    mutating func uint16() throws(FTMSError) -> UInt16 {
        UInt16(try unsigned(size: 2))
    }

    mutating func int16() throws(FTMSError) -> Int16 {
        Int16(bitPattern: try uint16())
    }

    mutating func uint24() throws(FTMSError) -> UInt32 {
        UInt32(try unsigned(size: 3))
    }

    mutating func uint32() throws(FTMSError) -> UInt32 {
        UInt32(try unsigned(size: 4))
    }

    private mutating func unsigned(size: Int) throws(FTMSError) -> UInt64 {
        guard remaining >= size else {
            throw .truncated(expectedAtLeast: offset + size, actual: bytes.count)
        }
        var value: UInt64 = 0
        for index in 0..<size {
            value |= UInt64(bytes[offset + index]) << (8 * index)
        }
        offset += size
        return value
    }
}

/// Représentation hexadécimale d'une trame, octets séparés par des espaces (« 80 00 01 »).
public func hexString(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { byte in
        let digits = String(byte, radix: 16, uppercase: false)
        return digits.count == 1 ? "0" + digits : digits
    }
    .joined(separator: " ")
}
