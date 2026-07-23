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

### Auth via telegram bot backend flow
1. User presses create account in flutter app then he is prompted to choose to pick a role (shop owner or customer) and write down his name first and family name, after it he presses "Verify through telegram" button.
2. Flutter app hits http point api/auth/init and sends a json containing gathered info: role, name.
3. Our backend receives this json data and generates random sessionID, after that using SessionManager's sync map called sessions, it links this sessionID with SessionData, like this:
```go
sm.sessions.Store(sessionID, SessionData{           
	Status:    "pending",               
	Name:      receivedName,                    
	Role:      receivedRole,                    
	CreatedAt: time.Now(),              
})      
```                                
4. Our backend sends telegram link and attaches to it sessionID to the flutter app, flutter app opens a telegram with that sessionID, sessionID is then send by telegram bot back to our backend with telegram's chatID.
5. Our backend using SessionManager's sync map called chatToSession, connects that sessionID with chatID, and this way we know who's phone number we will get from this particular chat.
6. After that we prompt a user to send his phone number, once he does that, telegram sends chatID along side his phone number to our backend, we check whether the user exists (if yes we check whether his role changed and edit it if needed), if he does we log in, if no we sign him up and generate jwt token and send it to the flutter app.

### Auth via telegram bot flluter flow:
1. frontend/lib/features/profile/data/auth_service.dart - file that contains code for initializing handshake with go backend. It sends collected data to the backend, does polling to check the status of a login ticket and stores JWT and role inside user's hardware encrypted storage.
2. frontend/lib/features/profile/presentation/controllers/auth_controller.dart - file that orchestrates the whole auth process, by initializing authService, initializing handshake with backend, setting up pollling, based on the incoming output dictates how to render the page in profile section.






### Things to fix and work on
1. ~~After registration through telegram completes, user can keep spamming /start and phone number button, we need to fix that.~~
2. ~~How to handle role separation in app between shop owner and normal user.~~
3. ~~Make jwt token live longer - one year~~
4. Auth security improvement - two token strategy set up.
5. CLEAN UP THE SYSTEM FROM DEV PACKAGES LIKE DEVICE PREVIEW IN FLUTTER.

### LOCAL TESTING
TRUNCATE TABLE users RESTART IDENTITY CASCADE;
ngrok http 8080
flutter run --dart-define-from-file=env.json