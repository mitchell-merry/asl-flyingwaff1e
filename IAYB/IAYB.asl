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

        vars.Helper["levelId"] = mono.Make<int>("GameManager", "instance", "levelController", "informationSetter", "levelInformation", "levelNumber");
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

    vars.IsRealTimeLevel = (Func<dynamic, bool>)(state => {
        // tutorial, cavalry, permafrost
        return state.levelId == 1 || state.levelId == 8 || state.levelId == 15;
    });

    vars.GetLevelInGameTime = (Func<dynamic, bool, float>)((state, includeRegainedTime) => {
        // Just use real elapsed time for these levels
        if (vars.IsRealTimeLevel(current)) {
            return (float)vars.levelRealTimeStopwatch.Elapsed.TotalSeconds;
        }

        if (includeRegainedTime) {
            return state.combatTime - state.regainedCombatTime;
        }
        
        return state.combatTime;
    });

    vars.JustLoadedLevel = (Func<dynamic, dynamic, bool>)((oldState, currentState) => {
        return currentState.sceneTransition == 2 && oldState.tracking == false && currentState.tracking == true;
    });

    vars.JustCompletedLevel = (Func<dynamic, dynamic, bool>)((oldState, currentState) => {
        if (currentState.cutsceneID == 22 && oldState.destination == "Scenes/UI/Cutscenes/Cutscene") {
            return oldState.destination == "Scenes/UI/Cutscenes/Cutscene" && currentState.destination == "Scenes/UI/Menus/LevelSelect";
        } else {
            return (oldState.destination == "#01c_Special_Tutorial" && currentState.destination == "Scenes/UI/Menus/LevelSelect")
                || (oldState.levelState == 1 && currentState.levelState == 2);
        }
    });

    vars.totalIGT = 0;
    vars.hasCompletedCurrentLevel = false;
    vars.timeAddedForAttempt = false;
    vars.levelRealTimeStopwatch = new Stopwatch();
}

onStart
{
    vars.totalIGT = 0;
    vars.hasCompletedCurrentLevel = false;
    vars.timeAddedForAttempt = false;
}

onReset
{
    vars.levelRealTimeStopwatch.Reset();
    vars.Log("real time stopwatch reset " + vars.totalIGT);
}

update
{
    if (old.sceneTransition != current.sceneTransition) {
        vars.Log("sceneTransition: " + old.sceneTransition + " -> " + current.sceneTransition);
    }
    if (old.cutsceneID != current.cutsceneID) {
        vars.Log("cutsceneID: " + old.cutsceneID + " -> " + current.cutsceneID);
    }
    if (old.tracking != current.tracking) {
        vars.Log("tracking: " + old.tracking + " -> " + current.tracking);
    }
    if (old.levelId != current.levelId) {
        vars.Log("levelId: " + old.levelId + " -> " + current.levelId);
    }

    if (old.levelState != current.levelState) {
        vars.Log("levelState: " + old.levelState + " -> " + current.levelState);
    }

    if (old.destination != current.destination) {
        vars.Log("destination: " + old.destination + " -> " + current.destination);
    }

    if (old.combatTime != 0 && current.combatTime == 0) {
        vars.Log("combatTime reset at " + old.combatTime + ": " + current.levelState);
    }

    vars.AddInGameTime = (Action<float>)(time => {
        vars.totalIGT += time;
        vars.Log("totalIGT: " + vars.totalIGT + " (" + time + ")");
        vars.timeAddedForAttempt = true;
        vars.levelRealTimeStopwatch.Reset();
    });

    if (vars.JustCompletedLevel(old, current)) {
        // Level complete - so the next time the timer resets, do not add any time
        vars.hasCompletedCurrentLevel = true;

        // Player beat the level, give the regained time
        // Add an hour (like the leaderboards have) to deal with negative times.
        // (LiveSplit will not save negative times on segments, so it needs to be on every split)
        vars.AddInGameTime(3600 + vars.GetLevelInGameTime(current, true));
    }

    var timeReset = current.combatTime == 0 && old.combatTime != 0;
    if (
        !vars.hasCompletedCurrentLevel && !vars.timeAddedForAttempt && (
            // Player reset the level
            timeReset ||
            // Player died
            (old.levelState == 1 && current.levelState == 3)
        )
    ) {
        // Do not give regained time, penalise them for it
        vars.AddInGameTime(vars.GetLevelInGameTime(old, false));
    }
    
    if (timeReset) {
        // Level has probably just been loaded into, so they haven't completed this level
        vars.hasCompletedCurrentLevel = false;
    }

    if (old.combatTime == 0 && current.combatTime != 0) {
        // Time's just started so new attempt
        vars.timeAddedForAttempt = false;
    }

    // Track real time for levels that need it
    if (vars.JustLoadedLevel(old, current)) {
        vars.Log("timer started: '" + current.destination + "', levelId: " + current.levelId);
        vars.levelRealTimeStopwatch.Start();
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
        if (current.levelState == 1 || vars.IsRealTimeLevel(current)) {
            // If the level is active, we should track whatever the current time is as it happens
            return TimeSpan.FromSeconds(vars.totalIGT + vars.GetLevelInGameTime(current, true));
        } else {
            return TimeSpan.FromSeconds(vars.totalIGT);
        }
    }

    // Don't set game time if not in IGT mode, let livesplit increment timer as normal
}

start
{
    bool justLoadedIntoLevel = vars.JustLoadedLevel(old, current);
    if (!settings["ILs"]) {
        return justLoadedIntoLevel && current.levelId == 1;
    }

    if (settings["igt"]) {
        // Timer starts when the combat time starts for IGT, not when you reset the level
        return (!old.timerStarted && current.timerStarted) || (
            vars.IsRealTimeLevel(current) && justLoadedIntoLevel
        );
    }
    
    return justLoadedIntoLevel;
}

split
{
    return vars.JustCompletedLevel(old, current);
}

reset
{
    if (settings["ILs"]) {
        return !current.timerStarted && old.timerStarted;
    }
}