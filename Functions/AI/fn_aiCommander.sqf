/*
 * Function: FLO_fnc_aiCommander
 * Author: Azraeelian Angel
 * Description:
 * Creates an AI Commander that controls overall OPFOR operations.
 * Sets operation modes (Attack, Defend, Skirmish) and coordinates task forces.
 *
 * Arguments:
 * 0: Operation Mode <STRING> - "ATTACK", "DEFEND", "SKIRMISH" (Optional, default: "DEFEND")
 *
 * Return Value:
 * AI Commander HashMap Object <HASHMAP>
 *
 * Example:
 * ["ATTACK"] call FLO_fnc_aiCommander;
 */

params [["_operationMode", "DEFEND", [""]]];

// Log function start
["AI Commander", 3, format["Starting AI Commander with operation mode: %1", _operationMode]] call FLO_fnc_log;

// Initialize variables
private _lastCommanderUpdate = diag_tickTime;
private _commanderUpdateInterval = 300; // 5 minutes between strategy updates
private _threatThreshold = 0.6; // Threshold to switch to defensive mode if under heavy attack
private _currentThreatLevel = 0;
private _currentStrength = 1.0;

// Set up the Commander object using a HashMap
private _aiCommander = createHashMapObject [[
    ["_operationMode", _operationMode], // Current operation mode
    ["_threatLevel", _currentThreatLevel], // Current threat level
    ["_lastUpdate", _lastCommanderUpdate], // Last time the commander updated
    ["_outpostStatus", createHashMap], // Tracks outpost status
    ["_virtualGroups", createHashMap], // Tracks virtual groups under commander control
    ["_activeTasksforvirtualGroups", createHashMap], // Tracks active tasks for virtual groups

    // Methods
    ["_updateOperationMode", {
        params ["_newMode"];
        private _oldMode = _self get "_operationMode";
        
        if (_oldMode != _newMode) then {
            _self set ["_operationMode", _newMode];
            ["AI Commander", 3, format["Operation mode changed from %1 to %2", _oldMode, _newMode]] call FLO_fnc_log;
            
            // Adjust task force behavior based on new mode
            switch (_newMode) do {
                case "Offensive": {
                    _self set ["_currentStrength", 1.2]; // More offensive units
                };
                case "Defensive": {
                    _self set ["_currentStrength", 0.8]; // Focus on defense
                }; 
                // TODO: Add Additional Operation Modes Here
            };
        }
    }],
    
    ["_update", {
     
        private _currentTime = diag_tickTime;
        private _lastUpdate = _self get "_lastUpdate";
        private _updateInterval = _self get "_commanderUpdateInterval";
        
        // Only update periodically
        if (_currentTime - _lastUpdate < _updateInterval) exitWith {};
        
        // Assess current threat situation
        // private _threat = _self call ["_assessThreat", []];
        
        // Occasionally check for BLUFOR in the field even outside regular task force deployment
        // This ensures direct response to BLUFOR incursions
        if (_self get "_operationMode" != "DEFEND" && random 1 > 0.7) then {
            _self call ["_attackBluforInField", [_self get "_taskForceStrengthFactor"]];
        };
        
        // Update last update time
        _self set ["_lastUpdate", _currentTime];
    }],
    
    // Issue waypoints to virtual group
    ["_issueVirtualGroupWaypoints", {
        params ["_self", "_groupId", "_waypoints"];
        
        // Skip if virtualization system is not initialized
        if (isNil "FLO_virtualGroups") exitWith {
            ["AI Commander", 2, "Cannot issue virtual group waypoints - virtualization system not initialized"] call FLO_fnc_log;
            false
        };
        
        // Update the virtual group's waypoints
        [_groupId, _waypoints] call FLO_fnc_updateVirtualGroupWaypoints;
        
        // Add to tracked virtual groups
        (_self get "_virtualGroups") set [_groupId, diag_tickTime];
        
        ["AI Commander", 3, format["Issued waypoints to virtual group %1", _groupId]] call FLO_fnc_log;
        true
    }],
    
    // Assign task to a single virtual group near objective
    ["_assignVirtualGroupsTask", {
        params ["_self", "_objectiveId", "_taskType", "_targetPos"];
        
        // Skip if virtualization system is not initialized
        if (isNil "FLO_virtualGroups") exitWith {
            ["AI Commander", 2, "Cannot assign task to virtual group - virtualization system not initialized"] call FLO_fnc_log;
            false
        };
        
        // Find the objective position
        private _objectivePos = getMarkerPos _objectiveId;
        if (_objectivePos isEqualTo [0,0,0]) exitWith {
            ["AI Commander", 3, format["Invalid objective marker: %1", _objectiveId]] call FLO_fnc_log;
            false
        };
        
        // Find a single group that is within 5000m of the objective
        private _selectedGroup = "";
        private _minDistance = 999999;
        private _allGroups = FLO_virtualGroups get "_groups";
        
        {
            private _groupData = _y;
            private _groupPos = _groupData getOrDefault ["position", [0,0,0]];
            private _dist = _groupPos distance _objectivePos;
            
            // If the group is close to this objective and closer than any previously found
            if (_dist < 5000 && _dist < _minDistance) then {
                _selectedGroup = _x;
                _minDistance = _dist;
            };
        } forEach _allGroups;
        
        if (_selectedGroup == "") exitWith {
            ["AI Commander", 3, format["No virtual group found near objective %1", _objectiveId]] call FLO_fnc_log;
            false
        };
        
        // Define waypoint parameters based on task type
        private _wpBehavior = "AWARE";
        private _wpSpeed = "NORMAL";
        private _wpFormation = "COLUMN";
        private _wpCombatMode = "YELLOW";
        
        switch (_taskType) do {
            case "ATTACK": {
                _wpBehavior = "COMBAT";
                _wpSpeed = "FULL";
                _wpCombatMode = "RED";
            };
            case "DEFEND": {
                _wpBehavior = "COMBAT";
                _wpFormation = "LINE";
            };
            case "PATROL": {
                _wpBehavior = "AWARE";
                _wpFormation = "STAG COLUMN";
            };
            case "RECON": {
                _wpBehavior = "STEALTH";
                _wpSpeed = "LIMITED";
            };
        };
        
        // Create waypoint data
        private _waypoints = [[_targetPos, _taskType, _wpBehavior, _wpSpeed, _wpFormation, _wpCombatMode]];
        
        // Issue waypoint to the single selected group
        [_self, _selectedGroup, _waypoints] call (_self get "_issueVirtualGroupWaypoints");
        
        ["AI Commander", 3, format["Assigned %1 task to virtual group %2 near objective %3", _taskType, _selectedGroup, _objectiveId]] call FLO_fnc_log;
        true
    }]
]];

// Initialize Commander
_aiCommander set ["_commanderUpdateInterval", 300];
_aiCommander set ["_threatThreshold", 0.6];

// Start the commander loop
[_aiCommander] spawn {
    params ["_commander"];
    
    while {true} do {
        // Update the commander
        _commander call ["_update", []];
        
        // Sleep for a bit
        sleep 60;
    };
};

// Set the global AI Commander variable for other scripts to reference
FLO_AI_Commander = _aiCommander;
["AI Commander", 3, "Global AI Commander variable set"] call FLO_fnc_log;

// Return the commander object
_aiCommander 