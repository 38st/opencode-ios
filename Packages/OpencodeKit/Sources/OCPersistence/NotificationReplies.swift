import Foundation
import GRDB

extension PersistenceWriter {
    /// Admission and receipt are one transaction. A duplicate response never rewrites the body,
    /// including after the outbox row was acknowledged and removed.
    public func admitNotificationReply(_ entry: OutboxEntry, notificationID: String) throws -> Bool {
        try database.write { db in
            if try String.fetchOne(db, sql: "SELECT input_id FROM notification_reply WHERE server_id=? AND notification_id=?", arguments: [entry.serverID, notificationID]) != nil { return false }
            try db.execute(sql: "INSERT INTO outbox(id,server_id,session_id,prelude,body,created_at,attempts,state,operation) VALUES (?,?,?,?,?,?,?,?,?)",
                arguments: [entry.id, entry.serverID, entry.sessionID, entry.prelude, entry.body, entry.createdAt.timeIntervalSinceReferenceDate, entry.attempts, entry.state, entry.operation])
            try db.execute(sql: "INSERT INTO notification_reply(server_id,notification_id,input_id) VALUES (?,?,?)", arguments: [entry.serverID, notificationID, entry.id])
            return true
        }
    }
}
