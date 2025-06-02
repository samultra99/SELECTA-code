# Final-Project-SELECTA

See important notes at the bottom.
Video demo is here: https://youtu.be/oIxJC3Q_O1s
Link to download game executable, analysis executable and .command file is here: https://drive.google.com/drive/folders/1sitiBymjwwlvl3NGQYidzOp2Bd0OUHm1?usp=sharing

How to run SELECTA (my game) for testing:
1. Create a folder called 'AudioAnalysisData' in your user's home directory: /Users/[your username]/AudioAnalysisData
2. Place the 'AnalyseSong', 'Final Project Real.app' and 'Final Project Real.command' files from the Drive link above into this folder. The 'Final Project Real.app' is listed as a 'folder' in Google Drive for some reason, so don't forget to download that one too!
3. Run Final Project Real.command (NOT the main executable), you might need to go to Privacy & Security to give it permission to run on MacOS
4. The game should now be running! 
5. TO UPLOAD A NEW SONG: Press the right arrow key twice from the Main Menu and navigate to the dock where a new executable will have appeared. Select a song and then wait whilst it processes in the background. When it is done, the game will return to the main menu and you can select the song from the Quick Play list. Please see the known bug below, although it probably won't happen on your machine - it only seems to happen on mine!

Important: The game in its final form only supports MP3 files sadly.

Important: You do not need a controller to play. You can use the Left, Down and Right arrow keys as an alternative. In menus, X is Right arrow and Square is Down arrow. Even if you are using a controller, a keyboard is required to navigate the Quick Play menu.

Important: If you want to look at Player Performance data you can go into the player_lib file that is generated after at least one level has been fully completed.

Known Bug: Sometimes, when the song analysis process is happening in the background, it is interrupted by additional executables popping up asking you to select more songs to analyse. If this happens (it shouldn't) just click OK and then Cancel on each file selection box.
