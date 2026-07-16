### Database Architecture

This is the Entity-Relationship Diagram (ERD) mapping the core tables in the Domix database.

```mermaid
erDiagram
    %% Relationship definitions
    User ||--o{ Shop : "User owns zero or many Shops (Cascade Delete)"
    Shop ||--o{ Product : "Shop contains zero or many Products (Cascade Delete)"

    User {
        bigint id PK "Internal Sequential ID"
        varchar name "Contact Name (Nullable)"
        varchar phone UK "Unique Phone Number"
        bigint telegram_chat_id UK "Unique Telegram Chat ID (Nullable)"
        varchar role "Role (customer, shop_owner, admin)"
        timestamp created_at "Creation timestamp"
        timestamp updated_at "Update timestamp"
    }

    Shop {
        bigint id PK "Internal Sequential ID"
        bigint user_id FK "Refers to users.id"
        varchar name "Shop name"
        text address "Physical text address"
        numeric rating "Shop rating (0.0 to 5.0)"
        int average_paycheck "Average customer check size"
        geometry location "PostGIS spatial point (lat/long)"
        timestamp created_at "Creation timestamp"
        timestamp updated_at "Update timestamp"
    }

    Product {
        bigint id PK "Internal Sequential ID"
        bigint shop_id FK "Refers to shops.id"
        varchar name "Product name"
        bigint price "Product price"
        varchar category "Product category designation"
        timestamp created_at "Creation timestamp"
        timestamp updated_at "Update timestamp"
    }
```

### Auth via telegram bot
1. User presses create account in flutter app then he is prompted to choose to pick a role, whether he is a customer or shop owner, after it he presses "Verify through telegram" button.
2. Flutter app generates a unique session id and user picked role into the link (https://t.me/domix_manager_bot?start=session_12345_shop_onwer)
- The phone detects the t.me link and automatically opens the native Telegram app directly to our bot.
- The Telegram app hides the ?start=session_12345 and role parts from the UI, but it saves it in memory.
- When the user taps the "Start" button at the bottom of the chat, Telegram automatically formats a hidden command and fires it to our Go backend via the ngrok webhook:
"/start session_12345"
- Our backend gets chatid, session id and role, after user sends phone number to our telegram bot, telegram sends chatid and phone number and this way we can identify from which chat we got the phone number and wanted flutter app.


### Things to fix.
1. After registration through telegram completes, user can keep spamming /start and phone number button, we need to fix that.
2. How to handle role separation in app between shop owner and normal user.
3. Make jwt token live longer - one year

TRUNCATE TABLE users RESTART IDENTITY CASCADE;