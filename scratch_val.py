import sqlite3

conn = sqlite3.connect(r"backend\flowspace.db")
c = conn.cursor()

print("=== VALIDATION RESULTS ===")
for row in c.execute("SELECT id, room_id, rule_id, status, severity, message, actual_value FROM validation_results").fetchall():
    print(f"Room: {row[1]}, Rule: {row[2]}, Status: {row[3]}, Severity: {row[4]}, Msg: {row[5]}, Val: {row[6]}")

print("\n=== ANALYTICS / SCORES ===")
for row in c.execute("SELECT id, room_id, overall_score, accessibility_score, space_utilization_score, ergonomic_score, lighting_score FROM analytics").fetchall():
    print(f"Room: {row[1]}, Overall: {row[2]}, Access: {row[3]}, Util: {row[4]}, Ergo: {row[5]}, Light: {row[6]}")
