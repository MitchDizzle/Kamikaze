#pragma semicolon 1
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2items>
#include <clientprefs>

bool loadedScore[MAXPLAYERS+1];
int playerScore[MAXPLAYERS+1];
bool playerExploded[MAXPLAYERS+1];
float canExplode[MAXPLAYERS+1];

Handle cKamikazeScore;

ConVar cExplodeDelay; // 5.0
ConVar cExplosionOffset; //42.0
ConVar cWeirdAnimation; // 1
ConVar cSuicide; //1
ConVar cSuicideDamage; //500.0
ConVar cSuicideDistance; //100.0
ConVar cTouchDamage; //500.0
ConVar cTouchDistance; //100.0
ConVar cFriendlyFire; //100.0

#define KAMIKAZE_VERSION "1.2.0"
public Plugin myinfo = {
    name = "KaMiKaZe!",
    author = "Mitch",
    description = "TF2 Gamemode.",
    version = KAMIKAZE_VERSION,
    url = "mtch.tech"
}

public void OnPluginStart() {
    HookEvent("player_death", Event_Death, EventHookMode_Pre);
    HookEvent("item_found", Event_Block, EventHookMode_Pre);
    HookEvent("player_team", Event_Team, EventHookMode_Pre);
    HookEvent("post_inventory_application", Event_Inventory);

    cExplodeDelay = CreateConVar("sm_kamikaze_explode_delay", "5.0", "The delay before a player can explode, to prevent premature explosions.");
    cExplosionOffset = CreateConVar("sm_kamikaze_explode_offset", "42.0", "The Z offset of the explosion");
    cWeirdAnimation = CreateConVar("sm_kamikaze_weirdanim", "1", "0 - Makes the animation more of a bat, 1 - T-Pose animation with floppy legs");
    cSuicide = CreateConVar("sm_kamikaze_suicide", "1", "0 - Do not self destruct, 1 - Explode on suicide, 2 - Prevent Suicide");
    cSuicideDamage = CreateConVar("sm_kamikaze_suicide_damage", "500.0", "Damage of explosion on suicide.");
    cSuicideDistance = CreateConVar("sm_kamikaze_suicide_distance", "100.0", "Distance of explosion on suicide.");
    cTouchDamage = CreateConVar("sm_kamikaze_touch_damage", "500.0", "Damage of explosion on touch.");
    cTouchDistance = CreateConVar("sm_kamikaze_touch_distance", "100.0", "Distance of explosion on touch.");
    cFriendlyFire = CreateConVar("sm_kamikaze_friendlyfire", "0", "Explosions hurt and kill players (This counts as score points)");
    AutoExecConfig(true, "Kamikaze");
    CreateConVar("sm_kamikaze_version", KAMIKAZE_VERSION, "Kamikaze Version", FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    //Prevent suicide 1-800-273-8255
    AddCommandListener(Command_Suicide, "kill");
    AddCommandListener(Command_Suicide, "explode");
    
    cKamikazeScore = RegClientCookie("kamikaze", "Kamikaze Count", CookieAccess_Private);

    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientInGame(i)) {
            OnClientPutInServer(i);
            if(AreClientCookiesCached(i)) {
                OnClientCookiesCached(i);
            }
        }
    }
}

public void OnClientCookiesCached(int client) {
    char sValue[64];
    GetClientCookie(client, cKamikazeScore, sValue, sizeof(sValue));
    playerScore[client] = StrEqual(sValue, "", false) ? 0 : StringToInt(sValue);
    loadedScore[client] = true;
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_StartTouch, OnStartTouch);
    SDKHook(client, SDKHook_OnTakeDamage, TakeDamageHook);
    loadedScore[client] = false;
}

public void OnClientDisconnect(int client) {
    playerScore[client] = 0;
    loadedScore[client] = false;
}

