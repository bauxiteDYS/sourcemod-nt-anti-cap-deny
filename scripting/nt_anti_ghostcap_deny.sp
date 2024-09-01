#pragma semicolon 1

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0.0"

#if(0)
// If defined, log some debug to LOG_PATH.
#define LOG_DEBUG
#define LOG_PATH "addons/sourcemod/logs/nt_anti_ghostcap_deny.log"
#endif

ConVar g_hCvar_UseSoundFx = null;
DataPack g_dpLateXpAwards = null;

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
}

public void OnMapEnd()
{
    // Clear any pending XP awards from the final round of a map.
    delete g_dpLateXpAwards;
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
    int award_xp_total = 0;
    int num_award_clients = 0;

    if (g_dpLateXpAwards != null) {
        delete g_dpLateXpAwards;
        LogError("Had dirty dp handle on AwardGhostCapXPToTeam; this should never happen.");
    }

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

        int client_prev_xp = GetPlayerXP(client);
        int next_xp = GetNextRankXP(client_prev_xp);
        int award_xp = next_xp - client_prev_xp;

        if (award_xp > 0) {
            if (g_dpLateXpAwards == null) {
                g_dpLateXpAwards = new DataPack();
            }

            g_dpLateXpAwards.WriteCell(GetClientUserId(client));
            g_dpLateXpAwards.WriteCell(client_prev_xp);

            award_xp_total += award_xp;
            ++num_award_clients;
        }
    }

    if (award_xp_total == 0) {
        if (g_dpLateXpAwards != null) {
            SetFailState("DataPack handle g_dpLateXpAwards is leaking");
        }
        return;
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

    Format(msg2, sizeof(msg2), "%s Awarding capture rank-up to %d player%s",
        g_szPluginTag, num_award_clients,
        (num_award_clients == 1 ? "." : "s.")); // -s plural postfix

    PrintToChatAll(msg1);
    PrintToChatAll(msg2);

    PrintToConsoleAll(msg1);
    PrintToConsoleAll(msg2);

#if defined(LOG_DEBUG)
    PrintToDebug(msg1);
    PrintToDebug(msg2);
#endif

    CreateTimer(1.0, Timer_AwardXP, _, TIMER_FLAG_NO_MAPCHANGE);
}

// Timer callback for awarding the "simulated ghost cap" XP to players,
// if any has been queued up.
public Action Timer_AwardXP(Handle timer)
{
    // This can happen if we change levels before this callback fires.
    if (g_dpLateXpAwards == null) {
        return Plugin_Stop;
    }

    // If we have an active round at this point, something external
    // (eg. admin command) has reset the match state before this
    // callback had a chance to fire.
    bool game_has_been_reset = IsGameRoundActive();

    // Actually award the XP only if there hasn't been a reset.
    if (!game_has_been_reset) {
        g_dpLateXpAwards.Reset();
        char award_message[sizeof(g_szPluginTag)-1 + 26 + 1];

// This addresses a bug in specific 1.8 branch releases
// where the function documentation didn't match implementation.
#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 8 && SOURCEMOD_V_REV < 5992 && SOURCEMOD_V_REV >= 5535
        while (g_dpLateXpAwards.IsReadable())
#else
        while (g_dpLateXpAwards.IsReadable(4))
#endif
        {
            int client = GetClientOfUserId(g_dpLateXpAwards.ReadCell());
            int client_prev_xp = g_dpLateXpAwards.ReadCell();

            if (client == 0 || !IsClientInGame(client)) {
                continue;
            }

            int current_xp = GetPlayerXP(client);
            int next_xp = GetNextRankXP(client_prev_xp);

            if (current_xp >= next_xp) {
                continue;
            }

            SetPlayerXP(client, next_xp);

            // Note: remember to update alloc size if you update the message format below!
            if (Format(award_message, sizeof(award_message), "%s You received %d extra XP.",
                g_szPluginTag,
                (next_xp - current_xp)
                ) == 0)
            {
                delete g_dpLateXpAwards;
                ThrowError("Failed to format award message");
            }
            PrintToChat(client, award_message);
            PrintToConsole(client, award_message);
#if defined(LOG_DEBUG)
            PrintToDebug("Award for %d: \"%s\"", client, award_message);
#endif
        }
    }

    delete g_dpLateXpAwards;

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
