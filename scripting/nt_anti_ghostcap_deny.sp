#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <neotokyo>

#define PLUGIN_VERSION "1.1.6"

// Remember to update PLUGIN_TAG_STRLEN if you change this tag.
#define PLUGIN_TAG "[ANTI CAP-DENY]"
// Length of the PLUGIN_TAG text.
#define PLUGIN_TAG_STRLEN 15

// Sound effect to use on the deny event.
// Can be turned on/off with a cvar.
#define SFX_NOTIFY "player/CPcaptured.wav"

#if(0)
// If defined, log some debug to LOG_PATH.
#define LOG_DEBUG
#define LOG_PATH "addons/sourcemod/logs/nt_anti_ghostcap_deny.log"
#endif

DataPack dp_lateXpAwards = null;

bool b_IsCurrentMapCtg = false;

ConVar g_hCvar_UseSoundFx = null;

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
    if (!PrecacheSound(SFX_NOTIFY)) {
        SetFailState("Failed to precache sound: \"%s\"", SFX_NOTIFY);
    }

    b_IsCurrentMapCtg = IsCurrentMapCtg();
}

public void OnMapEnd()
{
    // Clear any pending XP awards from the final round of a map.
    if (dp_lateXpAwards != null) {
        delete dp_lateXpAwards;
    }
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    // Don't need to do anything if this isn't a CTG map.
    if (!b_IsCurrentMapCtg) {
        return;
    }
    // Don't need to do anything if the round isn't live.
    else if (!IsGameRoundActive()) {
        return;
    }

    int victim_userid = event.GetInt("userid");
    int victim = GetClientOfUserId(victim_userid);

    if (victim == 0) {
        return;
    }

    int attacker_userid = event.GetInt("attacker");

    // Deaths by gravity etc. are attributed to userid 0 (world).
    bool was_suicide = (attacker_userid == 0 || attacker_userid == victim_userid);

    if (!was_suicide) {
        return;
    }

    int victim_team = GetClientTeam(victim);

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

bool IsGameRoundActive()
{
    // 1 means warmup, 2 means round is "live" in terms of gamerules
    return GameRules_GetProp("m_iGameState") == 2;
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

    // Not zero initializing this, because all NT weps have a classname
    // longer than this. We assume any non -1 ent index we get is always
    // a valid NT weapon ent index.
    decl String:wepName[9 + 1]; // "weapon_gh" + '\0' == strlen 10
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

    if (dp_lateXpAwards != null) {
        delete dp_lateXpAwards;
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
            if (dp_lateXpAwards == null) {
                dp_lateXpAwards = new DataPack();
            }

            dp_lateXpAwards.WriteCell(GetClientUserId(client));
            dp_lateXpAwards.WriteCell(client_prev_xp);

            award_xp_total += award_xp;
            ++num_award_clients;
        }
    }

    if (award_xp_total == 0) {
        if (dp_lateXpAwards != null) {
            SetFailState("DataPack handle dp_lateXpAwards is leaking");
        }
        return;
    }

    if (g_hCvar_UseSoundFx.BoolValue) {
        EmitSoundToAll(SFX_NOTIFY);
    }

    decl String:msg1[PLUGIN_TAG_STRLEN + 100 + 1];
    decl String:msg2[PLUGIN_TAG_STRLEN + 40 + 1];

    Format(msg1, sizeof(msg1),
        "%s Last player of %s suicided vs. ghost carrier; awarding capture to team %s.",
        PLUGIN_TAG,
        (team == TEAM_JINRAI ? "NSF" : "Jinrai"),
        (team == TEAM_JINRAI ? "Jinrai" : "NSF"));

    Format(msg2, sizeof(msg2), "%s Awarding capture rank-up to %d player%s",
        PLUGIN_TAG, num_award_clients,
        (num_award_clients == 1 ? "." : "s.")); // -s plural postfix

    PrintToChatAll(msg1);
    PrintToChatAll(msg2);

    PrintToConsoleAll(msg1);
    PrintToConsoleAll(msg2);

#if defined(LOG_DEBUG)
    PrintToDebug(msg1);
    PrintToDebug(msg2);
#endif

    CreateTimer(1.0, Timer_AwardXP);
}

// Timer callback for awarding the "simulated ghost cap" XP to players,
// if any has been queued up.
public Action Timer_AwardXP(Handle timer)
{
    // This can happen if we change levels before this callback fires.
    if (dp_lateXpAwards == null) {
        return Plugin_Stop;
    }

    // If we have an active round at this point, something external
    // (eg. admin command) has reset the match state before this
    // callback had a chance to fire.
    bool game_has_been_reset = IsGameRoundActive();

    // Actually award the XP only if there hasn't been a reset.
    if (!game_has_been_reset) {
        dp_lateXpAwards.Reset();
        decl String:award_message[PLUGIN_TAG_STRLEN + 26 + 1];

// This addresses a bug in specific 1.8 branch releases
// where the function documentation didn't match implementation.
#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 8 && SOURCEMOD_V_REV < 5992 && SOURCEMOD_V_REV >= 5535
        while (dp_lateXpAwards.IsReadable())
#else
        while (dp_lateXpAwards.IsReadable(4))
#endif
        {
            int client = GetClientOfUserId(dp_lateXpAwards.ReadCell());
            int client_prev_xp = dp_lateXpAwards.ReadCell();

            if (client == 0) {
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
                PLUGIN_TAG,
                (next_xp - current_xp)
                ) == 0)
            {
                delete dp_lateXpAwards;
                ThrowError("Failed to format award message");
            }
            PrintToChat(client, award_message);
            PrintToConsole(client, award_message);
#if defined(LOG_DEBUG)
            PrintToDebug("Award for %d: \"%s\"", client, award_message);
#endif
        }
    }

    delete dp_lateXpAwards;

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
    decl String:entName[15 + 1]; // strlen "neo_game_config" + '\0' = 16
    for (int ent = MaxClients + 1; ent <= GetMaxEntities(); ++ent) {
        if (!IsValidEntity(ent)) {
            continue;
        }
        if (!GetEntityClassname(ent, entName, sizeof(entName))) {
            continue;
        }
        if (StrEqual(entName, "neo_game_config")) {
            // m_GameType --> 0 : "TDM", 1 : "CTG", 2 : "VIP"
            bool is_ctg = (GetEntProp(ent, Prop_Send, "m_GameType") == 1);
            return is_ctg;
        }
    }
    return false;
}

#if defined(LOG_DEBUG)
void PrintToDebug(const char [] msg, any ...)
{
    decl String:buffer[256];
    int bytes = VFormat(buffer, sizeof(buffer), msg, 2);
    if (bytes <= 0) {
        ThrowError("VFormat failed on: %s", msg);
    }

    LogToFile(LOG_PATH, buffer);
}
#endif

// Backported from SourceMod/SourcePawn SDK for SM < 1.9 compatibility.
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