public void OnMapStart() {
    int playerManager = FindEntityByClassname(MaxClients+1, "tf_player_manager");
    if(playerManager == -1) {
        SetFailState("Unable to find tf_player_manager entity");
    }
    SDKHook(playerManager, SDKHook_ThinkPost, Hook_OnThinkPost);
    CreateTimer(0.1, Timer_HudUpdate, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Hook_OnThinkPost(int ent) {
    static iTotalScoreOffset = -1;
    if (iTotalScoreOffset == -1) {
        iTotalScoreOffset = FindSendPropInfo("CTFPlayerResource", "m_iTotalScore");
    }
    
    int iTotalScore[MAXPLAYERS+1];
    GetEntDataArray(ent, iTotalScoreOffset, iTotalScore, MaxClients+1);
    
    for(int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && playerScore[i] > 0) {
            iTotalScore[i] = playerScore[i];
        }
    }
    
    SetEntDataArray(ent, iTotalScoreOffset, iTotalScore, MaxClients+1);
}

public Action Command_Suicide(int client, char[] command, int args) {
    switch(cSuicide.IntValue) {
        case 0: {
            return Plugin_Continue;
        }
        case 1: {
            if(client > 0 && client <= MaxClients && IsPlayerAlive(client) && canExplode[client] < GetEngineTime()) {
                Explode(client, cSuicideDamage.FloatValue, cSuicideDistance.FloatValue, "ExplosionCore_Wall", "weapons/explode1.wav");
                return Plugin_Handled;
            }
        }
        case 2: {
            return Plugin_Handled;
        }
    }
    return Plugin_Continue;
}

public Action Event_Inventory(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(!IsPlayerAlive(client)) {
        return Plugin_Continue;
    }
    
    if(GetEntProp(client, Prop_Send, "m_PlayerClass") != 1) {
        TF2_SetPlayerClass(client, TFClass_Scout);
        TF2_RegeneratePlayer(client);
        return Plugin_Handled;
    }

    playerExploded[client] = false;
    TF2_RemoveAllWeapons(client);
    SpawnWeapon(client, cWeirdAnimation.BoolValue ? "tf_weapon_pda_engineer_destroy" : "tf_weapon_bat", 26, 0, 0, "250 ; 50 ; 821 ; 1", true);
    SetEntProp(client, Prop_Send, "m_bDrawViewmodel", false);
    canExplode[client] = GetEngineTime() + cExplodeDelay.FloatValue;
    return Plugin_Continue;
}

public Action TakeDamageHook(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon,
        float damageForce[3], float damagePosition[3], int damagecustom) {
    if(attacker > MaxClients) {
        char entName[48];
        GetEdictClassname(attacker, entName, sizeof(entName));
        if(StrEqual(entName, "tf_generic_bomb")) {
            int owner = GetEntPropEnt(attacker, Prop_Send, "m_hOwnerEntity");
            if(owner != client && owner > 0 && owner <= MaxClients) {
                if(!cFriendlyFire.BoolValue && GetClientTeam(client) == GetClientTeam(owner)) {
                    damageForce[0] = 0.0;
                    damageForce[1] = 0.0;
                    damageForce[2] = 0.0;
                    damage = 0.0;
                    return Plugin_Changed;
                }
            }
        }
    }
    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
    if(IsPlayerAlive(client)) {
        int dashCount = GetEntProp(client, Prop_Send, "m_iAirDash");
        if(dashCount > 1) {
            SetEntProp(client, Prop_Send, "m_iAirDash", GetRandomInt(0,1));
        }
        if(buttons & IN_ATTACK && canExplode[client] < GetEngineTime()) {
            Explode(client, cSuicideDamage.FloatValue, cSuicideDistance.FloatValue, "ExplosionCore_Wall", "weapons/explode1.wav");
        }
    }
}

public Action Timer_HudUpdate(Handle timer) {
    for(int client = 1; client <= MaxClients; client++) {
        if(IsClientInGame(client) && IsPlayerAlive(client)) {
            SetHudTextParams(-1.0, 0.80, 0.1, 255, 128, 0, 255);
            ShowHudText(client, 0, "Touch/Left-Click = KABOOM!");
        }
    }
}

public Action Event_Block(Event event, const char[] name, bool dontBroadcast) {
    SetEventBroadcast(event, true);
    return Plugin_Continue;
}

public Action Event_Death(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(client <= 0 || client > MaxClients) {
        return Plugin_Continue;
    }

    int iFlags = event.GetInt("death_flags");
    if(iFlags & TF_DEATHFLAG_DEADRINGER) {
        return Plugin_Continue; //Not a real death...
    }
    
    int inflictor = event.GetInt("inflictor_entindex");
    if(inflictor > MaxClients && IsValidEntity(inflictor)) {
        char sClassname[64];
        GetEdictClassname(inflictor, sClassname, sizeof(sClassname));
        if(StrEqual(sClassname, "tf_generic_bomb", false)) {
            int owner = GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity");
            if(owner > 0 && owner <= MaxClients) {
                if(owner == client) {
                    return Plugin_Handled;
                }
                if(!loadedScore[client] && AreClientCookiesCached(client)) {
                    OnClientCookiesCached(client);
                }
                if(loadedScore[client]) {
                    playerScore[owner]++;
                    PrintToChat(owner, "\x0796281B[\x07D91E18Kamikaze\x0796281B]\x01 Score:\x0703C9A9 %i", playerScore[owner]);
                    char tempBuffer[32];
                    IntToString(playerScore[owner], tempBuffer, sizeof(tempBuffer));
                    SetClientCookie(owner, cKamikazeScore, tempBuffer);
                }
                Event eventNew = CreateEvent("player_death");
                if(eventNew != null) {
                    eventNew.SetInt("userid", event.GetInt("userid"));
                    eventNew.SetInt("attacker", GetClientUserId(owner));
                    eventNew.SetString("weapon", "firedeath");
                    eventNew.SetBool("headshot", false);
                    eventNew.Fire(false);
                }
                return Plugin_Handled;
            }
        }
    }
    return Plugin_Continue;
}

public Action Event_Team(Event event, const char[] name, bool dontBroadcast) {
    SetEventBroadcast(event, true);
    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
    if(StrEqual(classname, "tf_dropped_weapon", false) || StrEqual(classname, "tf_spell_pickup", false) || StrContains(classname, "ammo") >= 0) {
        SDKHook(entity, SDKHook_Spawn, Hook_BlockSpawn);
    }
}

public Action Hook_BlockSpawn(int entity) {
    return Plugin_Handled;
}

public void OnStartTouch(int client, int other) {
    if(other <= 0 || other > MaxClients || playerExploded[client] || playerExploded[other]) {
        return;
    }
    playerExploded[client] = true;
    playerExploded[other] = true;
    
    float emptyVec[3];
    float clientVelocity[3];
    float otherVelocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", clientVelocity);
    GetEntPropVector(other , Prop_Data, "m_vecAbsVelocity", otherVelocity);
    float clientVel = GetVectorDistance(emptyVec, clientVelocity, false);
    float otherVel = GetVectorDistance(emptyVec, otherVelocity, false);
    int target = clientVel >= otherVel ? client : other;
    Explode(target, cTouchDamage.FloatValue, cTouchDistance.FloatValue, "ExplosionCore_Wall", "weapons/explode1.wav");
}

stock void Explode(int client, float flDamage, float flRadius, const char[] strParticle, const char[] strSound) {
    canExplode[client] = GetEngineTime() + 1.0; // Prevent any double explosions.
    float fPos[3];
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", fPos);
    fPos[2] += cExplosionOffset.FloatValue;
    
    int iBomb = CreateEntityByName("tf_generic_bomb");
    DispatchKeyValueVector(iBomb, "origin", fPos);
    DispatchKeyValueFloat(iBomb, "damage", flDamage);
    DispatchKeyValueFloat(iBomb, "radius", flRadius);
    DispatchKeyValue(iBomb, "health", "1");
    DispatchKeyValue(iBomb, "explode_particle", strParticle);
    DispatchKeyValue(iBomb, "sound", strSound);
    DispatchSpawn(iBomb);
    SetEntPropEnt(iBomb, Prop_Send, "m_hOwnerEntity", client);
    AcceptEntityInput(iBomb, "Detonate", client, client);
    char output[64];
    Format(output, sizeof(output), "OnUser1 !self:Kill::%f:1", 0.1);
    SetVariantString(output);
    AcceptEntityInput(iBomb, "AddOutput");
    AcceptEntityInput(iBomb, "FireUser1");
}

stock int SpawnWeapon(int client, char[] name, int index, int level, int qual, char[] att, bool equip) {
    int flags = OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES | FORCE_GENERATION;
    Handle hWeapon = TF2Items_CreateItem(flags);
    if(hWeapon == INVALID_HANDLE) {
        return -1;
    }
    TF2Items_SetClassname(hWeapon, name);
    TF2Items_SetItemIndex(hWeapon, index);
    TF2Items_SetLevel(hWeapon, level);
    TF2Items_SetQuality(hWeapon, qual);
    if(!StrEqual(att, "", false)) {
        char atts[32][32];
        int count = ExplodeString(att, " ; ", atts, 32, 32);
        if(count > 0) {
            TF2Items_SetNumAttributes(hWeapon, count/2);
            int i2 = 0;
            for(int i = 0;  i < count;  i+= 2) {
                TF2Items_SetAttribute(hWeapon, i2, StringToInt(atts[i]), StringToFloat(atts[i+1]));
                i2++;
            }
        } else {
            TF2Items_SetNumAttributes(hWeapon, 0);
        }
    } else {
        TF2Items_SetNumAttributes(hWeapon, 0);
    }
    int entity = TF2Items_GiveNamedItem(client, hWeapon);
    CloseHandle(hWeapon);
    hWeapon = INVALID_HANDLE;
    if(equip) {
        EquipPlayerWeapon(client, entity);
    }
    return entity;
}