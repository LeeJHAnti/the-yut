# The Yut Server - Admin REST API

Admin endpoints for monitoring and managing game servers. These endpoints are available at `http://localhost:9001/admin/...`

## Endpoints

### 1. GET /admin/stats
Server statistics including total rooms, players, active games.

**Response:**
```json
{
  "success": true,
  "total_rooms": 5,
  "total_players": 12,
  "total_human_players": 10,
  "total_bot_players": 2,
  "active_games": 3,
  "waiting_for_players_rooms": 2,
  "games_over": 0
}
```

**Example:**
```bash
curl http://localhost:9001/admin/stats
```

---

### 2. GET /admin/rooms
List all active rooms with summary information.

**Response:**
```json
{
  "success": true,
  "total_rooms": 2,
  "rooms": [
    {
      "code": "ABC5",
      "player_count": 3,
      "player_names": ["Alice", "Bob", "Charlie"],
      "phase": "Throwing",
      "has_winner": false,
      "bot_count": 1,
      "human_count": 2
    },
    {
      "code": "XYZ2",
      "player_count": 2,
      "player_names": ["David", "Bot_Medium"],
      "phase": "WaitingForPlayers",
      "has_winner": false,
      "bot_count": 1,
      "human_count": 1
    }
  ]
}
```

**Example:**
```bash
curl http://localhost:9001/admin/rooms
```

---

### 3. GET /admin/rooms/{code}
Detailed information about a specific room, including pieces, turn state, and pending actions.

**Response:**
```json
{
  "success": true,
  "code": "ABC5",
  "phase": "Throwing",
  "current_turn": 0,
  "must_throw": true,
  "winner": null,
  "pending_piece_id": null,
  "pending_distance": null,
  "players": [
    {
      "id": 0,
      "name": "Alice",
      "is_host": true,
      "is_bot": false
    },
    {
      "id": 1,
      "name": "Bob",
      "is_host": false,
      "is_bot": false
    }
  ],
  "pieces": [
    {
      "id": 0,
      "owner": 0,
      "status": "Home",
      "node": null,
      "path": null,
      "stacked_with": []
    }
  ],
  "pending_results": [],
  "clients_connected": 2,
  "bots_count": 1
}
```

**Example:**
```bash
curl http://localhost:9001/admin/rooms/ABC5
```

---

### 4. DELETE /admin/rooms/{code}
Force delete a room and disconnect all players.

**Response:**
```json
{
  "success": true,
  "message": "Room ABC5 deleted",
  "players_disconnected": 3
}
```

**Example:**
```bash
curl -X DELETE http://localhost:9001/admin/rooms/ABC5
```

---

### 5. DELETE /admin/rooms/{code}/players/{player_id}
Kick a specific player from a room.

**Response:**
```json
{
  "success": true,
  "message": "Player 1 kicked from room ABC5",
  "player_name": "Bob",
  "remaining_players": 2
}
```

**Example:**
```bash
curl -X DELETE http://localhost:9001/admin/rooms/ABC5/players/1
```

---

## Logging

All admin operations are logged with structured logging:

```
[INFO] Admin: Listed 5 rooms
[INFO] Admin: Retrieved details for room ABC5
[WARN] Admin: Forced deletion of room ABC5 with 3 players
[WARN] Admin: Kicked player 1 (Bob) from room ABC5
[WARN] Admin: Attempted to delete non-existent room ZZZ9
```

## Game Event Logging

The server logs significant game events:

```
[INFO] Room created: code=ABC5, player_id=0, player_name='Alice' (host)
[INFO] Player 'Bob' (ID: 1) joined room ABC5
[INFO] Bot 'Bot_Easy' (difficulty: Easy, ID: 2) added to room ABC5 by player 0
[INFO] Game started in room ABC5: 3 players: ["Alice", "Bob", "Bot_Easy"]
[INFO] Game ended: winner='Alice' (ID: 0), all_players: ["Alice", "Bob", "Bot_Easy"]
[INFO] Player 'Bob' (ID: 1) left room ABC5
[INFO] Room ABC5 deleted (all players left)
```

## Notes

- No authentication is required (suitable for local development)
- All responses are JSON
- Room codes are case-insensitive in requests but stored in uppercase
- Deleting a room immediately disconnects all players
- Kicking a player sends a `player_left` message to other players in the room
- Empty rooms (all human players left) are automatically deleted
