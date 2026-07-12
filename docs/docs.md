### Database Architecture

This is the Entity-Relationship Diagram (ERD) mapping the core tables in the Domix database.

```mermaid
erDiagram
    %% Relationship definition: One user can have zero or many stores
    User ||--o{ Store: "User table owns Store table using relationship (Single store and all store deletion supported)"

    User {
        id int PK "Internal Sequential ID"
        tg_id bigint UK "Unique Telegram ID"
        username varchar(32) "TG username @user"
        full_name varchar(128) "Extracted Profile Name"
        language varchar(2) "User chosen lang, default ru"
        created_at timestamp "When created" 
    }

    Store {
        id int PK "Internal Sequential ID"
        name varchar(100) "Store name"
        address text "Text address" 
        lat float "Composite Spatial Index"
        lon float "Composite Spatial Index"
        owner_id int FK "Refers and holds user.id"
        timestamp created_at
    }
```

### Auth via telegram bot
1. User presses "Verify through telegram" button in flutter app.
2. Flutter app generates a unique session id (https://t.me/domix_manager_bot?start=session_12345)
- The phone detects the t.me link and automatically opens the native Telegram app directly to our bot.
- The Telegram app hides the ?start=session_investor_99 part from the UI, but it saves it in memory.
- When the user taps the big "Start" button at the bottom of the chat, Telegram automatically formats a hidden command and fires it to your Go backend via the ngrok webhook:
"/start session_investor_99"



### Things to fix.
1. After registration through telegram completes, user can keep spamming /start and phone number button, we need to fix that.