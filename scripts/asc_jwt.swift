// Prints an App Store Connect API JWT (ES256) from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8.
import CryptoKit
import Foundation

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let env = ProcessInfo.processInfo.environment
guard let kid = env["ASC_KEY_ID"], let iss = env["ASC_ISSUER_ID"], var pem = env["ASC_KEY_P8"] else {
    FileHandle.standardError.write("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 must be set\n".data(using: .utf8)!)
    exit(1)
}
if !pem.contains("BEGIN PRIVATE KEY"), let d = Data(base64Encoded: pem), let s = String(data: d, encoding: .utf8) { pem = s }
// Secret stores often flatten the PEM's newlines into spaces; rebuild it from the base64 body.
let body = pem.replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
    .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
    .replacingOccurrences(of: "\\n", with: "")
    .filter { !$0.isWhitespace }
var lines: [String] = []
var rest = Substring(body)
while !rest.isEmpty { lines.append(String(rest.prefix(64))); rest = rest.dropFirst(64) }
pem = "-----BEGIN PRIVATE KEY-----\n" + lines.joined(separator: "\n") + "\n-----END PRIVATE KEY-----\n"
let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
let now = Int(Date().timeIntervalSince1970)
let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": kid, "typ": "JWT"])
let payload = try JSONSerialization.data(withJSONObject: ["iss": iss, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"])
let input = b64url(header) + "." + b64url(payload)
let sig = try key.signature(for: Data(input.utf8))
print(input + "." + b64url(sig.rawRepresentation))
