═══════════════════════════════════════════════
  Marinara Engine + JanitorAI Launcher v1.0
  by invisibru
═══════════════════════════════════════════════

WHAT IS THIS?
  This adds JanitorAI back to the Marinara Engine Bot Browser.
  It was removed from the official release but this launcher
  patches it back in before each launch.

HOW TO USE:
  1. Make sure Marinara Engine is installed normally first
     (run the official installer/start.bat at least once)
  2. Extract the contents of this Zip file in any folder you want.
  3. Double-click "Launch.bat" here instead of the official start.bat
  4. That's it! JanitorAI will appear in the Bot Browser dropdown.

JANITORAI LOGIN (for character definitions):
  - JanitorAI browsing works WITHOUT login
  - To unlock character definitions (personality, first message, etc):
    1. Click the JanitorAI provider in Bot Browser
    2. Click "Log in for character definitions"
    3. Follow the instructions to paste your auth token

IF MARINARA UPDATES BREAK THE PATCH:
  - The launcher will detect if the target files changed
  - It will offer to launch without JanitorAI until I release
    an updated version of this launcher
  - You can always use the official start.bat as a fallback

FILES IN THIS FOLDER:
  Launch.bat                      - Double-click this to start
  launch.ps1                      - The actual launcher script
  bot-browser.routes.patched.ts   - Server routes with JanitorAI
  BotBrowserView.patched.tsx      - Client UI with JanitorAI
  known-hashes.txt                - Auto-generated on first run
  README.txt                      - This file

SUPPORT:
  @iaminvisibru on discord

Added support for linux users. just download the whole directory and run the .sh file
