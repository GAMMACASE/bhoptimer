/*
 * shavit's Timer - Miscellaneous
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#define USES_STYLE_NAMES
#define USES_STYLE_PROPERTIES
#include <shavit>

#undef REQUIRE_EXTENSIONS
#include <dhooks>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// game specific
ServerGame gSG_Type = Game_Unknown;
int gI_Ammo = -1;

char gS_RadioCommands[][] = {"coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire", "go", "fallback", "sticktog",
	"getinpos", "stormfront", "report", "roger", "enemyspot", "needbackup", "sectorclear", "inposition", "reportingin",
	"getout", "negative", "enemydown", "compliment", "thanks", "cheer"};

// cache
bool gB_Hide[MAXPLAYERS+1];
bool gB_Late = false;
int gF_LastFlags[MAXPLAYERS+1];

// cvars
ConVar gCV_GodMode = null;
ConVar gCV_PreSpeed = null;
ConVar gCV_HideTeamChanges = null;
ConVar gCV_RespawnOnTeam = null;
ConVar gCV_RespawnOnRestart = null;
ConVar gCV_StartOnSpawn = null;
ConVar gCV_PrespeedLimit = null;
ConVar gCV_HideRadar = null;
ConVar gCV_TeleportCommands = null;
ConVar gCV_NoWeaponDrops = null;
ConVar gCV_NoBlock = null;
ConVar gCV_AutoRespawn = null;
ConVar gCV_CreateSpawnPoints = null;
ConVar gCV_DisableRadio = null;
ConVar gCV_Scoreboard = null;
ConVar gCV_WeaponCommands = null;

// dhooks
Handle gH_GetMaxPlayerSpeed = null;

// modules
bool gB_Rankings = false;

public Plugin myinfo =
{
	name = "[shavit] Miscellaneous",
	author = "shavit",
	description = "Miscellaneous stuff for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gB_Rankings = LibraryExists("shavit-rankings");
}

public void OnPluginStart()
{
	// cache
	gSG_Type = Shavit_GetGameType();

	// spectator list
	RegConsoleCmd("sm_specs", Command_Specs, "Show a list of spectators.");
	RegConsoleCmd("sm_spectators", Command_Specs, "Show a list of spectators.");

	// spec
	RegConsoleCmd("sm_spec", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spectate [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");

	// tpto
	RegConsoleCmd("sm_tpto", Command_Teleport, "Teleport to another player. Usage: sm_tpto [target]");
	RegConsoleCmd("sm_goto", Command_Teleport, "Teleport to another player. Usage: sm_goto [target]");

	// weapons
	RegConsoleCmd("sm_usp", Command_Weapon, "Spawn a USP.");
	RegConsoleCmd("sm_glock", Command_Weapon, "Spawn a Glock.");
	RegConsoleCmd("sm_knife", Command_Weapon, "Spawn a knife.");

	gI_Ammo = FindSendPropInfo("CCSPlayer", "m_iAmmo");

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");

	// hook radio commands instead of a global listener
	for(int i = 0; i < sizeof(gS_RadioCommands); i++)
	{
		AddCommandListener(Command_Radio, gS_RadioCommands[i]);
	}

	// crons
	CreateTimer(1.0, Timer_Scoreboard, INVALID_HANDLE, TIMER_REPEAT);
	CreateTimer(600.0, Timer_Message, INVALID_HANDLE, TIMER_REPEAT);

	// hooks
	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_team", Player_Notifications, EventHookMode_Pre);
	HookEvent("player_death", Player_Notifications, EventHookMode_Pre);
	HookEvent("weapon_fire", Weapon_Fire);

	// phrases
	LoadTranslations("common.phrases");

	// cvars and stuff
	gCV_GodMode = CreateConVar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", 0, true, 0.0, true, 3.0);
	gCV_PreSpeed = CreateConVar("shavit_misc_prespeed", "3", "Stop prespeed in startzone?\n0 - Disabled\n1 - Limit 280 speed.\n2 - Block bhopping in startzone\n3 - Limit 280 speed and block bhopping in startzone.", 0, true, 0.0, true, 3.0);
	gCV_HideTeamChanges = CreateConVar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = CreateConVar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = CreateConVar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if he uses the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = CreateConVar("shavit_misc_startonspawn", "1", "Restart the timer for a player after he spawns?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PrespeedLimit = CreateConVar("shavit_misc_prespeedlimit", "280.00", "Prespeed limitation in startzone.", 0, true, 10.0, false);
	gCV_HideRadar = CreateConVar("shavit_misc_hideradar", "1", "Should the plugin hide the in-game radar?", 0, true, 0.0, true, 1.0);
	gCV_TeleportCommands = CreateConVar("shavit_misc_tpcmds", "1", "Enable teleport-related commands? (sm_goto/sm_tpto)\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoWeaponDrops = CreateConVar("shavit_misc_noweapondrops", "1", "Remove every dropped weapon.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlock = CreateConVar("shavit_misc_noblock", "1", "Disable player collision?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = CreateConVar("shavit_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_CreateSpawnPoints = CreateConVar("shavit_misc_createspawnpoints", "32", "Amount of spawn points to add for each team.\n0 - Disabled", 0, true, 0.0, true, 32.0);
	gCV_DisableRadio = CreateConVar("shavit_misc_disableradio", "0", "Block radio commands.\n0 - Disabled (radio commands work)\n1 - Enabled (radio commands are blocked)", 0, true, 0.0, true, 1.0);
	gCV_Scoreboard = CreateConVar("shavit_misc_scoreboard", "1", "Manipulate scoreboard so score is -{time} and deaths are {rank})?\nDeaths part requires shavit-rankings.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_WeaponCommands = CreateConVar("shavit_misc_weaponcommands", "2", "Enable sm_usp, sm_glock and sm_knife?\n0 - Disabled\n1 - Enabled\n2 - Also give infinite reserved ammo.", 0, true, 0.0, true, 2.0);

	AutoExecConfig();

	if(LibraryExists("dhooks"))
	{
		Handle hGameData = LoadGameConfigFile("shavit.games");

		if(hGameData != null)
		{
			int iOffset = GameConfGetOffset(hGameData, "GetMaxPlayerSpeed");
			gH_GetMaxPlayerSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, DHook_GetMaxPlayerSpeed);
		}

		delete hGameData;
	}

	// late load
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnMapStart()
{
	if(gCV_CreateSpawnPoints.BoolValue)
	{
		int iEntity = -1;
		float fOrigin[3];

		if((iEntity = FindEntityByClassname(-1, "info_player_terrorist")) != -1)
		{
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
		}

		else if((iEntity = FindEntityByClassname(-1, "info_player_counterterrorist")) != -1)
		{
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
		}

		if(iEntity != -1)
		{
			for(int i = 1; i <= gCV_CreateSpawnPoints.IntValue; i++)
			{
				for(int iTeam = 1; iTeam <= 2; iTeam++)
				{
					int iSpawnPoint = CreateEntityByName(iTeam == 1? "info_player_terrorist":"info_player_counterterrorist");

					if(DispatchSpawn(iSpawnPoint))
					{
						TeleportEntity(iSpawnPoint, fOrigin, view_as<float>({0.0, 0.0, 0.0}), NULL_VECTOR);
					}
				}
			}
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	char[] arg1 = new char[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);

	bool bRespawn = false;

	switch(iTeam)
	{
		case CS_TEAM_T:
		{
			// if T spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				bRespawn = true;

				CS_SwitchTeam(client, CS_TEAM_T);
			}
		}

		case CS_TEAM_CT:
		{
			// if CT spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_counterterrorist") != -1)
			{
				bRespawn = true;

				CS_SwitchTeam(client, CS_TEAM_CT);
			}
		}

		// if they chose to spectate, i'll force them to join the spectators
		case CS_TEAM_SPECTATOR:
		{
			CS_SwitchTeam(client, CS_TEAM_SPECTATOR);
		}

		default:
		{
			bRespawn = true;

			CS_SwitchTeam(client, GetRandomInt(2, 3));
		}
	}

	if(gCV_RespawnOnTeam.BoolValue && bRespawn)
	{
		CS_RespawnPlayer(client);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Command_Radio(int client, const char[] command, int args)
{
	if(gCV_DisableRadio.BoolValue)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public MRESReturn DHook_GetMaxPlayerSpeed(int pThis, Handle hReturn)
{
	if(IsValidClient(pThis, true))
	{
		DHookSetReturn(hReturn, 250.000);

		return MRES_Override;
	}

	return MRES_Ignored;
}

public Action Timer_Scoreboard(Handle Timer)
{
	if(!gCV_Scoreboard.BoolValue)
	{
		return Plugin_Continue;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i))
		{
			continue;
		}

		UpdateScoreboard(i);
	}

	return Plugin_Continue;
}

public Action Timer_Message(Handle Timer)
{
	Shavit_PrintToChatAll("You may write !hide to hide other players.");

	return Plugin_Continue;
}

public void UpdateScoreboard(int client)
{
	float fPB = 0.0;
	Shavit_GetPlayerPB(client, view_as<BhopStyle>(0), fPB);

	int iScore = (fPB != 0.0 && fPB < 2000)? -RoundToFloor(fPB):-2000;

	if(gSG_Type == Game_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}

	else
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	if(gB_Rankings)
	{
		SetEntProp(client, Prop_Data, "m_iDeaths", Shavit_GetRank(client));
	}
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(!IsPlayerAlive(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	bool bInStart = Shavit_InsideZone(client, Zone_Start);
	bool bNoclipping = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);

	if(bNoclipping && !bInStart && Shavit_GetTimerStatus(client) == Timer_Running)
	{
		Shavit_StopTimer(client);
	}

	// prespeed
	if(!(gI_StyleProperties[Shavit_GetBhopStyle(client)] & STYLE_PRESPEED) && bInStart)
	{
		if((gCV_PreSpeed.IntValue == 2 || gCV_PreSpeed.IntValue == 3) && !(gF_LastFlags[client] & FL_ONGROUND) && (GetEntityFlags(client) & FL_ONGROUND) && buttons & IN_JUMP)
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			Shavit_PrintToChat(client, "Bhopping in the start zone is not allowed.");

			gF_LastFlags[client] = GetEntityFlags(client);

			return Plugin_Continue;
		}

		if(gCV_PreSpeed.IntValue == 1 || gCV_PreSpeed.IntValue == 3)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

			float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
			float fScale = gCV_PrespeedLimit.FloatValue / fSpeed_New;

			if(bNoclipping)
			{
				fSpeed[2] = 0.0;
			}

			else if(fScale < 1.0)
			{
				ScaleVector(fSpeed, fScale);
			}

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
		}
	}

	gF_LastFlags[client] = GetEntityFlags(client);

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	gB_Hide[client] = false;

	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);

	if(gH_GetMaxPlayerSpeed != null)
	{
		DHookEntity(gH_GetMaxPlayerSpeed, true, client);
	}
}

public Action OnTakeDamage(int victim, int attacker)
{
	switch(gCV_GodMode.IntValue)
	{
		case 0:
		{
			return Plugin_Continue;
		}

		case 1:
		{
			// 0 - world/fall damage
			if(attacker == 0)
			{
				return Plugin_Handled;
			}
		}

		case 2:
		{
			if(IsValidClient(attacker, true))
			{
				return Plugin_Handled;
			}
		}

		// else
		default:
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public void OnWeaponDrop(int client, int entity)
{
	if(gCV_NoWeaponDrops.BoolValue && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

// hide
public Action OnSetTransmit(int entity, int client)
{
	if(client != entity && gB_Hide[client])
	{
		if(!IsClientObserver(client) || (GetEntProp(client, Prop_Send, "m_iObserverMode") != 6 && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != entity))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(IsChatTrigger())
	{
		// hide commands
		return Plugin_Handled;
	}

	else if(sArgs[0] == '!' || sArgs[0] == '/')
	{
		bool bUpper = false;

		for(int i = 0; i < strlen(sArgs); i++)
		{
			if(IsCharUpper(sArgs[i]))
			{
				bUpper = true;

				break;
			}
		}

		if(bUpper)
		{
			char[] sCopy = new char[32];
			strcopy(sCopy, 32, sArgs[1]);

			FakeClientCommand(client, "sm_%s", sCopy);

			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action Command_Hide(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Hide[client] = !gB_Hide[client];

	// I use PTC instead of RTC there because I have an sm_hide bind just like many people :)
	Shavit_PrintToChat(client, "You are now %shiding players.", gB_Hide[client]? "":"not ");

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ChangeClientTeam(client, CS_TEAM_SPECTATOR);

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", iTarget);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_TeleportCommands.BoolValue)
	{
		Shavit_PrintToChat(client, "This command is disabled.");

		return Plugin_Handled;
	}

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		Teleport(client, GetClientSerial(iTarget));
	}

	else
	{
		Menu m = new Menu(MenuHandler_Teleport);
		m.SetTitle("Teleport to:");

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true) || i == client)
			{
				continue;
			}

			char[] serial = new char[16];
			IntToString(GetClientSerial(i), serial, 16);

			char[] sName = new char[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);

			m.AddItem(serial, sName);
		}

		m.ExitButton = true;

		m.Display(client, 60);
	}

	return Plugin_Handled;
}

public int MenuHandler_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(Teleport(param1, StringToInt(info)) == -1)
		{
			Command_Teleport(param1, 0);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int Teleport(int client, int targetserial)
{
	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "You can teleport only if you are alive.");

		return -1;
	}

	int iTarget = GetClientFromSerial(targetserial);

	if(Shavit_InsideZone(client, Zone_Start) || Shavit_InsideZone(client, Zone_End))
	{
		Shavit_PrintToChat(client, "You cannot teleport inside the start/end zones.");

		return -1;
	}

	if(!iTarget)
	{
		Shavit_PrintToChat(client, "Invalid target.");

		return -1;
	}

	float vecPosition[3];
	GetClientAbsOrigin(iTarget, vecPosition);

	Shavit_StopTimer(client);

	TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);

	return 0;
}

public Action Command_Weapon(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_WeaponCommands.BoolValue)
	{
		Shavit_PrintToChat(client, "This command is disabled.");

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "You need to be alive to spawn weapons.");

		return Plugin_Handled;
	}

	char[] sCommand = new char[16];
	GetCmdArg(0, sCommand, 16);

	int iSlot = CS_SLOT_SECONDARY;
	char[] sWeapon = new char[16];

	if(StrContains(sCommand, "usp", false) != -1)
	{
		strcopy(sWeapon, 16, (gSG_Type == Game_CSS)? "weapon_usp":"weapon_usp_silencer");
	}

	else if(StrContains(sCommand, "glock", false) != -1)
	{
		strcopy(sWeapon, 16, "weapon_glock");
	}

	else
	{
		strcopy(sWeapon, 16, "weapon_knife");
		iSlot = CS_SLOT_KNIFE;
	}

	int iWeapon = GetPlayerWeaponSlot(client, iSlot);

	if(iWeapon != -1)
	{
		RemovePlayerItem(client, iWeapon);
		AcceptEntityInput(iWeapon, "Kill");
	}

	iWeapon = GivePlayerItem(client, sWeapon);
	FakeClientCommand(client, "use %s", sWeapon);

	if(iSlot != CS_SLOT_KNIFE)
	{
		SetWeaponAmmo(client, iWeapon);
	}

	return Plugin_Handled;
}

public void SetWeaponAmmo(int client, int weapon)
{
	int iAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	SetEntData(client, gI_Ammo + (iAmmo * 4), 255, 4, true);

	if(gSG_Type == Game_CSGO)
	{
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 255);
	}
}

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client) && !IsClientObserver(client))
	{
		Shavit_PrintToChat(client, "You should be alive or spectate someone to see your/their spectators.");

		return Plugin_Handled;
	}

	int iSpecTarget = client;

	if(IsClientObserver(client))
	{
		iSpecTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

	if(args > 0)
	{
		char[] sTarget = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			Shavit_PrintToChat(client, "You can't target a dead player.");

			return Plugin_Handled;
		}

		iSpecTarget = iNewTarget;
	}

	int iCount;
	char[] sSpecs = new char[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || !IsClientObserver(i))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iSpecTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%N", i);
			}

			else
			{
				Format(sSpecs, 192, "%s, %N", sSpecs, i);
			}
		}
	}

	if(iCount > 0)
	{
		Shavit_PrintToChat(client, "\x03%N\x01 has %d spectators: %s", iSpecTarget, iCount, sSpecs);
	}

	else
	{
		Shavit_PrintToChat(client, "No one is spectating \x03%N\x01.", iSpecTarget);
	}

	return Plugin_Handled;
}

public void Shavit_OnWorldRecord(int client, BhopStyle style, float time, int jumps)
{
	char[] sUpperCase = new char[32];
	strcopy(sUpperCase, 32, gS_BhopStyles[view_as<int>(style)]);

	for(int i = 0; i < strlen(sUpperCase); i++)
	{
		if(!IsCharUpper(sUpperCase[i]))
		{
			sUpperCase[i] = CharToUpper(sUpperCase[i]);
		}
	}

	for(int i = 1; i <= 3; i++)
	{
		Shavit_PrintToChatAll("%sNEW %s WR!!!", gSG_Type == Game_CSGO? "\x02":"\x077D42C9", sUpperCase);
	}
}

public void Shavit_OnRestart(int client)
{
	if(!gCV_RespawnOnRestart.BoolValue)
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
		{
			CS_SwitchTeam(client, CS_TEAM_T);
		}

		else
		{
			CS_SwitchTeam(client, CS_TEAM_CT);
		}

		CreateTimer(0.1, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Respawn(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(IsValidClient(client) && !IsPlayerAlive(client))
	{
		CS_RespawnPlayer(client);

		if(gCV_RespawnOnRestart.BoolValue)
		{
			RestartTimer(client);
		}
	}

	return Plugin_Handled;
}

public void RestartTimer(int client)
{
	if(Shavit_ZoneExists(Zone_Start))
	{
		Shavit_RestartTimer(client);
	}
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(gCV_HideRadar.BoolValue)
	{
		CreateTimer(0.0, RemoveRadar, GetClientSerial(client));
	}

	if(gCV_StartOnSpawn.BoolValue)
	{
		RestartTimer(client);
	}

	if(gCV_NoBlock.BoolValue)
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	}

	if(gCV_Scoreboard.BoolValue && !IsFakeClient(client))
	{
		UpdateScoreboard(client);
	}
}

public Action RemoveRadar(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(!IsValidClient(client))
	{
		return Plugin_Stop;
	}

	if(gSG_Type == Game_CSGO)
	{
		SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | (1 << 12)); // disables player radar
	}

	else
	{
		SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 3600.0);
		SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
	}

	return Plugin_Stop;
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	if(gCV_HideTeamChanges.BoolValue)
	{
		event.BroadcastDisabled = true;
	}

	if(gCV_AutoRespawn.BoolValue && StrEqual(name, "player_death"))
	{
		int client = GetClientOfUserId(event.GetInt("userid"));

		if(!IsFakeClient(client))
		{
			CreateTimer(gCV_AutoRespawn.FloatValue, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	return Plugin_Continue;
}

public void Weapon_Fire(Event event, const char[] name, bool dB)
{
	if(gCV_WeaponCommands.IntValue < 2)
	{
		return;
	}

	char[] sWeapon = new char[16];
	event.GetString("weapon", sWeapon, 16);

	if(StrContains(sWeapon, "usp") != -1 || StrContains(sWeapon, "hpk") != -1 || StrEqual(sWeapon, "glock"))
	{
		int client = GetClientOfUserId(event.GetInt("userid"));

		SetWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));
	}
}

public void Shavit_OnFinish(int client)
{
	if(!gCV_Scoreboard.BoolValue)
	{
		return;
	}

	UpdateScoreboard(client);
}
