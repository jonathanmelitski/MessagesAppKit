import Foundation

/// A value that can travel inside a message.
///
/// Messages gives you exactly one channel for custom data: `MSMessage.url`. Apple is explicit
/// that "all data passed between users in a conversation needs to be encoded in a URL". This
/// protocol marks the types you put through that channel; encoding is JSON, base64'd into a
/// single query item.
///
/// ```swift
/// struct Challenge: MessagePayload {
///     var name: String
///     var deadline: Date
/// }
/// ```
///
/// Two consequences of the transport worth keeping in mind. The payload is visible to anyone
/// who can see the URL, so it isn't a private channel. And it counts against a size ceiling —
/// exceed it and sending fails with ``MessagesAppKit/MessagesSessionError/urlExceedsMaxSize``,
/// so keep payloads to identifiers and small state rather than images or history.
public protocol MessagePayload: Codable {}

/// Why a payload couldn't be read out of, or written into, a message URL.
public enum MessagePayloadError: Error {
    /// The message carried no URL, or no payload query item within it.
    ///
    /// Expected when the selected message came from a different iMessage app, or from a version
    /// of yours that encoded things differently.
    case noPayload

    /// The query item was present but wasn't valid base64.
    case malformedPayload

    case encodingFailed(any Error)
    case decodingFailed(any Error)
}

/// Moves payloads in and out of `MSMessage.url`.
///
/// Split out from the session extension so the encoding is testable on its own and identical in
/// both directions.
enum PayloadCodec {
    /// Query item name holding the encoded payload.
    static let queryItemName = "data"

    static func encodeToURL(_ payload: some Encodable) throws -> URL {
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            throw MessagePayloadError.encodingFailed(error)
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: queryItemName, value: data.base64EncodedString())
        ]
        guard let url = components.url else {
            // Only reachable if URLComponents rejects the base64 alphabet, which it doesn't.
            throw MessagePayloadError.malformedPayload
        }
        return url
    }

    static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?
                  .first(where: { $0.name == queryItemName })?.value
        else {
            throw MessagePayloadError.noPayload
        }
        guard let data = Data(base64Encoded: encoded) else {
            throw MessagePayloadError.malformedPayload
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MessagePayloadError.decodingFailed(error)
        }
    }
}
