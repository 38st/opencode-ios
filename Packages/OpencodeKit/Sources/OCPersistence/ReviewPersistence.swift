import Foundation
import GRDB
import OCModels

extension PersistenceWriter {
    public func reviewState(serverID: String, sessionID: String) throws -> (ReviewState, Set<String>) {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT review_state,reviewed_files FROM local_meta WHERE server_id=? AND session_id=?", arguments: [serverID, sessionID]) else { return (.init(), []) }
            let state: Data? = row["review_state"], marks: Data? = row["reviewed_files"]
            return (state.flatMap { try? JSONDecoder().decode(ReviewState.self, from: $0) } ?? .init(),
                    marks.flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? [])
        }
    }
    public func saveReviewState(serverID: String, sessionID: String, state: ReviewState, reviewed: Set<String>) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO local_meta(server_id,session_id,review_state,reviewed_files) VALUES (?,?,?,?)
                ON CONFLICT(server_id,session_id) DO UPDATE SET review_state=excluded.review_state,reviewed_files=excluded.reviewed_files
                """, arguments: [serverID, sessionID, try JSONEncoder().encode(state), try JSONEncoder().encode(reviewed)])
        }
    }
}
