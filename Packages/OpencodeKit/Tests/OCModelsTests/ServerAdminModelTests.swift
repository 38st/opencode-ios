import Foundation
import Testing
import OCFoundation
@testable import OCModels

@Test func configRedactionHidesSecretLookingValuesOnly() throws {
    let document = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
    {"providers":{"mock":{"settings":{"baseURL":"http://x","apiKey":"sk-1","api_key":"sk-2"},"headers":{"Authorization":"Bearer t","X-Api-Key":"k"}}},
     "mcp":{"servers":{"gh":{"type":"remote","environment":{"GITHUB_TOKEN":"ghp","PATH":"/bin"},"oauth":{"clientId":"id","clientSecret":"s"}}}},
     "keybinds":{"leader":"ctrl+x"},"monkey":"banana","password":null,"auth":{"type":"oauth","refresh_token":"r"},"keys":["a","b"],
     "tokens":7,"shell":"/bin/zsh","secretary":"visible","model":{"providerID":"mock","model":"m"}}
    """#.utf8))
    let redacted = ConfigRedaction.redact(document), hidden = JSONValue.string(ConfigRedaction.placeholder)
    #expect(redacted["providers"]?["mock"]?["settings"]?["apiKey"] == hidden)
    #expect(redacted["providers"]?["mock"]?["settings"]?["api_key"] == hidden)
    #expect(redacted["providers"]?["mock"]?["settings"]?["baseURL"]?.stringValue == "http://x")
    #expect(redacted["providers"]?["mock"]?["headers"]?["Authorization"] == hidden)
    #expect(redacted["providers"]?["mock"]?["headers"]?["X-Api-Key"] == hidden)
    #expect(redacted["mcp"]?["servers"]?["gh"]?["environment"]?["GITHUB_TOKEN"] == hidden)
    #expect(redacted["mcp"]?["servers"]?["gh"]?["environment"]?["PATH"]?.stringValue == "/bin")
    #expect(redacted["mcp"]?["servers"]?["gh"]?["oauth"]?["clientSecret"] == hidden)
    #expect(redacted["mcp"]?["servers"]?["gh"]?["oauth"]?["clientId"]?.stringValue == "id")
    #expect(redacted["auth"]?["type"] == hidden && redacted["auth"]?["refresh_token"] == hidden, "A secret-named block is hidden whole")
    #expect(redacted["keys"] == .array([hidden, hidden]) && redacted["tokens"] == hidden)
    #expect(redacted["keybinds"]?["leader"]?.stringValue == "ctrl+x" && redacted["monkey"]?.stringValue == "banana")
    #expect(redacted["secretary"]?.stringValue == "visible" && redacted["shell"]?.stringValue == "/bin/zsh")
    #expect(redacted["password"] == .null, "Absent values stay absent")
    let nested = ConfigRedaction.redact(.object(["credentials": .object(["user": .string("me"), "pass": .string("p")]), "APIKEY": .string("k1"), "apikey": .string("k2"), "accessKey": .string("k3")]))
    #expect(nested["credentials"]?["user"] == hidden && nested["credentials"]?["pass"] == hidden, "Everything under a secret name is hidden")
    #expect(nested["APIKEY"] == hidden && nested["apikey"] == hidden && nested["accessKey"] == hidden)
    let text = try redacted.prettyPrinted()
    for secret in ["sk-1", "sk-2", "Bearer t", "ghp", "\"s\"", "\"r\""] { #expect(!text.contains(secret), "\(secret) leaked") }
}

@Test func integrationsExposeAccountsMethodsAndStatus() {
    let info = IntegrationInfo(raw: .object(["id": .string("openai"), "name": .string("OpenAI"),
        "methods": .array([.object(["type": .string("oauth"), "id": .string("chatgpt"), "label": .string("ChatGPT Pro/Plus")]),
                           .object(["type": .string("key"), "form": .array([.object(["key": .string("org"), "type": .string("string"), "required": .bool(true)])])]),
                           .object(["type": .string("env"), "names": .array([.string("OPENAI_API_KEY")])]), .string("junk")]),
        "connections": .array([.object(["type": .string("credential"), "id": .string("cred_b"), "label": .string("Work"), "method": .string("oauth"),
                                        "status": .object(["status": .string("needs_auth"), "message": .string("Expired")])]),
                               .object(["type": .string("credential"), "id": .string("cred_a"), "label": .string("Home"), "method": .string("key")]),
                               .object(["type": .string("env"), "name": .string("OPENAI_API_KEY")])])]))
    #expect(info.accounts.map(\.credentialID) == ["cred_b", "cred_a"], "The active account first")
    #expect(info.environment.map(\.name) == ["OPENAI_API_KEY"] && info.needsAuth && info.isConnected)
    #expect(info.accounts[0].needsAuth?.message == "Expired")
    #expect(info.methods.map(\.label) == ["ChatGPT Pro/Plus", "API key", "Environment variable"])
    #expect(info.methods[1].form?.fields.count == 1 && info.methods[1].methodID == nil)
    #expect(info.methods.map(\.isEditable) == [true, true, false])
    #expect(AttemptStatus(raw: .object(["status": .string("pending"), "message": .string("Visit")])) == .pending(message: "Visit"))
    #expect(AttemptStatus(raw: .object(["status": .string("failed")])) == .failed("Sign-in failed."))
    #expect(!AttemptStatus(raw: .object(["status": .string("new")])).isTerminal && AttemptStatus(raw: .object(["status": .string("expired")])).isTerminal)
}

@Test func switcherFindsServerSettingsSections() {
    let settings = ServerSettingsSection.allCases.map { SwitcherIndex.Setting(server: "S", serverName: "Studio", section: $0) }
    #expect(SwitcherIndex.groups(query: "", commands: [], sessions: [], projects: [], settings: settings).isEmpty, "Only searches show settings")
    let groups = SwitcherIndex.groups(query: "api key", commands: [], sessions: [], projects: [], settings: settings)
    #expect(groups.map(\.title) == ["Settings"] && groups[0].entries.first?.title == "Providers")
    #expect(groups[0].entries.first?.kind == .settings("S:providers") && groups[0].entries.first?.detail == "Studio")
    #expect(SwitcherIndex.groups(query: "worktrees", commands: [], sessions: [], projects: [], settings: settings)[0].entries.first?.title == "Worktrees")
}
