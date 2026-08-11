addon.name      = 'BLUAlert';
addon.author    = 'Angelofdeath';
addon.version   = '1.2.0';
addon.desc      = 'Alerts when a mob uses unknown Blue Magic and when a Blue Magic spell is learned.';
addon.link      = '';

require('common');

local chat = require('chat');

local BLU_JOB           = 16;
local BLU_SKILL         = 43;
local MSG_LEARN_BLU     = 419;
local CAT_ABILITY_START = 7;  
local CAT_MAGIC_START   = 8;  

-- Monster ability names that do not match the BLU spell resource name.
local ABILITY_ALIASES = T{
    ["everyone's grudge"]     = 'evryone. grudge',
    ["nature's meditation"]   = 'nat. meditation',
    ['orcish counterstance']  = 'o. counterstance',
    ['tempestuous upheaval']  = 'tem. upheaval',
    ['atramentous libations'] = 'atra. libations',
    ['winds of promyvion']    = 'winds of promy.',
    ['quadratic continuum']   = 'quad. continuum',
};

local state = T{
    is_blu        = false,
    spell_by_name = T{},
    last_unknown  = T{}, 
    last_learn    = 0,
};

local function msg(s)
    print(chat.header(addon.name) + chat.message(s));
end

local function play(file)
    ashita.misc.play_sound(('%s\\sounds\\%s'):fmt(addon.path, file));
end

local function refresh_job()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil) then
        state.is_blu = false;
        return;
    end
    state.is_blu = (player:GetMainJob() == BLU_JOB);
end
local function get_skill_cap(level)
    -- A+ skill rating.
    -- Starts at 3 for level 1
    -- Plus 3 for levels [1,50]
    -- Plus 5 for levels [51,60]
    -- Plus 4 for level 61
    -- Plus 5 for levels [62,66]
    -- Plus 4 for level 67
    -- Plus 5 for levels [68,75]

    local skill_cap = 0;
    if level >= 1 then
        skill_cap = skill_cap + (math.min(50, level) * 3);
    end
    if level >= 51 then
        skill_cap = skill_cap + (math.min(10, level - 50) * 5)
    end
    if level >= 61 then
        skill_cap = skill_cap + 4;
    end
    if level >= 62 then
        skill_cap = skill_cap + (math.min(5, level-61) * 5);
    end
    if level >= 67 then
        skill_cap = skill_cap + 4;
    end
    if level > 67 then
        skill_cap = skill_cap + ((level-68) * 5);
    end
    return skill_cap;
end
local function msg(s)
    print(chat.header(addon.name) + chat.color(chat.colors.RoyalBlue, s));
end
--[[
* Builds a lookup of learnable BLU spells by lowercase English name.
* Same identification approach as blucheck (Skill == 43, BLU level > 0).
--]]
local function build_spell_map()
    local map = T{};
    local res = AshitaCore:GetResourceManager();

    for id = 0, 2048 do
        local spell = res:GetSpellById(id);
        if (spell ~= nil and spell.Skill == BLU_SKILL) then
            local name = spell.Name[1];
            if (name ~= nil and name ~= '') and spell.LevelRequired[17] <= 75 then
                map[name:lower()] = T{ id = id, name = name};
            end
        end
    end

    state.spell_by_name = map;
end

local function get_index_from_id(server_id)
    local ent = AshitaCore:GetMemoryManager():GetEntity();
    local index = bit.band(server_id, 0x7FF);

    if (ent:GetServerId(index) == server_id) then
        return index;
    end

    for i = 1, 2303 do
        if (ent:GetServerId(i) == server_id) then
            return i;
        end
    end

    return 0;
end

local function is_monster(index)
    if (index == 0) then
        return false;
    end
    return bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(index), 0xFF) == 0x10;
end

local function knows_spell(id)
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    return (player ~= nil) and player:HasSpell(id);
end

local function alert_unknown(id, name)
    local now = os.clock();
    local prev = state.last_unknown[id] or 0;
    if ((now - prev) < 2.0) then
        return;
    end
    state.last_unknown[id] = now;

    msg(('*** UNLEARNED BLUE MAGIC: %s ***'):fmt(name or ('ID ' .. tostring(id))));
    play('UnknownBlueMagicUsed.wav');
end

local function alert_learn(name)
    local now = os.clock();
    if ((now - state.last_learn) < 1.0) then
        return;
    end
    state.last_learn = now;

    if (name ~= nil and name ~= '') then
        msg(('*** BLUE MAGIC LEARNED: %s ***'):fmt(name));
    else
        msg('*** BLUE MAGIC LEARNED! ***');
    end
    play('BlueMagicLearned.wav');
end

