---
name: backend
description: >
  Core architectural rules, schema constraints, PostgreSQL behavior, authentication flows,
  and data mechanics for the Domix Go backend. Use when working on internal/endpoints,
  db/queries, authentication, or any Go server logic.
---

# Domix Backend Architecture & Rules

### Authentication & State
We use a passwordless Telegram flow. Pending logins live in RAM (`sync.Map`) to prevent creating "ghost" accounts in the database if a user abandons the process halfway. Session IDs use base64url to stay strictly under Telegram's 64-character deep-link limit. We never trust a JWT for user roles; our middleware checks the database live on every request so admin demotions take effect instantly.

### The Basket Price Index & History
This system ranks shop competitiveness. A "template" is a curated, shared list of standard products. To be ranked, a shop owner MUST price every single item in that template; otherwise, the mathematical comparison breaks. We divide their total basket cost by the market average to get their index score. Because this is a live database view, yesterday's prices vanish when an owner updates them. Thus, the `basket_history` table takes hourly snapshots, making it the only table holding historical data that cannot be recomputed.

### Product Photos
We generate two files per upload: a 1000px "master" for detail screens and a 400px `_thumb` for grid views to prevent massive bandwidth drain. The database only stores the master's path; the code assumes and derives the thumb. Photos are given random hash names upon upload so our aggressive 1-year cache doesn't serve stale images when an owner replaces a picture. The system automatically swaps between a local `Disk` backend for development and Cloudflare `R2` for production.

### Support & Schema Constraints
Support chats use an adaptive poll (10s to 60s) rather than websockets, saving significant network overhead. "Unread" states use a `last_read_id` watermark instead of boolean flags to prevent sync bugs when multiple admins read threads. In the schema, `products.template_key` is vital as it separates our curated global products from custom owner additions. Finally, `products.price` is nullable because an unpriced item is fundamentally different from a free (0) item.