## bot/handlers
This folder contains code which is responsible for reposnding to user interactions/commands. For example: Adding a store.
Folders inside handler
1. common.py - responsible for four main steps, printing a hello message to "start" command, language pick, number registration, main profile and buttons print. 

## bot/statesFSM
This is an implementation of FSM states for each event, like registration, adding store, editing store and etc. FSM is "long-term memory." By default, the bot "forgets" the user immediately after a response. FSM helps the bot remember: "Aha, this user is currently entering the store name; after their message, this is the object name."
Example: States/store_states.py (list of steps: wait for address -> wait for photo -> wait for phone number).

## database
SQLAlchemy objects