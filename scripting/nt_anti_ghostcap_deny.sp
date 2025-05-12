#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.1.0"

#if(0)
// If defined, log some debug to LOG_PATH.
#define LOG_DEBUG
#define LOG_PATH "addons/sourcemod/logs/nt_anti_ghostcap_deny.log"
#endif

int g_iNewXP[NEO_MAXPLAYERS + 1];
int g_iFlatXP;
bool g_bRewardDead;
ConVar g_hCvar_GhostReward = null;
ConVar g_hCvar_GhostRewardDead = null;
ConVar g_hCvar_UseSoundFx = null;

char g_szPluginTag[] = "[ANTI CAP-DENY]";
// Sound effect to use on the deny event. Can be turned on/off with a cvar.
char g_szSfxNotify[] = "player/CPcaptured.wav";

public Plugin myinfo = {
    name        = "NEOTOKYO° Anti Ghost Cap Deny",
    author      = "Rain",
    description = "If the last living player of a team suicides (or gets \
posthumously teamkilled) to prevent a ghost cap, treat it as if the ghost \
cap happened.",
    version     = PLUGIN_VERSION,
    url         = "https://github.com/Rainyan/sourcemod-nt-anti-cap-deny"
};

public void OnPluginStart()
{
    if (!HookEventEx("player_death", OnPlayerDeath, EventHookMode_Pre)) {
        SetFailState("Failed to hook event player_death");
    }

    CreateConVar("sm_nt_anti_ghost_cap_deny_version", PLUGIN_VERSION,
        "NEOTOKYO° Anti Ghost Cap Deny plugin version.", FCVAR_DONTRECORD);

    g_hCvar_UseSoundFx = CreateConVar("sm_nt_anti_ghost_cap_deny_sfx", "1",
        "Whether to play sound FX on the cap deny event.");
}

public void OnMapStart()
{
    if (!IsCurrentMapCtg()) {
        UnloadSelf();
        return;
    }

    if (!PrecacheSound(g_szSfxNotify)) {
        SetFailState("Failed to precache sound: \"%s\"", g_szSfxNotify);
    }
    
    // if nt_wincond is late-loaded or unloaded then this plugin will not function properly until next map

    g_hCvar_GhostReward = FindConVar("sm_nt_wincond_ghost_reward");
    g_hCvar_GhostRewardDead = FindConVar("sm_nt_wincond_ghost_reward_dead");

    if(g_hCvar_GhostReward != null && g_hCvar_GhostRewardDead != null) {
        g_iFlatXP = g_hCvar_GhostReward.IntValue;
        g_bRewardDead = g_hCvar_GhostRewardDead.BoolValue;
    }
    else {
        g_iFlatXP = 0;
        g_bRewardDead = false;
    }
}

public void OnClientDisconnect(int client)
{
    int userid = GetClientUserId(client);
    // Treat player disconnect the same as suicide,
    // because the player effectively removed themselves from the round.
    CheckForAntiCap(userid, userid);
}

void CheckForAntiCap(int victim_userid, int attacker_userid)
{
    // Don't need to do anything if the round isn't live.
    if (!IsGameRoundActive()) {
        return;
    }

    int victim = GetClientOfUserId(victim_userid);
    if (victim == 0 || !IsClientInGame(victim)) {
        return;
    }

    // Deaths by gravity etc. are attributed to userid 0 (world).
    bool was_suicide = (attacker_userid == 0 || attacker_userid == victim_userid);
    if (!was_suicide) {
        return;
    }

    int victim_team = GetClientTeam(victim);
    // This can happen if we're handling a non-playerteam disconnect.
    if (victim_team != TEAM_JINRAI && victim_team != TEAM_NSF) {
        return;
    }

    // We don't have guarantee of having processed the victim living status
    // state change yet, so ignoring victim from this team count.
    if (GetNumLivingPlayersInTeam(victim_team, victim) != 0) {
        // This wasn't the last player of this team; can't be a ghost cap deny.
        return;
    }

    int opposing_team = GetOpposingTeam(victim_team);
    if (!IsTeamGhosting(opposing_team)) {
        return;
    }

    AwardGhostCapXPToTeam(opposing_team);
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    CheckForAntiCap(event.GetInt("userid"), event.GetInt("attacker"));
}

bool IsGameRoundActive()
{
    return GameRules_GetProp("m_iGameState") == GAMESTATE_ROUND_ACTIVE;
}

int GetNumLivingPlayersInTeam(int team, int ignore_client = 0)
{
    int num_living = 0;
    for (int client = 1; client <= MaxClients; ++client) {
        if (client == ignore_client) {
            continue;
        }
        if (!IsValidClient(client)) {
            continue;
        }
        if (GetClientTeam(client) != team) {
            continue;
        }
        if (!IsPlayerAlive(client)) {
            continue;
        }
        ++num_living;
    }
    return num_living;
}

bool IsTeamGhosting(int team)
{
    for (int client = 1; client <= MaxClients; ++client) {
        if (!IsValidClient(client)) {
            continue;
        }
        if (GetClientTeam(client) != team) {
            continue;
        }
        if (!IsPlayerAlive(client)) {
            continue;
        }
        if (!IsWeaponGhost(GetPlayerWeaponSlot(client, SLOT_PRIMARY))) {
            continue;
        }
        return true;
    }
    return false;
}

