import GRDB
import OCModels

extension PersistenceWriter {
    public func sessionLocalMeta(serverID: String) throws -> [String: SessionLocalMeta] {
        try database.read { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT session_id,pinned,hidden FROM local_meta WHERE server_id=?", arguments: [serverID]).map {
                ($0["session_id"], SessionLocalMeta(pinned: $0["pinned"], hidden: $0["hidden"]))
            })
        }
    }
    public func setSessionLocalMeta(_ value: SessionLocalMeta, serverID: String, sessionID: String) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO local_meta(server_id,session_id,pinned,hidden) VALUES (?,?,?,?)
                ON CONFLICT(server_id,session_id) DO UPDATE SET pinned=excluded.pinned,hidden=excluded.hidden
                """, arguments: [serverID, sessionID, value.pinned, value.hidden])
        }
    }
}
