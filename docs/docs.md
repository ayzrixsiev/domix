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