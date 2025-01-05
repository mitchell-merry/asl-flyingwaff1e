state("I Am Your Beast") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");
    vars.Helper.GameName = "I Am Your Beast";

    settings.Add("ILs", false, "Individual Level Mode (start on every level, reset when level resets)");
    settings.Add("igt", false, "Use in-game-time instead of real time");
    
    vars.Helper.AlertLoadless();
}

init
{
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono => {

        //Level states: 0 - intro; 1 - active; 2 - completed; 3 - failed.
        vars.Helper["levelState"] = mono.Make<byte>("GameManager", "instance", "levelController", "levelState");

        //Transition states: 0 - TransitioningOut; 1 - Holding; 2 - TransitioningIn.
        //Timer pauses during 0 and 1 since the player can't control Harding during those states.
        vars.Helper["sceneTransition"] = mono.Make<byte>("GameManager", "instance", "activeSceneTransition", "state");

        //Tracks if player is active. Makes split starts more precise.
        vars.Helper["tracking"] = mono.Make<bool>("GameManager", "instance", "levelController", "gameplayTracker", "tracking");

        // Note that the following time values will stay whatever they last were while in the level select screen,
        //   and only reset once a level has been loaded.
        // Total elapsed time since level start.
        vars.Helper["combatTime"] = mono.Make<float>("GameManager", "instance", "levelController", "combatTimer", "timer");
        // Time "regained" from killing enemies, etc. (the IGT is combatTime - regainedCombatTime)
        vars.Helper["regainedCombatTime"] = mono.Make<float>("GameManager", "instance", "levelController", "combatTimer", "regainedTime");
        // Self explanatory. Stays true while in the level complete screen.
        vars.Helper["timerStarted"] = mono.Make<bool>("GameManager", "instance", "levelController", "combatTimer", "timerStarted");

        //Technically a transition destination, but works as a current scene
        vars.Helper["destination"] = mono.MakeString("GameManager", "instance", "activeSceneTransition", "destination");

        //#25 Mercy split
        vars.Helper["cutsceneID"] = mono.Make<byte>("GameManager", "instance", "cutsceneInfoStorer", "sequence", "ID");

        return true;
    });

    vars.totalIGT = 0;
    vars.hasCompletedCurrentLevel = false;
}

onStart
{
    vars.totalIGT = 0;
    vars.hasCompletedCurrentLevel = false;
}

update
{
    if (!vars.hasCompletedCurrentLevel && old.levelState == 1 && current.levelState == 2) {
        // Level complete - so the next time the timer resets, do not add any time
        vars.hasCompletedCurrentLevel = true;
    }

    if (current.combatTime == 0 && old.combatTime != 0) {
        if (!vars.hasCompletedCurrentLevel) {
            // Player reset the level (do not give regained time, penalise them for it)
            vars.totalIGT += old.combatTime;
        } else {
            // Level has probably just been loaded into
            vars.hasCompletedCurrentLevel = false;
        }
    }

    if (old.levelState == 1 && current.levelState == 2) {
        // Player beat the level, give the regained time
        vars.totalIGT += current.combatTime - current.regainedCombatTime;
    }
}

isLoading
{
    if (settings["igt"]) {
        // If we return false in isLoading then livesplit will continue to increment time.
        // If IGT mode is enabled, we want to be in full control of the timer, so we disable it here
        return true;
    }

    if (current.destination == "Scenes/!___STORY SCENES/#01a_Special_Tutorial" || current.destination == "#01c_Special_Tutorial") {
        return current.sceneTransition != 2;
    }

    return current.sceneTransition != 2 || current.destination == "Scenes/UI/Menus/LevelSelect" || current.levelState == 2 || current.levelState == 0;
}

gameTime
{
    if (settings["igt"]) {
        // Add a base 60 (like the leaderboards have) to deal with negative times.
        // Someone could break this if they get more than 60 seconds of negative time in a run.
        // (LiveSplit will not save negative times)
        var baseTime = 60 + vars.totalIGT;
        
        if (current.levelState == 1) {
            // If the level is active, we should track whatever the current time is
            var currentLevelTimeSeconds = current.combatTime - current.regainedCombatTime;
            return TimeSpan.FromSeconds(baseTime + currentLevelTimeSeconds);
        } else {
            return TimeSpan.FromSeconds(baseTime);
        }
    }
}

start
{
    if (settings["igt"]) {
        // Timer starts when the combat time starts for IGT, not when you reset the level
        return !old.timerStarted && current.timerStarted;
    }

    bool hasLoadedIntoLevel = current.sceneTransition == 2 && old.tracking == false && current.tracking == true;
    if (settings["ILs"]) {
        return hasLoadedIntoLevel;
    }
    
    return hasLoadedIntoLevel && current.destination == "Scenes/!___STORY SCENES/#01a_Special_Tutorial";
}

split
{
    if (current.cutsceneID == 22 && old.destination == "Scenes/UI/Cutscenes/Cutscene") {
        return old.destination == "Scenes/UI/Cutscenes/Cutscene" && current.destination == "Scenes/UI/Menus/LevelSelect";
    } else {
        return (old.destination == "#01c_Special_Tutorial" && current.destination == "Scenes/UI/Menus/LevelSelect") || (old.levelState == 1 && current.levelState == 2);
    }
}

reset
{
    if (settings["ILs"]) {
        return !current.timerStarted && old.timerStarted;
    }
}