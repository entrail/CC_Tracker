-- CCTracker_Data.lua
-- Definitions for tracked CC spells and enemy defensive abilities

-- CC spells to track, matched by spellName from the combat log.
-- ccType:
--   "aura"      = tracked via SPELL_AURA_APPLIED (hit) + SPELL_MISSED (miss)
--   "interrupt" = tracked via SPELL_INTERRUPT (hit) + SPELL_MISSED (miss)
-- CC level definitions:
--   "hard"   = full loss of control (stuns, fears, sleeps, polymorphs, incapacitates, disorients, banishes)
--   "medium" = significant impairment without full loss of control (roots, interrupts, silences)
--   "light"  = minor impairment (slows)
CCTracker_CCSpells = {
    -- MAGE
    ["Polymorph"]           = { ccType = "aura",      ccLevel = "hard",   label = "Polymorph" },
    ["Dragon's Breath"]     = { ccType = "aura",      ccLevel = "hard",   label = "Dragon's Breath" },
    ["Frost Nova"]          = { ccType = "aura",      ccLevel = "medium", label = "Frost Nova" },
    ["Counterspell"]        = { ccType = "interrupt",  ccLevel = "medium", label = "Counterspell" },
    ["Cone of Cold"]        = { ccType = "aura",      ccLevel = "light",  label = "Cone of Cold" },
    ["Slow"]                = { ccType = "aura",      ccLevel = "light",  label = "Slow" },
    -- Mage Water Elemental (pet) ability
    ["Freeze"]              = { ccType = "aura",      ccLevel = "medium", label = "Freeze" },            -- Water Elemental pet: AoE root, different spell from the mage's own Frost Nova
    -- Mage talent procs
    ["Frostbite"]           = { ccType = "aura",      ccLevel = "medium", label = "Frostbite" },        -- Frost talent: chilling effects have a 15% chance to root
    ["Impact"]              = { ccType = "aura",      ccLevel = "hard",   label = "Impact" },            -- Fire talent: fire spells have up to 10% chance to stun for 2s
    -- ROGUE
    ["Sap"]                 = { ccType = "aura",      ccLevel = "hard",   label = "Sap" },
    ["Blind"]               = { ccType = "aura",      ccLevel = "hard",   label = "Blind" },
    ["Kidney Shot"]         = { ccType = "aura",      ccLevel = "hard",   label = "Kidney Shot" },
    ["Cheap Shot"]          = { ccType = "aura",      ccLevel = "hard",   label = "Cheap Shot" },
    ["Gouge"]               = { ccType = "aura",      ccLevel = "hard",   label = "Gouge" },
    ["Kick"]                = { ccType = "interrupt",  ccLevel = "medium", label = "Kick" },
    -- Rogue talent procs  (Mace Stun Effect is shared with Warrior — see WARRIOR section)
    -- DRUID
    ["Hibernate"]           = { ccType = "aura",      ccLevel = "hard",   label = "Hibernate" },
    ["Cyclone"]             = { ccType = "aura",      ccLevel = "hard",   label = "Cyclone" },
    ["Bash"]                = { ccType = "aura",      ccLevel = "hard",   label = "Bash" },
    ["Maim"]                = { ccType = "aura",      ccLevel = "hard",   label = "Maim" },
    ["Pounce"]              = { ccType = "aura",      ccLevel = "hard",   label = "Pounce" },
    ["Entangling Roots"]    = { ccType = "aura",      ccLevel = "medium", label = "Entangling Roots" },
    ["Feral Charge Effect"] = { ccType = "aura",      ccLevel = "medium", label = "Feral Charge" },
    -- PRIEST
    ["Shackle Undead"]      = { ccType = "aura",      ccLevel = "hard",   label = "Shackle Undead" },
    ["Mind Control"]        = { ccType = "aura",      ccLevel = "hard",   label = "Mind Control" },
    ["Psychic Scream"]      = { ccType = "aura",      ccLevel = "hard",   label = "Psychic Scream" },
    ["Silence"]             = { ccType = "interrupt",  ccLevel = "medium", label = "Silence" },
    -- Priest talent procs
    ["Blackout"]            = { ccType = "aura",      ccLevel = "hard",   label = "Blackout" },          -- Shadow talent: shadow spells have up to 10% chance to stun for 3s
    -- WARLOCK
    ["Fear"]                = { ccType = "aura",      ccLevel = "hard",   label = "Fear" },
    ["Banish"]              = { ccType = "aura",      ccLevel = "hard",   label = "Banish" },
    ["Howl of Terror"]      = { ccType = "aura",      ccLevel = "hard",   label = "Howl of Terror" },
    ["Death Coil"]          = { ccType = "aura",      ccLevel = "hard",   label = "Death Coil" },
    ["Shadowfury"]          = { ccType = "aura",      ccLevel = "hard",   label = "Shadowfury" },
    ["Seduction"]           = { ccType = "aura",      ccLevel = "hard",   label = "Seduction" },       -- Succubus (pet)
    ["Spell Lock"]          = { ccType = "interrupt",  ccLevel = "medium", label = "Spell Lock" },      -- Felhunter (pet)
    ["Curse of Exhaustion"] = { ccType = "aura",      ccLevel = "light",  label = "Curse of Exhaustion" },
    -- HUNTER
    ["Scatter Shot"]        = { ccType = "aura",      ccLevel = "hard",   label = "Scatter Shot" },
    ["Wyvern Sting"]        = { ccType = "aura",      ccLevel = "hard",   label = "Wyvern Sting" },
    ["Freezing Trap Effect"]= { ccType = "aura",      ccLevel = "hard",   label = "Freezing Trap" },
    ["Scare Beast"]         = { ccType = "aura",      ccLevel = "hard",   label = "Scare Beast" },
    ["Intimidation"]        = { ccType = "aura",      ccLevel = "hard",   label = "Intimidation" },     -- Hunter pet
    ["Wing Clip"]           = { ccType = "aura",      ccLevel = "light",  label = "Wing Clip" },
    ["Concussive Shot"]     = { ccType = "aura",      ccLevel = "light",  label = "Concussive Shot" },
    -- Hunter talent procs / abilities
    ["Entrapment"]          = { ccType = "aura",      ccLevel = "medium", label = "Entrapment" },        -- Entrapment talent: frost/immolation/explosive traps root nearby enemies for 5s
    ["Counterattack"]       = { ccType = "aura",      ccLevel = "medium", label = "Counterattack" },     -- Survival talent: melee attack after dodging that roots the target for 5s
    -- PALADIN
    ["Hammer of Justice"]   = { ccType = "aura",      ccLevel = "hard",   label = "Hammer of Justice" },
    ["Repentance"]          = { ccType = "aura",      ccLevel = "hard",   label = "Repentance" },
    ["Turn Evil"]           = { ccType = "aura",      ccLevel = "hard",   label = "Turn Evil" },
    ["Avenger's Shield"]    = { ccType = "aura",      ccLevel = "medium", label = "Avenger's Shield" },
    -- SHAMAN
    ["Earth Shock"]         = { ccType = "interrupt",  ccLevel = "medium", label = "Earth Shock" },
    ["Frost Shock"]         = { ccType = "aura",      ccLevel = "light",  label = "Frost Shock" },
    -- WARRIOR
    ["Intimidating Shout"]  = { ccType = "aura",      ccLevel = "hard",   label = "Intimidating Shout" },
    ["Charge"]              = { ccType = "aura",      ccLevel = "hard",   label = "Charge" },
    ["Intercept"]           = { ccType = "aura",      ccLevel = "hard",   label = "Intercept" },
    ["Concussion Blow"]     = { ccType = "aura",      ccLevel = "hard",   label = "Concussion Blow" },
    ["Pummel"]              = { ccType = "interrupt",  ccLevel = "medium", label = "Pummel" },
    ["Shield Bash"]         = { ccType = "interrupt",  ccLevel = "medium", label = "Shield Bash" },
    ["Hamstring"]           = { ccType = "aura",      ccLevel = "light",  label = "Hamstring" },
    ["Piercing Howl"]       = { ccType = "aura",      ccLevel = "light",  label = "Piercing Howl" },
    -- Warrior/Rogue talent procs
    ["Mace Stun Effect"]    = { ccType = "aura",      ccLevel = "hard",   label = "Mace Stun" },         -- Mace Specialization: mace attacks have a 3% chance to stun for 3s (Warrior Arms & Rogue Combat)
    -- RACIAL
    ["War Stomp"]           = { ccType = "aura",      ccLevel = "hard",   label = "War Stomp" },        -- Tauren
    ["Arcane Torrent"]      = { ccType = "aura",      ccLevel = "medium", label = "Arcane Torrent" },   -- Blood Elf
    -- WEAPON ON-HIT PROCS
    -- These fire from the player's weapon and appear in the combat log with the player as source,
    -- so they are caught by the standard sourceGUID == playerGUID check.
    ["Stormherald"]         = { ccType = "aura",      ccLevel = "hard",   label = "Stormherald" },      -- TBC Blacksmithing 2H mace: on-hit stun for 3s
    ["The Unstoppable Force"] = { ccType = "aura",    ccLevel = "hard",   label = "Unstop. Force" },    -- Darkmoon Faire 2H mace: on-hit stun for 3s
    ["Thunderfury"]         = { ccType = "aura",      ccLevel = "light",  label = "Thunderfury" },      -- Thunderfury legendary 1H sword: on-hit movement/attack speed slow
}