local function resolve_blu_spell(ability_name)
    if (ability_name == nil or ability_name == '') then
        return nil;
    end

    
    ability_name = ability_name:gsub('%z', ''):gsub('%s+$', '');
    local key = ability_name:lower();
    key = ABILITY_ALIASES[key] or key;

    return state.spell_by_name[key];
end

local function get_monster_ability_name(ability_id)
    if (ability_id == nil or ability_id < 256) then
        return nil;
    end

    local res = AshitaCore:GetResourceManager();
    local index = ability_id - 256;
    return res:GetString('monsters.abilities', index, 2)
        or res:GetString('monsters.abilities', index);
end

--[[
* Handles 0x028 action packets.
* Category / param layout from fields.lua (incoming 0x028):
*   Category @ 0x0A:2 (4 bits)
*   First action Param @ bit 213 (17 bits) -- see action_base Param
--]]
local function handle_action(e)
    if (not state.is_blu) then
        return;
    end

    local category = ashita.bits.unpack_be(e.data_raw, 10, 2, 4);
    if (category ~= CAT_ABILITY_START and category ~= CAT_MAGIC_START) then
        return;
    end

    
    local top_param = ashita.bits.unpack_be(e.data_raw, 0x0C, 6, 16);
    if (top_param == 28787) then
        return;
    end

    local actor_id = struct.unpack('L', e.data, 0x05 + 1);
    local actor_index = get_index_from_id(actor_id);
    if (not is_monster(actor_index)) then
        return;
    end

    
    local param = ashita.bits.unpack_be(e.data_raw, 0, 213, 17);

    if (category == CAT_MAGIC_START) then
        local spell = AshitaCore:GetResourceManager():GetSpellById(param);
        if (spell == nil or spell.Skill ~= BLU_SKILL) then
            return;
        end
        if (knows_spell(param)) then
            return;
        end
        alert_unknown(param, spell.Name[1]);
        return;
    end

    
    local ability_name = get_monster_ability_name(param);
    local info = resolve_blu_spell(ability_name);
    if (info == nil) then
        return;
    end
    if (knows_spell(info.id)) then
        return;
    end

    alert_unknown(info.id, info.name);
end

--[[
* Handles 0x029 action message — message 419 is "learns a blue magic spell".
* Field offsets from fields.lua / blucheck / blumon.
--]]
local function handle_message(e)
    local msgid = struct.unpack('H', e.data, 0x18 + 1);
    if (msgid ~= MSG_LEARN_BLU) then
        return;
    end

    local spell_id = struct.unpack('L', e.data, 0x0C + 1);
    local sender   = struct.unpack('H', e.data, 0x14 + 1);
    local target   = struct.unpack('H', e.data, 0x16 + 1);

    local player = GetPlayerEntity();
    if (player == nil or sender ~= player.TargetIndex or target ~= player.TargetIndex) then
        return;
    end

    local name = AshitaCore:GetResourceManager():GetString('spells.names', spell_id);
    alert_learn(name);
end

ashita.events.register('load', 'blualert_load', function ()
    build_spell_map();
    refresh_job();
    msg('Loaded.');
    if (state.is_blu) then
        msg('Blue Mage detected.');
    else
        msg('Not on BLU main — alerts idle until you change job.');
    end
end);

ashita.events.register('packet_in', 'blualert_packet_in', function (e)
    if (e.id == 0x0028) then
        handle_action(e);
        return;
    end

    if (e.id == 0x0029) then
        handle_message(e);
        return;
    end

    
    if (e.id == 0x000A or e.id == 0x001B or e.id == 0x0061) then
        refresh_job();
    end
end);

ashita.events.register('command', 'blualert_command', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1]:lower() ~= '/blualert') then
        return;
    end
    e.blocked = true;

    local sub = args[2] and args[2]:lower() or '';

    if (sub == 'test') then
        msg('Testing unknown Blue Magic alert.');
        alert_unknown(0, 'TEST SPELL');
    elseif (sub == 'learn') then
        msg('Testing learned Blue Magic alert.');
        alert_learn('TEST SPELL');
    elseif (sub == 'status') then
        refresh_job();
        msg(('Main job BLU: %s | Mapped spells: %d'):fmt(tostring(state.is_blu), state.spell_by_name:length()));
    elseif (sub == 'reload') then
        build_spell_map();
        refresh_job();
        msg(('Spell map rebuilt (%d spells). BLU: %s'):fmt(state.spell_by_name:length(), tostring(state.is_blu)));
    else
        msg('/blualert test    - test unknown-spell alert');
        msg('/blualert learn   - test learned-spell alert');
        msg('/blualert status  - show BLU detection');
        msg('/blualert reload  - rebuild spell name map');
    end
end);
