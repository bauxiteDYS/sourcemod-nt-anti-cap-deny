#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <neotokyo>

#define PLUGIN_VERSION "0.9"

// Remember to update PLUGIN_TAG_STRLEN if you change this tag.
#define PLUGIN_TAG "[ANTI CAP-DENY]"
// Length of the PLUGIN_TAG text.
#define PLUGIN_TAG_STRLEN 15

#define LOG_DEBUG

DataPack dp_lateXpAwards = null;

bool b_IsCurrentMapCtg = false;

ConVar g_cvarSimulate = null;

public Plugin myinfo = {
	name		= "NEOTOKYO° Anti Ghost Cap Deny",
	author	= "Rain",
	description = "If the last living player of a team suicides (or gets \
posthumously teamkilled) to prevent a ghost cap, treat it as if the ghost cap happened.",
	version	 = PLUGIN_VERSION,
	url		 = "https://github.com/Rainyan/sourcemod-nt-anti-cap-deny"
};

public void OnPluginStart()
{
	if (!HookEventEx("player_death", OnPlayerDeath, EventHookMode_Pre)) {
		SetFailState("Failed to hook event player_death");
	}

	CreateConVar("sm_nt_anti_ghost_cap_deny_version", PLUGIN_VERSION,
		"NEOTOKYO° Anti Ghost Cap Deny plugin version.", FCVAR_DONTRECORD);
	
	g_cvarSimulate = CreateConVar("sm_nt_anti_ghost_cap_deny_dryrun", "0",
		"Only simulate the behaviour for debug, without actually changing XP.");
}

public void OnMapStart()
{
	b_IsCurrentMapCtg = IsCurrentMapCtg();
}

public void OnMapEnd()
{
	// Clear any pending XP awards from the final round of a map.
	if (dp_lateXpAwards != null) {
		delete dp_lateXpAwards;
		dp_lateXpAwards = null;
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

	// We don't have guarantee of having processed the victim living status state
	// change yet, so ignoring victim from this team count.
	if (GetNumLivingPlayersInTeam(victim_team, victim) != 0) {
		// This was not the last player of this team; can't be a ghost cap deny.
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
		dp_lateXpAwards = null;
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

		if (award_xp != 0) {
			if (award_xp < 0) {
				if (dp_lateXpAwards) {
					delete dp_lateXpAwards;
					dp_lateXpAwards = null;
				}
				ThrowError("Negative award XP");
			}

			if (dp_lateXpAwards == null) {
				dp_lateXpAwards = new DataPack();
			}

			dp_lateXpAwards.WriteCell(GetClientUserId(client));
			dp_lateXpAwards.WriteCell(client_prev_xp);

			award_xp_total += award_xp;
			++num_award_clients;
		}
	}

	if (award_xp_total != 0) {
		decl String:msg1[PLUGIN_TAG_STRLEN + 100 + 1];
		decl String:msg2[PLUGIN_TAG_STRLEN + 35 + 1];
		
		Format(msg1, sizeof(msg1),
			"%s Last player of %s suicided vs. ghost carrier; awarding capture to team %s.",
			PLUGIN_TAG,
			(team == TEAM_JINRAI ? "NSF" : "Jinrai"),
			(team == TEAM_JINRAI ? "Jinrai" : "NSF"));
		
		Format(msg2, sizeof(msg2), "%s Awarded %d XP total to %d player%s",
			PLUGIN_TAG, award_xp_total, num_award_clients,
			(num_award_clients == 1 ? "." : "s.")); // "player/players" plural

		if (g_cvarSimulate.BoolValue) {
			for (int i = 1; i <= MaxClients; ++i) {
				if (IsAdmin(i)) {
					PrintToConsole(i, "[ADMIN DEBUG] : %s\n%s", msg1, msg2);
				}
			}
		} else {
			PrintToChatAll(msg1);
			PrintToChatAll(msg2);

			PrintToConsoleAll(msg1);
			PrintToConsoleAll(msg2);
		}
		
#if defined(LOG_DEBUG)
		PrintToDebug(msg1);
		PrintToDebug(msg2);
#endif

		CreateTimer(1.0, Timer_AwardXP);
	}
	else if (dp_lateXpAwards != null) {
		SetFailState("DataPack handle dp_lateXpAwards is leaking");
	}
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
		decl String:award_message[PLUGIN_TAG_STRLEN + 20 + 1];
		while (dp_lateXpAwards.IsReadable()) {
			int client = GetClientOfUserId(dp_lateXpAwards.ReadCell());
			int client_prev_xp = dp_lateXpAwards.ReadCell();

			if (client == 0) {
				continue;
			}
			
			// Subtract one to account for the default round win +1 XP
			// that we don't want to award on top of the capture award.
			int award_amount = (GetNextRankXP(client_prev_xp) - client_prev_xp) - 1;
			
			if (award_amount <= 0) {
				continue;
			}
			
			if (!IsValidClient(client)) {
				// This should never happen since we do GetClientOfUserId,
				// but adding a sanity check for now to catch any weirdness.
				LogError("Got invalid client %d at Timer_AwardXP!", client);
				continue;
			}

			if (!g_cvarSimulate.BoolValue) {
				SetPlayerXP(client, GetPlayerXP(client) + award_amount);

				// Note: remember to update alloc size if you update the message format below!
				if (Format(award_message, sizeof(award_message), "%s You received %d XP.",
					PLUGIN_TAG,
					(award_amount + 1) // +1 because we're offsetting the award. See var assignment for comment.
					) == 0)
				{
					delete dp_lateXpAwards;
					dp_lateXpAwards = null;
					ThrowError("Failed to format award message");
				}
				PrintToChat(client, award_message);
				PrintToConsole(client, award_message);
#if defined(LOG_DEBUG)
				PrintToDebug("Award for %d: %s", client, award_message);
#endif
			}
		}
	}

	delete dp_lateXpAwards;
	dp_lateXpAwards = null;

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

bool IsAdmin(int client)
{
	return (IsClientConnected(client) && GetAdminFlag(GetUserAdmin(client), Admin_Generic));
}

#if defined(LOG_DEBUG)
void PrintToDebug(const char [] msg, any ...)
{
	decl String:buffer[512];
	int bytes = VFormat(buffer, sizeof(buffer), msg, 2);
	if (bytes <= 0) {
		ThrowError("VFormat failed on: %s", msg);
	}

	LogToFile("addons/sourcemod/logs/nt_anti_ghostcap_deny.log", buffer);
}
#endif