// Assumes weapon input to always be a valid NT wep index,
// or -1 for invalid weapon.
bool IsWeaponGhost(int weapon)
{
    if (weapon == -1) {
        return false;
    }

    // "weapon_gh" + '\0' == strlen 10.
    // We assume any non -1 ent index we get is always
    // a valid NT weapon ent index.
    char wepName[9 + 1];
    if (!GetEntityClassname(weapon, wepName, sizeof(wepName))) {
        return false;
    }

    // weapon_gHost -- only weapon with letter H on 8th position of its name.
    return wepName[8] == 'h';
}

void AwardGhostCapXPToTeam(int team)
{
    int num_award_clients = 0;
    char award_message[sizeof(g_szPluginTag)-1 + 26 + 1];

    for (int client = 1; client <= MaxClients; ++client) {
        if (!IsValidClient(client)) {
            continue;
        }
        if (GetClientTeam(client) != team) {
            continue;
        }
        if (!g_bRewardDead && !IsPlayerAlive(client)) {
            continue;
        }

        int client_prev_xp = GetPlayerXP(client);
        int next_xp;
        int award_xp;

        if(g_iFlatXP > 0) {
            next_xp = g_iFlatXP + client_prev_xp;
            award_xp = g_iFlatXP;
        }
        else {
            next_xp = GetNextRankXP(client_prev_xp);
            award_xp = next_xp - client_prev_xp;
        }

        if (award_xp <= 0) {
            continue;
        }
            
        ++num_award_clients;

        g_iNewXP[client] = next_xp;

        CreateTimer(0.3, Timer_AwardXP, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

        // Note: remember to update alloc size if you update the message format below!
        if (Format(award_message, sizeof(award_message), "%s You received %d XP.", g_szPluginTag, award_xp) == 0) {
            ThrowError("Failed to format award message");
        }
        PrintToChat(client, award_message);
        PrintToConsole(client, award_message);
#if defined(LOG_DEBUG)
        PrintToDebug("Award for %d: \"%s\"", client, award_message);
#endif

    }

    if (g_hCvar_UseSoundFx.BoolValue) {
        EmitSoundToAll(g_szSfxNotify);
    }

    char msg1[sizeof(g_szPluginTag)-1 + 100 + 1];
    char msg2[sizeof(g_szPluginTag)-1 + 40 + 1];

    Format(msg1, sizeof(msg1),
        "%s Last player of %s suicided vs. ghost carrier; awarding capture to team %s.",
        g_szPluginTag,
        (team == TEAM_JINRAI ? "NSF" : "Jinrai"),
        (team == TEAM_JINRAI ? "Jinrai" : "NSF"));

    Format(msg2, sizeof(msg2), "%s Awarding capture %s to %d player%s",
        g_szPluginTag, g_iFlatXP == 0 ? "rank-up" : "points", num_award_clients,
        (num_award_clients == 1 ? "." : "s.")); // -s plural postfix

    PrintToChatAll(msg1);
    PrintToChatAll(msg2);

    PrintToConsoleAll(msg1);
    PrintToConsoleAll(msg2);
    
#if defined(LOG_DEBUG)
    PrintToDebug(msg1);
    PrintToDebug(msg2);
#endif
}

public Action Timer_AwardXP(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    
    if(client <= 0 || !IsValidClient(client)) {
        return Plugin_Stop;
    }
    
    SetPlayerXP(client, g_iNewXP[client]);
    
    return Plugin_Stop;
}

// Takes in an amount of XP, and returns the XP value
// of the next rank, or returns the input XP if it is
// already >= the lieutenant XP of 20.
int GetNextRankXP(const int xp)
{
    if (xp < 0) { return 0; }
    if (xp < 4) { return 4; }
    if (xp < 10) { return 10; }
    if (xp < 20) { return 20; }
    return xp;
}

int GetOpposingTeam(int team)
{
    return team == TEAM_JINRAI ? TEAM_NSF : TEAM_JINRAI;
}

bool IsCurrentMapCtg()
{
    int ent = FindEntityByClassname(-1, "neo_game_config");
    if (!IsValidEntity(ent)) {
        return false;
    }
#define GAMETYPE_CTG 1
    return GetEntProp(ent, Prop_Send, "m_GameType") == GAMETYPE_CTG;
}

#if defined(LOG_DEBUG)
void PrintToDebug(const char [] msg, any ...)
{
    char buffer[256];
    int bytes = VFormat(buffer, sizeof(buffer), msg, 2);
    if (bytes <= 0) {
        ThrowError("VFormat failed on: %s", msg);
    }

    LogToFile(LOG_PATH, buffer);
}
#endif

void UnloadSelf()
{
    char filename[PLATFORM_MAX_PATH];
    GetPluginFilename(INVALID_HANDLE, filename, sizeof(filename));
    ServerCommand("sm plugins unload \"%s\"", filename);
}

// Backported from SourceMod/SourcePawn SDK for SM < 1.9 compatibility.
// Used here under GPLv3 license: https://www.sourcemod.net/license.php
// SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR < 9
/**
 * Sends a message to every client's console.
 *
 * @param format        Formatting rules.
 * @param ...           Variable number of format parameters.
 */
stock void PrintToConsoleAll(const char[] format, any ...)
{
    char buffer[254];

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SetGlobalTransTarget(i);
            VFormat(buffer, sizeof(buffer), format, 2);
            PrintToConsole(i, "%s", buffer);
        }
    }
}
#endif
