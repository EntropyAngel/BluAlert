BLUAlert - Ashita v4 / Horizon
==============================

Purpose
-------
Plays a sound when a monster uses a Horizon Blue Magic spell that is in the
Horizon level-75-or-lower Blue Magic list.

Install
-------
1. Extract the BLUAlert folder into your Ashita v4 addons folder:
   horizon\\addons\\BLUAlert\\
2. Load it with:
   /addon load BLUAlert

Commands
--------
/blualert on       Enable alerts
/blualert off      Disable alerts
/blualert test     Play the sound immediately
/blualert debug    Print incoming chat lines to the console
/blualert status   Show current settings
/blualert reload   Reload settings
/blualert list     Show number of tracked spells

Important
---------
This first build intentionally uses the Ashita v4 text_in event. That lets us
verify exactly what Horizon sends for a monster ability before adding packet-
level parsing. If a particular Horizon battle-log message is not detected,
run /blualert debug, reproduce the mob ability, and the exact line can be added
without guessing at packet offsets.

Sound
-----
The included WAV is a short two-tone alert. You can replace it with any WAV
file and change sound_file in the settings if desired.

Horizon spell source
--------------------
The tracked list is based on the HorizonXI Blue Magic Spell List and is capped
at level 75 for Horizon's level-75-era spell set.
