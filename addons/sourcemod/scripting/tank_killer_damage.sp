#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdkhooks>
#include <colors>


public Plugin myinfo =
{
	name = 			"TankKillerDamage",
	author = 		"TouchMe",
	description = 	"Displays in chat the damage done to the tank",
	version = 		"build0001",
	url = 			"https://github.com/TouchMe-Inc/l4d2_tank_killer_damage"
}


#define TRANSLATIONS            "tank_killer_damage.phrases"


/*
 * Infected Class.
 */
#define CLASS_TANK              8

/*
 * Team.
 */
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3


bool g_bRoundIsLive = false;

int
	g_iKillerDamage[MAXPLAYERS + 1] = {0, ...}, /*< Damage done to Witch, client tracking */
	g_iTotalDamage = 0, /*< Total Damage done to Witch. */
	g_iLastHealth = 0
;


/**
 * Called before OnPluginStart.
 *
 * @param myself      Handle to the plugin
 * @param bLate       Whether or not the plugin was loaded "late" (after map load)
 * @param sErr        Error message buffer in case load failed
 * @param iErrLen     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure
 */
public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] sErr, int iErrLen)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
 * Called when the map starts loading.
 */
public void OnMapStart() {
	g_bRoundIsLive = false;
}

public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	// Events.
	HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerKilled, EventHookMode_Post);
}

/**
 * Round start event.
 */
void Event_PlayerLeftStartArea(Event event, const char[] sName, bool bDontBroadcast)
{
	g_bRoundIsLive = true;

	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		g_iKillerDamage[iClient] = 0;
	}

	g_iTotalDamage = 0;
}

/**
 * Round end event.
 */
void Event_RoundEnd(Event event, const char[] sName, bool bDontBroadcast)
{
	if (!g_bRoundIsLive)
	{
	    return;
	}

	g_bRoundIsLive = false;

	int iTank = FindTank();

	if (iTank == -1) {
		return;
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| !IsClientSurvivor(iPlayer)
		|| !g_iKillerDamage[iPlayer]) {
			continue;
		}

		iPlayers[iTotalPlayers ++] = iPlayer;
	}

	if (!iTotalPlayers) {
		return;
	}

	SortCustom1D(iPlayers, iTotalPlayers, SortDamage);

	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
			continue;
		}

		PrintToChatDamage(iClient, iPlayers, iTotalPlayers);
	}
}

void Event_PlayerHurt(Event event, const char[] sName, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(iVictim)
	|| !IsClientInGame(iVictim)
	|| !IsClientInfected(iVictim)
	|| !IsClientTank(iVictim)
	|| IsClientIncapacitated(iVictim)) {
		return;
	}

	int iRemainingHealth = GetEventInt(event, "health");

	if (iRemainingHealth <= 0) {
		return;
	}

	g_iLastHealth = iRemainingHealth;

	int iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!IsValidClient(iAttacker)
	|| !IsClientInGame(iAttacker)
	|| !IsClientSurvivor(iAttacker)) {
		return;
	}

	int iDamage = GetEventInt(event, "dmg_health");

	g_iKillerDamage[iAttacker] += iDamage;
	g_iTotalDamage += iDamage;
}

void Event_PlayerKilled(Event event, const char[] sName, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(iVictim) || !IsClientInGame(iVictim)
	|| !IsClientInfected(iVictim) || !IsClientTank(iVictim)) {
		return;
	}

	int iAttacker = GetClientOfUserId(GetEventInt(event, "userid"));

	if (IsValidClient(iAttacker) && IsClientInGame(iAttacker)
	&& IsClientSurvivor(iAttacker) && g_iLastHealth > 0)
	{
		g_iKillerDamage[iAttacker] += g_iLastHealth;
		g_iTotalDamage += g_iLastHealth;

		g_iLastHealth = 0;
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| !IsClientSurvivor(iPlayer)
		|| !g_iKillerDamage[iPlayer]) {
			continue;
		}

		iPlayers[iTotalPlayers ++] = iPlayer;
	}

	if (!iTotalPlayers) {
		return;
	}

	SortCustom1D(iPlayers, iTotalPlayers, SortDamage);

	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
			continue;
		}

		PrintToChatDamage(iClient, iPlayers, iTotalPlayers);
	}
}

void PrintToChatDamage(int iClient, const int[] iPlayers, int iTotalPlayers)
{
	CPrintToChat(iClient, "%T%T", "BRACKET_START", iClient, "TAG", iClient);

	char sName[MAX_NAME_LENGTH];

	for (int iItem = 0; iItem < iTotalPlayers; iItem ++)
	{
		int iPlayer = iPlayers[iItem];
		float fDamageProcent = 0.0;

		if (g_iTotalDamage > 0.0) {
			fDamageProcent = 100.0 * float(g_iKillerDamage[iPlayer]) / float(g_iTotalDamage);
		}

		GetClientNameFixed(iPlayer, sName, sizeof(sName), 18);

		CPrintToChat(iClient, "%T%T",
			(iItem + 1) == iTotalPlayers ? "BRACKET_END" : "BRACKET_MIDDLE", iClient,
			"SURVIVOR_KILLER", iClient,
			sName,
			g_iKillerDamage[iPlayer],
			fDamageProcent
		);
	}
}

bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients);
}

int SortDamage(int elem1, int elem2, const int[] array, Handle hndl)
{
	int iDamage1 = g_iKillerDamage[elem1];
	int iDamage2 = g_iKillerDamage[elem2];

	if (iDamage1 > iDamage2) {
		return -1;
	} else if (iDamage1 < iDamage2) {
		return 1;
	}

	return 0;
}

/**
 * Infected team player?
 */
bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

/**
 * Gets the client L4D1/L4D2 zombie class id.
 *
 * @param client     Client index.
 * @return L4D1      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=WITCH, 5=TANK, 6=NOT INFECTED
 * @return L4D2      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=SPITTER, 5=JOCKEY, 6=CHARGER, 7=WITCH, 8=TANK, 9=NOT INFECTED
 */
int GetClientClass(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

bool IsClientTank(int iClient) {
	return (GetClientClass(iClient) == CLASS_TANK);
}

bool IsClientIncapacitated(int iClient) {
	return view_as<bool>(GetEntProp(iClient, Prop_Send, "m_isIncapacitated"));
}

int FindTank()
{
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| !IsClientInfected(iPlayer)
		|| !IsPlayerAlive(iPlayer)
		|| !IsClientTank(iPlayer)) {
			continue;
		}

		return iPlayer;
	}

	return -1;
}

/**
 *
 */
void GetClientNameFixed(int iClient, char[] name, int length, int iMaxSize)
{
	GetClientName(iClient, name, length);

	if (strlen(name) > iMaxSize)
	{
		name[iMaxSize - 3] = name[iMaxSize - 2] = name[iMaxSize - 1] = '.';
		name[iMaxSize] = '\0';
	}
}
