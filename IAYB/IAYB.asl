state("I Am Your Beast") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");
    vars.Helper.GameName = "I Am Your Beast";

    settings.Add("ILs", false, "Individual Level Mode (start on every level, reset when level resets)");
    settings.Add("igt", false, "Use in-game-time instead of real time (does not work for full game)", "ILs");
    settings.Add("objectives", false, "Split on main objective progress", "ILs");
    
    vars.Timer = new TimerModel { CurrentState = timer };

    vars.Helper.AlertLoadless();
}

init
{
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
        // used to identify if we're on Mercy (25)
        // note that this is only level number within a pack. which means ids <= 12 are ambiguous (multiple levels share that number)
        vars.Helper["level"] = mono.Make<int>("GameManager", "instance", "levelController", "informationSetter", "levelInformation", "levelNumber");

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

        // OBJECTIVES
        vars.Helper["mainObjectiveIndex"] = mono.Make<int>("GameManager", "instance", "objectiveManager", "currentMainObjective");
        vars.Helper["mainObjectives"] = mono.MakeArray<IntPtr>("GameManager", "instance", "objectiveManager", "mainObjectives");

        vars.Helper["enemiesKilled"] = mono.Make<int>("GameManager", "instance", "levelController", "totalEnemiesKilledInLevel");
        vars.Helper["enemiesInLevel"] = mono.Make<int>("GameManager", "instance", "AI", "totalEnemiesInLevel");

        var LOInteractWithObjects = mono["LevelObjectiveInteractWithObjects"];
        var PlayerInteractableGenericOneUse = mono["PlayerInteractableGenericOneUse"];
        
        var LevelObjectiveDestroyObjects = mono["LevelObjectiveDestroyObjects"];

        vars.ReadObjectiveType = (Func<IntPtr, string>)(objectivePtr =>
        {
            return vars.Helper.ReadString(256, ReadStringType.UTF8, objectivePtr + 0x0, 0x0, 0x48, 0);
        });

        vars.ReadObjectiveProgress = (Func<IntPtr, int>)(objectivePtr =>
        {
            var type = vars.ReadObjectiveType(objectivePtr);
            var prog = vars.GetObjectiveProgress(objectivePtr, type);
            
            // vars.Log("mainObjectiveIndex: " + current.mainObjectiveIndex);
            // vars.Log("Objective at 0x" + objectivePtr.ToString("X"));
            // vars.Log("- type: " + type);
            // vars.Log("- progress: " + prog);

            return prog;
        });

        vars.GetObjectiveProgress = (Func<IntPtr, string, int>)((objectivePtr, objectiveType) =>
        {
            switch (objectiveType) {
                case "LevelObjectiveInteractWithObjects":
                    var progress = 0;
                    
                    var interactables = vars.Helper.ReadArray<IntPtr>(objectivePtr + LOInteractWithObjects["interactables"]);
                    foreach (var interactablePtr in interactables) {
                        var interactedWith = vars.Helper.Read<bool>(interactablePtr + PlayerInteractableGenericOneUse["interactedWith"]);
                        progress += interactedWith ? 1 : 0;
                    }

                    // -3: the objective was completed. we should not use the intra-objective progress to split between objectives
                    return interactables.Length != progress ? progress : -3;
                case "LevelObjectiveKillAllEnemies":
                    return current.enemiesKilled != current.enemiesInLevel ? current.enemiesKilled : -3;
                case "LevelObjectiveDestroyObjects":
                    var destroyedTargets = vars.Helper.Read<int>(objectivePtr + LevelObjectiveDestroyObjects["destroyedTargets"]);
                    var targets = vars.Helper.ReadArray<IntPtr>(objectivePtr + LevelObjectiveDestroyObjects["targets"]);
                    return destroyedTargets != targets.Length ? destroyedTargets : -3;
            }

            // -2: no known progress for this type
            return -2;
        });

        return true;
    });

    vars.totalIGT = 0;
    current.lastNonZeroTime = 0; // lol
}

onStart
{
    vars.totalIGT = 0;
    current.objectiveProgress = -1;

    foreach (var objectivePtr in current.mainObjectives) {
        // var type = vars.ReadObjectiveType(objectivePtr);
        // vars.Log(type);
        // vars.ReadObjectiveProgress(objectivePtr);
    }
}

onSplit
{
    vars.totalIGT += 3600;
}

onReset
{
    current.lastNonZeroTime = 0;
}

update
{
    // objectives
    if (current.mainObjectives.Length > current.mainObjectiveIndex) {
        current.objectiveProgress = vars.ReadObjectiveProgress(current.mainObjectives[current.mainObjectiveIndex]);
    } else {
        current.objectiveProgress = -1;
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
        var currentLevelTimeSeconds = current.combatTime - current.regainedCombatTime;
        return TimeSpan.FromSeconds(baseTime + currentLevelTimeSeconds);
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
    if (settings["objectives"]) {
        if (current.mainObjectiveIndex == old.mainObjectiveIndex + 1) {
            vars.Log("Advanced main objective from " + old.mainObjectiveIndex + " to " + current.mainObjectiveIndex);
            return true;
        }

        if (current.objectiveProgress >= 0 && old.objectiveProgress >= 0
         && current.objectiveProgress > old.objectiveProgress
        ) {
            vars.Log("Advanced objective progress from " + old.objectiveProgress + " to " + current.objectiveProgress);
            return true;
        }
    }

    if (current.cutsceneID == 22 && old.destination == "Scenes/UI/Cutscenes/Cutscene") {
        return old.destination == "Scenes/UI/Cutscenes/Cutscene" && current.destination == "Scenes/UI/Menus/LevelSelect";
    } else {
        return (old.destination == "#01c_Special_Tutorial" && current.destination == "Scenes/UI/Menus/LevelSelect") || (old.levelState == 1 && current.levelState == 2);
    }
}

reset
{
    // disable for Mercy since it transitions out before the level finishes
    if (settings["ILs"] && current.level != 25 && old.sceneTransition != 0 && current.sceneTransition == 0) {
        return true;
    }
}