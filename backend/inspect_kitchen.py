import sqlite3, json

conn = sqlite3.connect('backend/flowspace.db')
c = conn.cursor()
c.execute("SELECT id, room_name, room_type, properties FROM rooms WHERE id = 'dae9a071-cdb7-4156-bf52-6ac151f955c5'")
r = c.fetchone()
if r:
    print('Room name:', r[1], 'type:', r[2])
    props = json.loads(r[3]) if r[3] else {}
    print('Openings:', props.get('openings'))
    print('Furniture count:', len(props.get('furniture', [])))
    for f in props.get('furniture', []):
        print(f.get('name'), 'cat:', f.get('category'), 'pos:', f.get('x'), f.get('y'), f.get('z'), 'rot:', f.get('rotation'))
else:
    print('Room not found')