-- Sort priority for CC levels (lower = higher priority / shown first)
CCTracker_CCLevelOrder = { hard = 1, medium = 2, light = 3 }

-- Display labels and colours for each CC level
CCTracker_CCLevelInfo = {
    hard   = { label = "Hard CC",   r = 1,    g = 0.35, b = 0.35 },
    medium = { label = "Medium CC", r = 1,    g = 0.70, b = 0.10 },
    light  = { label = "Light CC",  r = 0.65, g = 0.65, b = 0.65 },
}

-- Enemy defensive abilities to track.
-- When one of these auras is active on a target when our CC misses,
-- the miss is tagged as "wasted" due to that defensive.
-- category: hints at which miss types are caused by this ability.
CCTracker_DefensiveSpells = {
    -- Full immunities
    [45438] = { name = "Ice Block",              category = "IMMUNE",  description = "Full spell & attack immunity" },
    [642]   = { name = "Divine Shield",          category = "IMMUNE",  description = "Full damage & effect immunity" },
    [10278] = { name = "Blessing of Protection", category = "IMMUNE",  description = "Physical attack immunity" },
    [34471] = { name = "The Beast Within",       category = "IMMUNE",  description = "Immune to CC effects" },
    [19574] = { name = "Bestial Wrath",          category = "IMMUNE",  description = "Pet immune to CC" },
    [18499] = { name = "Berserker Rage",         category = "IMMUNE",  description = "Immune to Fear/Incapacitate" },
    [1719]  = { name = "Recklessness",           category = "IMMUNE",  description = "Immune to stuns" },
    -- High evasion
    [5277]  = { name = "Evasion",                category = "DODGE",   description = "+50% dodge chance" },
    [19263] = { name = "Deterrence",             category = "DEFLECT", description = "100% deflect chance" },
    -- Spell resistance/immunity
    [31224] = { name = "Cloak of Shadows",       category = "RESIST",  description = "Resist all spell effects" },
    -- Spell reflection
    [23920] = { name = "Spell Reflection",       category = "REFLECT", description = "Reflects next spell" },
    [34471] = { name = "The Beast Within",       category = "IMMUNE",  description = "Immune to CC effects" },
    -- Spell absorption
    [8178]  = { name = "Grounding Totem Effect", category = "ABSORB",  description = "Absorbs one targeted spell" },
    -- Paladin
    [498]   = { name = "Divine Protection",      category = "IMMUNE",  description = "50% damage reduction" },
}

-- Human-readable names for miss types
CCTracker_MissTypeText = {
    MISS    = "Missed",
    DODGE   = "Dodged",
    PARRY   = "Parried",
    BLOCK   = "Blocked",
    RESIST  = "Resisted",
    ABSORB  = "Absorbed",
    DEFLECT = "Deflected",
    EVADE   = "Evaded",
    REFLECT = "Reflected",
    IMMUNE  = "Immune",
}

-- Ordered list of miss types for consistent display
CCTracker_MissTypeOrder = {
    "MISS", "DODGE", "PARRY", "BLOCK",
    "RESIST", "ABSORB", "DEFLECT",
    "EVADE", "REFLECT", "IMMUNE",
}

-- Session type display names
CCTracker_SessionTypeNames = {
    arena          = "Arena",
    arena_rated    = "Arena (Rated)",
    arena_skirmish = "Arena (Skirmish)",
    pvp            = "Battleground",
    party          = "Dungeon",
    raid           = "Raid",
    world          = "World",
}
