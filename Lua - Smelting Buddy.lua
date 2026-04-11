-- Smelting Buddy - Your buddy to help you smelt with ease
-- Fully automatic smelting process - Select ingot type, select amount and press start
-- Supports fully integrated batch crafting mode
-- Vent automation and failsafe system for the furnace to prevent explosions or autoignite
-- Uses silos for ore storage and retrieval and vending machines to store ingots for easy retrieval

-- ==================== SURFACES & VIEW ====================

local surfaces = {
    overview = ss.ui.surface("overview"),
    settings = ss.ui.surface("settings"),
    batch = ss.ui.surface("batch"),
}
local s = surfaces.overview
local view = "overview"

local W, H = 480, 272
local size = ss.ui.surface("overview"):size()
if size then
    W = size.w or W
    H = size.h or H
end

local elapsed = 0
local currenttime = 0
local currenttime2 = 0
local LIVE_REFRESH_TICKS = 4
local MIN_LIVE_REFRESH_TICKS = 4

local handles = {
    view = nil,
    header = {},
    nav = {},
    footer = {},
    overview = {},
    settings = {},
    batch = {},
}

-- ==================== CONSTANTS ====================

local LT = ic.enums.LogicType
local LBM = ic.enums.LogicBatchMethod
local hash = ic.hash
local batch_read_name = ic.batch_read_name
local batch_write_name = ic.batch_write_name
local batch_write = ic.batch_write
local LST = ic.enums.LogicSlotType
local batch_read_slot_name = ic.batch_read_slot_name
local roles
local requested_recipe
local recipe_window
local _recipe_win_cache_key = -1
local _recipe_win_cache = {}

local PREFABS = {
    logic_sorter = hash("StructureLogicSorter"),
    logic_sorter_mirrored = hash("StructureLogicSorterMirrored"),
    gas_pa = hash("StructurePipeAnalysizer"),
    liquid_pa = hash("StructureLiquidPipeAnalyzer"),
    vent = hash("StructureActiveVent"),
    pump = hash("StructureVolumePump"),
    pump_mirrored = hash("StructureVolumePumpMirrored"),
    gas_mixer = hash("StructureGasMixer"),
    gas_sensor = hash("StructureGasSensor"),
    silo = hash("StructureSDBSilo"),
    furnace = hash("StructureAdvancedFurnace"),
    furnace_mirrored = hash("StructureAdvancedFurnaceMirrored"),
    vend = hash("StructureVendingMachine"),
    vend_fridge = hash("StructureRefrigeratedVendingMachine"),
    stackers = hash("StructureStacker"),
    stackersmirror = hash("StructureStackerReverse"),
    sorter = hash("StructureSorter"),
    sorter2 = hash("StructureSorterMirrored"),
}

local PA_PREFABS = { PREFABS.gas_pa, PREFABS.liquid_pa }
local VENT_PREFABS = { PREFABS.vent }
local PUMP_PREFABS = { PREFABS.pump, PREFABS.pump_mirrored }
local MIXER_PREFABS = { PREFABS.gas_mixer }
local GAS_SENSOR_PREFABS = { PREFABS.gas_sensor }
local SILO_PREFABS = { PREFABS.silo }
local FURNACE_PREFABS = { PREFABS.furnace, PREFABS.furnace_mirrored }
local VEND_PREFABS = { PREFABS.vend, PREFABS.vend_fridge }
local LOGIC_SORTER_PREFABS = { PREFABS.logic_sorter, PREFABS.logic_sorter_mirrored }
local OTHER_PREFABS = { PREFABS.sorter, PREFABS.stackers, PREFABS.sorter2, PREFABS.stackersmirror }
local ORE_STACK_SIZE = 50

local C = {
    bg = "#0A0E1A",
    header = "#0C1220",
    panel = "#0F1628",
    panel_light = "#151D30",
    text = "#E2E8F0",
    text_dim = "#64748B",
    text_muted = "#475569",
    accent = "#38BDF8",
    green = "#22C55E",
    yellow = "#EAB308",
    orange = "#F97316",
    red = "#EF4444",
    light_blue = "#38BDF8",
    blue = "#1D4ED8",
    dark_red = "#7F1D1D",
    bar_bg = "#1F2937",
    title = "#0a71d8ff",
}

function pressure_color(v)
    if v == nil then return C.text end
    if v < 100 then return C.red end
    if v < 200 then return C.orange end
    if v < 400 then return C.yellow end
    return C.green
end

-- ==================== MEMORY MAP ====================

local MEM_DEVICE_BEGIN = 0
local MEM_CONTROL_BEGIN = 80

local MEM_MAX_TEMP_HARD = MEM_CONTROL_BEGIN + 4
local MEM_LIVE_REFRESH = MEM_CONTROL_BEGIN + 5
local MEM_BATCH_RUNNING = MEM_CONTROL_BEGIN + 6
local MEM_POWER_TOGGLE = MEM_CONTROL_BEGIN + 7
local MEM_POWER_TARGET = MEM_CONTROL_BEGIN + 8
local MEM_GAS_MIX = MEM_CONTROL_BEGIN + 9
local MEM_GAS_MIX_MOLE = MEM_CONTROL_BEGIN + 10

local MEM_QUEUE_COUNT = 100
local MEM_QUEUE_START = 101

local GAS_MIX_OPTIONS = {
    { label = "O2 / CH4",  setting = 33.3, oxidiser_lt = LT.RatioOxygen,       fuel_lt = LT.RatioVolatiles },
    { label = "O2 / H2",   setting = 33.3, oxidiser_lt = LT.RatioOxygen,       fuel_lt = LT.RatioHydrogen  },
    { label = "N2O / CH4", setting = 50.0, oxidiser_lt = LT.RatioNitrousOxide, fuel_lt = LT.RatioVolatiles },
    { label = "N2O / H2",  setting = 50.0, oxidiser_lt = LT.RatioNitrousOxide, fuel_lt = LT.RatioHydrogen  },
    { label = "O3 / CH4",  setting = 40.0, oxidiser_lt = LT.RatioOzone,        fuel_lt = LT.RatioVolatiles },
    { label = "O3 / H2",   setting = 25.0, oxidiser_lt = LT.RatioOzone,        fuel_lt = LT.RatioHydrogen  },
}

-- =============== Logs & util functions ===============
local DEBUG_LOG_ENABLED = false
local DEBUG_LOG_UI = false
local debug_seq = 0
local gt, gtH, gtM, gtS = 0, 0, 0, 0

function time()
    gt = util.game_time() or 0
    gtH = math.floor(gt / 3600)
    gtM = math.floor((gt % 3600) / 60)
    gtS = math.floor((gt % 3600) % 60)
    return gtH, gtM, gtS
end

function log_action(message)
    if not DEBUG_LOG_ENABLED then return end
    time()
    debug_seq = debug_seq + 1
    print("[SmeltingBuddy] #" .. tostring(debug_seq) .. " H" .. gtH .. " : M" .. gtM .. " : S" .. gtS .. " | " .. tostring(message))
end

function log_step(message)
    log_action("[STEP] " .. tostring(message))
end

function log_ui(message)
    if not DEBUG_LOG_UI then return end
    log_action("[UI] " .. tostring(message))
end

function safe_call(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        log_action("[ERROR] " .. tostring(label) .. " | " .. tostring(err))
    end
    return ok
end

-- ==================== HELPERS ====================

function write(address, value)
    mem_write(address, value)
end

function read(address)
    return mem_read(address) or 0
end

function fmt(v, d)
    if v == nil then return "--" end
    return string.format("%." .. tostring(d or 1) .. "f", v)
end

function kelvin_to_celsius(v)
    if v == nil then return nil end
    return v - 273.15
end

function room_pressure_color(v)
    if v == nil then return C.text end
    if v <= 15000 then return C.green end
    if v <= 30000 then return C.yellow end
    if v <= 40000 then return C.orange end
    return C.red
end

function room_temp_color(v)
    local c = kelvin_to_celsius(v)
    if c == nil then return C.text end
    if c > 60 then return C.red end
    if c >= 40 then return C.orange end
    if c >= 30 then return C.yellow end
    if c >= 10 then return C.light_blue end
    return C.blue
end

local function room_temp_text(v)
    return fmt(kelvin_to_celsius(v), 1) .. " C"
end

local function stock_amount_color(v)
    if v == nil then return C.text_dim end
    if v < 200 then return C.red end
    if v < 500 then return C.orange end
    if v < 1000 then return C.yellow end
    return C.green
end

local function vend_free_slots_color(v)
    if v == nil then return C.text_dim end
    if v < 20 then return C.red end
    if v < 40 then return C.orange end
    if v < 60 then return C.yellow end
    return C.green
end

local function selected_recipe_window()
    local recipe_index = tonumber(requested_recipe) or 0
    if recipe_index <= 0 or type(recipe_window) ~= "function" then
        return nil
    end
    if _recipe_win_cache_key == recipe_index then
        return _recipe_win_cache[1], _recipe_win_cache[2], _recipe_win_cache[3], _recipe_win_cache[4]
    end
    local ok, t_min, t_max, p_min, p_max = pcall(recipe_window, recipe_index)
    if not ok then
        log_action("[ERROR] recipe_window lookup failed | " .. tostring(t_min))
        return nil
    end
    _recipe_win_cache_key = recipe_index
    _recipe_win_cache = { t_min, t_max, p_min, p_max }
    return t_min, t_max, p_min, p_max
end

local function furnace_pressure_color(v)
    if v == nil then return C.text end
    local _, _, p_min, p_max = selected_recipe_window()
    if p_min == nil or p_max == nil then return C.text end
    if v < p_min or v > p_max then return C.red end
    return C.green
end

local function furnace_temp_color(v)
    if v == nil then return C.text end
    local t_min, t_max = selected_recipe_window()
    if t_min == nil or t_max == nil then return C.text end
    if v < t_min or v > t_max then return C.red end
    return C.green
end

local function furnace_temp_text(v)
    return fmt(kelvin_to_celsius(v), 1) .. " C"
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function to_number_or(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function safe_batch_read_name(prefab, namehash, logic_type, method)
    if batch_read_name == nil then return nil end
    local p = tonumber(prefab) or 0
    local n = tonumber(namehash) or 0
    if p == 0 or n == 0 then return nil end
    local ok, value = pcall(batch_read_name, p, n, logic_type, method)
    if not ok then return nil end
    return value
end

local function safe_batch_write_name(prefab, namehash, logic_type, value)
    if batch_write_name == nil then return false end
    local p = tonumber(prefab) or 0
    local n = tonumber(namehash) or 0
    if p == 0 or n == 0 then return false end
    local ok = pcall(batch_write_name, p, n, logic_type, value)
    return ok
end

local function safe_batch_write_prefab(prefab, logic_type, value)
    if batch_write == nil then return false end
    local p = tonumber(prefab) or 0
    if p == 0 then return false end
    local ok = pcall(batch_write, p, logic_type, value)
    return ok
end

local function resolve_name_hash(namehash)
    local n = tonumber(namehash) or 0
    if n == 0 then return "Unassigned" end
    local ok, resolved = pcall(namehash_name, n)
    if not ok or resolved == nil then
        return "#" .. tostring(n)
    end
    return tostring(resolved)
end

local function device_list_safe()
    local ok, devices = pcall(device_list)
    if not ok or type(devices) ~= "table" then return {} end
    return devices
end

local function bool01(v)
    return (tonumber(v) or 0) > 0 and 1 or 0
end

local function logic_or_zero(role, logic_type)
    return safe_batch_read_name(role.prefab, role.namehash, logic_type, LBM.Average) or 0
end

local function role_is_bound(role)
    if role == nil then return false end
    return (tonumber(role.prefab) or 0) ~= 0 and (tonumber(role.namehash) or 0) ~= 0
end

local function roles_are_bound(keys)
    for _, key in ipairs(keys) do
        if not role_is_bound(roles[key]) then
            return false
        end
    end
    return true
end

local function device_matches_prefabs(dev, allowed_prefabs)
    if allowed_prefabs == nil then
        return true
    end

    local prefab_hash = tonumber(dev and dev.prefab_hash) or 0
    for _, allowed in ipairs(allowed_prefabs) do
        if prefab_hash == allowed then
            return true
        end
    end

    return false
end

-- ==================== DEVICE ROLE MODEL ====================

local role_defs = {
    { key = "furnace", label = "Furnace", default_name = "Furnace", slot = 1, allowed_prefabs = FURNACE_PREFABS },
    { key = "fuel_pa", label = "PA - Fuel", default_name = "PA - Fuel", slot = 2, allowed_prefabs = PA_PREFABS },
    { key = "coolant_pa", label = "PA - Coolant", default_name = "PA - Coolant", slot = 3, allowed_prefabs = PA_PREFABS },
    { key = "o2_pa", label = "PA - O2 Analyzer", default_name = "PA - O2 Analyzer", slot = 4, allowed_prefabs = PA_PREFABS },
    { key = "ch4_pa", label = "PA - CH4 Analyzer", default_name = "PA - CH4 Analyzer", slot = 5, allowed_prefabs = PA_PREFABS },
    { key = "fuel_mixer", label = "Fuel Mixer", default_name = "Fuel Mixer", slot = 6, allowed_prefabs = MIXER_PREFABS },
    { key = "fuel_pump", label = "Pump - Fuel", default_name = "Pump - Fuel", slot = 7, allowed_prefabs = PUMP_PREFABS },
    { key = "coolant_pump", label = "Pump - Coolant", default_name = "Pump - Coolant", slot = 8, allowed_prefabs = PUMP_PREFABS },
    { key = "vent_1", label = "Vent 1 - In", default_name = "Vent 1 - In", slot = 12, allowed_prefabs = VENT_PREFABS },
    { key = "vent_2_out", label = "Vent 2 - Out", default_name = "Vent 2 - Out", slot = 13, allowed_prefabs = VENT_PREFABS },
    { key = "room_sensor", label = "Room Sensor", default_name = "Room Sensor", slot = 14, allowed_prefabs = GAS_SENSOR_PREFABS },
    { key = "silo_iron", label = "Iron Silo", default_name = "Iron Silo", slot = 24, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_copper", label = "Copper Silo", default_name = "Copper Silo", slot = 25, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_gold", label = "Gold Silo", default_name = "Gold Silo", slot = 26, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_silicon", label = "Silicon Silo", default_name = "Silicon Silo", slot = 27, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_silver", label = "Silver Silo", default_name = "Silver Silo", slot = 28, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_lead", label = "Lead Silo", default_name = "Lead Silo", slot = 29, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_nickel", label = "Nickel Silo", default_name = "Nickel Silo", slot = 30, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_coal", label = "Coal Silo", default_name = "Coal Silo", slot = 31, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_cobalt", label = "Cobalt Silo", default_name = "Cobalt Silo", slot = 32, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "silo_steel", label = "Steel Silo", default_name = "Steel Silo", slot = 33, allowed_prefabs = SILO_PREFABS, is_batch = true },
    { key = "vend_normal", label = "Vending Normal", default_name = "Vending Normal", slot = 34, allowed_prefabs = VEND_PREFABS },
    { key = "vend_alloy",  label = "Vending Special",  default_name = "Vending Special",  slot = 35, allowed_prefabs = VEND_PREFABS },
    { key = "chute_valve", label = "Logic Sorter", default_name = "Logic Sorter", slot = 36, allowed_prefabs = LOGIC_SORTER_PREFABS },
}


roles = {}
local settings_dropdown_selected = {}
local settings_dropdown_open = {}
local cached_role_dropdowns = {}

for i, def in ipairs(role_defs) do
    roles[def.key] = {
        index = i,
        key = def.key,
        label = def.label,
        default_name = def.default_name,
        slot = def.slot,
        allowed_prefabs = def.allowed_prefabs,
        is_batch = def.is_batch or false
    }
    settings_dropdown_selected[def.key] = 0
    settings_dropdown_open[def.key] = "false"
end

local function load_roles_from_memory()
    log_step("load_roles_from_memory: begin")
    local summary = {}
    for _, def in ipairs(role_defs) do
        local role = roles[def.key]
        local slot = tonumber(role.slot) or role.index
        local base = MEM_DEVICE_BEGIN + (slot - 1) * 2
        role.prefab = tonumber(read(base)) or 0
        role.namehash = tonumber(read(base + 1)) or 0
        if role_is_bound(role) then
            log_step(string.format("role loaded: %s prefab=%s namehash=%s", role.key, tostring(role.prefab), tostring(role.namehash)))
        else
            log_step("role loaded unassigned: " .. tostring(role.key))
        end
        table.insert(summary, string.format("%s:[%s,%s]", role.key, tostring(role.prefab), tostring(role.namehash)))
    end
    print("[SmeltingBuddy] Role summary: " .. table.concat(summary, "; "))
end

local function save_role_to_memory(role)
    local slot = tonumber(role.slot) or role.index
    local base = MEM_DEVICE_BEGIN + (slot - 1) * 2
    write(base, tonumber(role.prefab) or 0)
    write(base + 1, tonumber(role.namehash) or 0)
    log_step(string.format("save_role_to_memory: %s prefab=%s namehash=%s", tostring(role.key), tostring(role.prefab), tostring(role.namehash)))
end

-- ==================== CONTROL STATE ====================

local settings_subtab = "flow"
local settings_device_page = 1
local gas_mix_index = 1
local gas_mix_dropdown_open = "false"
local gas_mix_mole_based = false

local max_temp_hard = 2500

local ui_max_temp_hard = tostring(max_temp_hard)
local ui_live_refresh = tostring(LIVE_REFRESH_TICKS)

local global_power_on = true
local power_target_all = true

requested_recipe = 0
local requested_amount = 0
local requested_hash = 0
local furnace_run_active = false
local furnace_start_tick = 0
local has_seen_reagents = false
local recipe_ready = false
local stock_ok = false
local vent_enabled = false
local last_vent_enabled = false
local vent_pulse_state = 0
local vent_pulse_start = 0
local is_recovery_active = false
local recovery_timer = 0
local recovery_phase = 0
local recovery_last_reagents = 0
local lever_pulse_remaining = 0
local lever_pulse_timer = 0
local waiting_for_export_clear = 0
local furnace_stuck_ticks = 0
local last_activity_reagents = 0
local last_activity_import = 0
local last_activity_export = 0
local flush_enabled = false
local status_text = "Idle"
local status_color = C.text_dim
local selected_ingot_index = 1
local last_status_text = ""
local furnace_ignition_ticks = 0

local MIN_BATCH_AMOUNT = 1
local MAX_BATCH_AMOUNT = 50
local FUEL_MIXER_CHECK_TICKS = 30


local fuel_mixer_fill_active = false
local batch_wait_finish = false

local smelting_queue = {}
local is_batch_running = false
local batch_selected_ingot_index = 1
local batch_requested_amount = 1

local silo_request = {
    active = false,
    items = {},
    item_index = 1,
    phase = 0,
    qty_before = 0,
}

local readings = {
    furnace_temp = nil,
    furnace_press = nil,
    furnace_reagents = nil,
    furnace_recipe_hash = nil,
    furnace_open = nil,
    furnace_export_count = nil,
    furnace_import_count = nil,
    fuel_pa_press = nil,
    fuel_pa_temp = nil,
    fuel_pa_moles = nil,
    fuel_pa_vol = nil,
    coolant_pa_press = nil,
    coolant_pa_temp = nil,
    coolant_pa_moles = nil,
    coolant_pa_vol = nil,
    room_press = nil,
    room_temp = nil,
    o2_pa_press = nil,
    ch4_pa_press = nil,
    vend_normal_free = nil,
    vend_alloy_free = nil,
    vend_ingot_totals = {},
}

local ingots = {
    { "Iron Ingot",       ss.ui.icons.prefab.IronIngot, 1 },
    { "Steel Ingot",      ss.ui.icons.prefab.SteelIngot, 8 },
    { "Copper Ingot",     ss.ui.icons.prefab.CopperIngot, 2 },
    { "Gold Ingot",       ss.ui.icons.prefab.GoldIngot, 3 },
    { "Silver Ingot",     ss.ui.icons.prefab.SilverIngot, 5 },
    { "Nickel Ingot",     ss.ui.icons.prefab.NickelIngot, 7 },
    { "Lead Ingot",       ss.ui.icons.prefab.LeadIngot, 6 },
    { "Silicon Ingot",    ss.ui.icons.prefab.SiliconIngot, 4 },
    { "Electrum Ingot",   ss.ui.icons.prefab.ElectrumIngot, 11 },
    { "Solder Ingot",     ss.ui.icons.prefab.SolderIngot, 10 },
    { "Constantan Ingot", ss.ui.icons.prefab.ConstantanIngot, 12 },
    { "Invar Ingot",      ss.ui.icons.prefab.InvarIngot, 9 },
    { "Astroloy Ingot",   ss.ui.icons.prefab.AstroloyIngot, 15 },
    { "Hastelloy Ingot",  ss.ui.icons.prefab.HastelloyIngot, 16 },
    { "Waspaloy Ingot",   ss.ui.icons.prefab.WaspaloyIngot, 13 },
    { "Inconel Ingot",    ss.ui.icons.prefab.InconelIngot, 14 },
    { "Stellite Ingot",   -1897868623, 17 }, --using hash since the ss.icons didn't work?
}

local totalIngots = #ingots
local recipe_hashes = {
    [1] = -1301215609,
    [2] = -404336834,
    [3] = 226410516,
    [4] = -290196476,
    [5] = -929742000,
    [6] = 2134647745,
    [7] = -1406385572,
    [8] = -654790771,
    [9] = -297990285,
    [10] = -82508479,
    [11] = 502280180,
    [12] = 1058547521,
    [13] = 156348098,
    [14] = -787796599,
    [15] = 412924554,
    [16] = 1579842814,
    [17] = -1897868623,
}

local recipe_names = {
    [1] = "Iron",
    [2] = "Copper",
    [3] = "Gold",
    [4] = "Silicon",
    [5] = "Silver",
    [6] = "Lead",
    [7] = "Nickel",
    [8] = "Steel",
    [9] = "Invar",
    [10] = "Solder",
    [11] = "Electrum",
    [12] = "Constantan",
    [13] = "Waspaloy",
    [14] = "Inconel",
    [15] = "Astroloy",
    [16] = "Hastelloy",
    [17] = "Stellite",
}

local silo_role_by_material = {
    Iron = "silo_iron",
    Copper = "silo_copper",
    Gold = "silo_gold",
    Silicon = "silo_silicon",
    Silver = "silo_silver",
    Lead = "silo_lead",
    Nickel = "silo_nickel",
    Coal = "silo_coal",
    Cobalt = "silo_cobalt",
    Steel = "silo_steel",
}

local MATERIAL_ORDER = { "Iron", "Copper", "Gold", "Silicon", "Silver", "Lead", "Nickel", "Coal", "Cobalt", "Steel" }


local SILO_HANDLE_KEY = {}
for _, mat in ipairs(MATERIAL_ORDER) do
    SILO_HANDLE_KEY[mat] = "ov_silo_" .. string.lower(mat)
end

local recipe_has_stock

local settings_subtab_groups = {
    flow = {
        "fuel_pa",
        "coolant_pa",
        "o2_pa",
        "ch4_pa",
        "furnace",
        "fuel_pump",
        "coolant_pump",
        "fuel_mixer",
        "vent_1",
        "vent_2_out",
        "room_sensor",
        "vend_normal",
        "vend_alloy",
        "chute_valve",
    },
    silos = {
        "silo_iron",
        "silo_copper",
        "silo_gold",
        "silo_silicon",
        "silo_silver",
        "silo_lead",
        "silo_nickel",
        "silo_coal",
        "silo_cobalt",
        "silo_steel",
    },
}

local recipe_requirements = {
    [1] = { Iron = 1 },
    [2] = { Copper = 1 },
    [3] = { Gold = 1 },
    [4] = { Silicon = 1 },
    [5] = { Silver = 1 },
    [6] = { Lead = 1 },
    [7] = { Nickel = 1 },
    [8] = { Iron = 3, Coal = 1 }, 
    [9] = { Iron = 0.5, Nickel = 0.5 },  
    [10] = { Iron = 0.5, Lead = 0.5 },  
    [11] = { Gold = 0.5, Silver = 0.5 }, 
    [12] = { Copper = 0.5, Nickel = 0.5 }, 
    [13] = { Nickel = 1, Silver = 1, Lead = 2 }, 
    [14] = { Gold = 2, Steel = 1, Nickel = 1 },  
    [15] = { Copper = 1, Cobalt = 1, Steel = 2 }, 
    [16] = { Silver = 2, Nickel = 1, Cobalt = 1 },
    [17] = { Silicon = 2, Cobalt = 1, Silver = 1 },
}

local recipe_windows = {
    [1] = { t_min = 800,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Iron
    [2] = { t_min = 600,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Copper
    [3] = { t_min = 600,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Gold
    [4] = { t_min = 900,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Silicon
    [5] = { t_min = 600,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Silver
    [6] = { t_min = 400,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Lead
    [7] = { t_min = 800,  t_max = 100000, p_min = 100,   p_max = 100000 }, -- Nickel
    [8] = { t_min = 900,  t_max = 100000, p_min = 1000,  p_max = 100000 }, -- Steel
    [9] = { t_min = 1200, t_max = 1500,   p_min = 18000, p_max = 20000  }, -- Invar
    [10] = { t_min = 350, t_max = 550,    p_min = 1000,  p_max = 100000 }, -- Solder
    [11] = { t_min = 600, t_max = 100000, p_min = 800,   p_max = 2400   }, -- Electrum
    [12] = { t_min = 1000,t_max = 100000, p_min = 20000, p_max = 100000 }, -- Constantan
    [13] = { t_min = 400, t_max = 800,    p_min = 50000, p_max = 100000 }, -- Waspaloy
    [14] = { t_min = 600, t_max = 100000, p_min = 23500, p_max = 24000  }, -- Inconel
    [15] = { t_min = 1000,t_max = 100000, p_min = 30000, p_max = 40000  }, -- Astroloy
    [16] = { t_min = 950, t_max = 1000,   p_min = 25000, p_max = 30000  }, -- Hastelloy
    [17] = { t_min = 1800,t_max = 100000, p_min = 10000, p_max = 20000  }, -- Stellite
}

recipe_window = function(recipe_index)
    local win = recipe_windows[recipe_index]
    if win ~= nil then
        return win.t_min, win.t_max, win.p_min, win.p_max
    end
    return 600, 100000, 100, 100000
end

local function recipe_amount_scale(recipe_id)
    if recipe_id <= 0 then return 0 end
    if recipe_id <= 7 then return 50 end
    if recipe_id == 8 then return 200 end
    if recipe_id >= 13 then return 50 end 
    if recipe_id >= 9 then return 100 end
    return 50
end

local function recipe_target_reagents(recipe_id, amount)

    local req = recipe_requirements[recipe_id]
     if not req then return amount * 50 end
    local sum = 0
    for _, count in pairs(req) do
        sum = sum + count
    end
    return amount * sum * 50
end

local function selected_ingot_entry()
    return ingots[selected_ingot_index] or ingots[1]
end

function sync_selected_recipe()
    local entry = selected_ingot_entry()
    requested_recipe = tonumber(entry and entry[3]) or 1
    requested_hash = recipe_hashes[requested_recipe] or 0
    requested_amount = clamp(math.floor(to_number_or(requested_amount, 1)), MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
end

local function selected_output_amount()
    return requested_amount * recipe_amount_scale(requested_recipe)
end

local function materials_preview_title()
    if requested_recipe <= 0 then
        return "Materials Required"
    end
    return string.format("Materials for %d Ingots", selected_output_amount())
end

local function selected_recipe_has_stock()
    if requested_recipe <= 0 then
        return false
    end
    return recipe_has_stock(requested_recipe, requested_amount)
end

local function selected_recipe_can_start()
    if requested_recipe <= 0 then
        return false
    end
    return selected_recipe_has_stock()
end

local function material_preview_lines(recipe_index, amount)
    local req = recipe_requirements[recipe_index]
    if req == nil then
        return { "No recipe selected", "", "" }
    end

    local scaled_amount = amount * recipe_amount_scale(recipe_index)

    local parts = {}
    for _, material in ipairs(MATERIAL_ORDER) do
        local count = req[material]
        if count ~= nil and count > 0 then
            local display_qty = count * scaled_amount
            if recipe_index == 8 then
                display_qty = display_qty / 4
            end
            table.insert(parts, string.format("%s x%d", material, display_qty))
        end
    end

    local lines = { "", "", "" }
    if #parts == 0 then
        lines[1] = "No materials required"
        return lines
    end

    if #parts == 1 then
        lines[1] = parts[1]
        return lines
    end

    if #parts == 2 then
        lines[1] = parts[1]
        lines[2] = parts[2]
        return lines
    end

    lines[1] = parts[1] .. " | " .. parts[2]
    lines[2] = parts[3]
    return lines
end

local function current_settings_roles()
    local keys = settings_subtab_groups[settings_subtab] or settings_subtab_groups.other
    local items = {}

    for _, key in ipairs(keys) do
        local role = roles[key]
        if role ~= nil then
            table.insert(items, role)
        end
    end

    return items
end

local function normalize_settings_subtab()
    if settings_subtab == "pas" or settings_subtab == "other" then
        settings_subtab = "flow"
        return
    end

    if settings_subtab ~= "flow"
        and settings_subtab ~= "silos"
        and settings_subtab ~= "control" then
        settings_subtab = "flow"
    end
end

-- ==================== LOGIC SORTER CONTROL ====================
local STEEL_HASH = ic.hash("ItemSteelIngot")
local SORTER_STEEL_INSTRUCTION = (STEEL_HASH * 256) + 1  -- Shift left 8 equals * 2^8 (256). OR 1 equals + 1.

local function set_chute_valve_open(output_to_vend)
    local role = roles.chute_valve
    if not role_is_bound(role) then return end

    local device_id = safe_batch_read_name(role.prefab, role.namehash, LT.ReferenceId, LBM.Average)

    if output_to_vend then
        safe_batch_write_name(role.prefab, role.namehash, LT.Mode, 0)
        safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
        
        if device_id ~= nil and device_id > 0 and mem_put_id ~= nil then
            pcall(mem_put_id, device_id, 0, 0)
        end
        log_action("Logic Sorter: Mode 0 (Vend - pass all, filter cleared)")
    else
        safe_batch_write_name(role.prefab, role.namehash, LT.Mode, 0)
        safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)

        if device_id ~= nil and device_id > 0 then
            if mem_put_id ~= nil then
                pcall(mem_put_id, device_id, 0, SORTER_STEEL_INSTRUCTION)
                log_action("Logic Sorter: Mode 1 (Silo - steel filter via mem_put_id reference=" .. tostring(device_id) .. ")")
            else
                log_action("[WARN] Logic Sorter: mem_put_id missing, cannot write filter")
            end
        else
            log_action("[WARN] Logic Sorter: failed to read ReferenceId, filter not written")
        end
    end
end

local function render_chute_valve_buttons(surface, x, y)
    local w, h = 80, 32
    surface:button({
        x = x, y = y, w = w, h = h,
        label = "Open 1",
        on_click = function()
            set_chute_valve_open(true)
        end
    })
    surface:button({
        x = x + w + 8, y = y, w = w, h = h,
        label = "Open 0",
        on_click = function()
            set_chute_valve_open(false)
        end
    })
end

local function ore_needed_for_material(recipe_index, count_per, amount)
    local scale = recipe_amount_scale(recipe_index)
    if recipe_index == 8 then scale = scale / 4 end
    return count_per * amount * scale
end

local function build_silo_request_items(recipe_index, amount)
    local items = {}
    local req = recipe_requirements[recipe_index]

    if req == nil then
        return items
    end

    for _, material in ipairs(MATERIAL_ORDER) do
        local count = req[material]
        if count ~= nil and count > 0 then
            local role_key = silo_role_by_material[material]
            if role_key ~= nil then
                local ore = ore_needed_for_material(recipe_index, count, amount)
                local stacks = math.ceil(ore / ORE_STACK_SIZE)
                table.insert(items, {
                    material = material,
                    role_key = role_key,
                    remaining = stacks,
                })
            end
        end
    end

    return items
end

local function queue_silo_requests(recipe_index, amount)
    log_step(string.format("queue_silo_requests: recipe=%s amount=%s", tostring(recipe_index), tostring(amount)))
    silo_request.active = true
    silo_request.items = build_silo_request_items(recipe_index, amount)
    silo_request.item_index = 1
    silo_request.phase = 0

    if #silo_request.items == 0 then
        silo_request.active = false
        log_step("queue_silo_requests: no items queued")
    else
        log_step("queue_silo_requests: queued items=" .. tostring(#silo_request.items))
    end
end

local function process_silo_request_tick()
    if not silo_request.active then
        return
    end

    log_step("process_silo_request_tick: active index=" .. tostring(silo_request.item_index) .. " phase=" .. tostring(silo_request.phase))

    local current = silo_request.items[silo_request.item_index]
    while current ~= nil and (tonumber(current.remaining) or 0) <= 0 do
        silo_request.item_index = silo_request.item_index + 1
        current = silo_request.items[silo_request.item_index]
    end

    if current == nil then
        silo_request.active = false
        silo_request.phase = 0
        log_step("process_silo_request_tick: complete")
        return
    end

    local role = roles[current.role_key]
    if role == nil then
        current.remaining = 0
        log_step("process_silo_request_tick: missing role " .. tostring(current.role_key))
        return
    end

    if silo_request.phase == 0 then
        silo_request.qty_before = logic_or_zero(role, LT.Quantity)
        log_step("process_silo_request_tick: open silo " .. tostring(current.role_key) .. " qty_before=" .. tostring(silo_request.qty_before))
        safe_batch_write_name(role.prefab, role.namehash, LT.ClearMemory, 1)
        safe_batch_write_name(role.prefab, role.namehash, LT.Open, 1)
        silo_request.phase = 1
    else
        log_step("process_silo_request_tick: close silo " .. tostring(current.role_key))
        safe_batch_write_name(role.prefab, role.namehash, LT.Open, 0)
        local qty_after = logic_or_zero(role, LT.Quantity)
        if qty_after < silo_request.qty_before then
            current.remaining = (tonumber(current.remaining) or 0) - 1
            log_step("process_silo_request_tick: stack confirmed qty " .. tostring(silo_request.qty_before) .. "->" .. tostring(qty_after) .. " remaining=" .. tostring(current.remaining))
        else
            log_step("[WARN] process_silo_request_tick: no stack dispensed for " .. tostring(current.role_key) .. " qty_before=" .. tostring(silo_request.qty_before) .. " qty_after=" .. tostring(qty_after) .. ", skipping")
            current.remaining = 0
        end
        silo_request.phase = 0
    end
end

local function start_selected_recipe()
    log_step("start_selected_recipe: begin")
    sync_selected_recipe()
    log_step(string.format("start_selected_recipe: recipe=%s amount=%s hash=%s", tostring(requested_recipe), tostring(requested_amount), tostring(requested_hash)))

    if not roles_are_bound({ "furnace", "fuel_pump", "coolant_pump", "fuel_mixer" }) then
        furnace_run_active = false
        recipe_ready = false
        log_step("start_selected_recipe: blocked missing required bindings")
        return false
    end

    stock_ok = recipe_has_stock(requested_recipe, requested_amount)
    if not stock_ok then
        furnace_run_active = false
        recipe_ready = false
        log_step("start_selected_recipe: blocked missing stock")
        return false
    end

    furnace_run_active = true
    furnace_start_tick = currenttime
    furnace_ignition_ticks = 25
    has_seen_reagents = false
    recipe_ready = false
    queue_silo_requests(requested_recipe, requested_amount)
    log_step("start_selected_recipe: started")

    return true
end

local function validate_control_settings()
    max_temp_hard = clamp(to_number_or(max_temp_hard, 600), 100, 2000)
    LIVE_REFRESH_TICKS = clamp(math.floor(to_number_or(LIVE_REFRESH_TICKS, MIN_LIVE_REFRESH_TICKS)), MIN_LIVE_REFRESH_TICKS, 60)

    ui_max_temp_hard = tostring(math.floor(max_temp_hard))
    ui_live_refresh = tostring(math.floor(LIVE_REFRESH_TICKS))
end

local function save_control_settings()
    validate_control_settings()
    write(MEM_MAX_TEMP_HARD, max_temp_hard)
    write(MEM_LIVE_REFRESH, LIVE_REFRESH_TICKS)
    write(MEM_BATCH_RUNNING, is_batch_running and 1 or 0)
    write(MEM_POWER_TOGGLE, global_power_on and 2 or 1)
    write(MEM_POWER_TARGET, power_target_all and 1 or 0)
    write(MEM_GAS_MIX, gas_mix_index)
    write(MEM_GAS_MIX_MOLE, gas_mix_mole_based and 1 or 0)
    log_step(string.format("save_control_settings: max_temp_hard=%s refresh_ticks=%s power=%s target_all=%s gas_mix=%s mole=%s", 
        tostring(max_temp_hard), tostring(LIVE_REFRESH_TICKS), tostring(global_power_on), tostring(power_target_all), tostring(gas_mix_index), tostring(gas_mix_mole_based)))
end

local function load_control_settings()
    max_temp_hard = to_number_or(read(MEM_MAX_TEMP_HARD), max_temp_hard)
    LIVE_REFRESH_TICKS = to_number_or(read(MEM_LIVE_REFRESH), MIN_LIVE_REFRESH_TICKS)
    is_batch_running = (read(MEM_BATCH_RUNNING) == 1)
    
    local pval = tonumber(read(MEM_POWER_TOGGLE)) or 0
    if pval > 0 then global_power_on = (pval == 2) end
    
    local tval = tonumber(read(MEM_POWER_TARGET)) or 1
    power_target_all = (tval == 1)

    local gval = tonumber(read(MEM_GAS_MIX)) or 1
    gas_mix_index = clamp(math.floor(gval), 1, #GAS_MIX_OPTIONS)

    local mval = tonumber(read(MEM_GAS_MIX_MOLE)) or 1
    gas_mix_mole_based = (mval == 1)

    save_control_settings()
    log_step(string.format("load_control_settings: max_temp_hard=%s refresh_ticks=%s power=%s target_all=%s gas_mix=%s mole=%s", 
        tostring(max_temp_hard), tostring(LIVE_REFRESH_TICKS), tostring(global_power_on), tostring(power_target_all), tostring(gas_mix_index), tostring(gas_mix_mole_based)))
end

-- ==================== DEVICE LIST HELPERS ====================

local function build_filtered_device_options(devices, current_role)
    local options = { "Select device..." }
    local candidates = {}
    local selected = 0

    for i, dev in ipairs(devices) do
        if device_matches_prefabs(dev, current_role.allowed_prefabs) then
            local label = tostring((dev and dev.display_name) or ("Device " .. i))
            label = label:gsub("|", "/")
            table.insert(options, label)
            table.insert(candidates, dev)

            local prefab_hash = tonumber(dev and dev.prefab_hash) or 0
            local name_hash = tonumber(dev and dev.name_hash) or 0
            if (tonumber(current_role.prefab) or 0) ~= 0
                and (tonumber(current_role.namehash) or 0) ~= 0
                and prefab_hash == (tonumber(current_role.prefab) or 0)
                and name_hash == (tonumber(current_role.namehash) or 0) then
                selected = #candidates
            end
        end
    end

    if #candidates == 0 then
        options[1] = "No devices found"
    end

    return options, candidates, selected
end

-- ==================== CORE LOGIC ====================

local function update_readings()
    local furnace = roles.furnace
    local fuel_pa = roles.fuel_pa
    local coolant_pa = roles.coolant_pa
    local o2 = roles.o2_pa
    local ch4 = roles.ch4_pa
    local room_sensor = roles.room_sensor

    readings.furnace_temp = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.Temperature, LBM.Average)
    readings.furnace_press = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.Pressure, LBM.Average)
    readings.furnace_reagents = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.Reagents, LBM.Average)
    readings.furnace_recipe_hash = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.RecipeHash, LBM.Average)
    readings.furnace_open = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.Open, LBM.Average)
    readings.furnace_export_count = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.ExportCount, LBM.Average)
    readings.furnace_import_count = safe_batch_read_name(furnace.prefab, furnace.namehash, LT.ImportCount, LBM.Average)

    readings.fuel_pa_press = safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, LT.Pressure, LBM.Average)
    readings.fuel_pa_temp = safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, LT.Temperature, LBM.Average)
    readings.fuel_pa_moles = safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, LT.TotalMoles, LBM.Average)
    readings.fuel_pa_vol = safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, LT.Volume, LBM.Average)

    readings.room_press = safe_batch_read_name(room_sensor.prefab, room_sensor.namehash, LT.Pressure, LBM.Average)
    readings.room_temp = safe_batch_read_name(room_sensor.prefab, room_sensor.namehash, LT.Temperature, LBM.Average)

    readings.coolant_pa_press = safe_batch_read_name(coolant_pa.prefab, coolant_pa.namehash, LT.Pressure, LBM.Average)
    readings.coolant_pa_temp = safe_batch_read_name(coolant_pa.prefab, coolant_pa.namehash, LT.Temperature, LBM.Average)
    readings.coolant_pa_moles = safe_batch_read_name(coolant_pa.prefab, coolant_pa.namehash, LT.TotalMoles, LBM.Average)
    readings.coolant_pa_vol = safe_batch_read_name(coolant_pa.prefab, coolant_pa.namehash, LT.Volume, LBM.Average)

    readings.o2_pa_press = safe_batch_read_name(o2.prefab, o2.namehash, LT.Pressure, LBM.Average)
    readings.ch4_pa_press = safe_batch_read_name(ch4.prefab, ch4.namehash, LT.Pressure, LBM.Average)
end

local function read_silo_quantity(material)
    local role_key = silo_role_by_material[material]
    if role_key == nil then return 0 end
    local role = roles[role_key]
    if role == nil then return 0 end
    return logic_or_zero(role, LT.Quantity)
end

local function read_silo_ore_amount(material)
    return read_silo_quantity(material) * ORE_STACK_SIZE
end

recipe_has_stock = function(recipe_index, amount)
    local req = recipe_requirements[recipe_index]
    if req == nil then return false end

    for mat, count_per in pairs(req) do
        local ore_available = read_silo_ore_amount(mat)
        local ore_needed = ore_needed_for_material(recipe_index, count_per, amount)
        if ore_available < ore_needed then
            return false
        end
    end
    return true
end

local function get_queue_total_requirements()
    local totals = {}
    for _, item in ipairs(smelting_queue) do
        local req = recipe_requirements[item.recipe_id]
        local scale = recipe_amount_scale(item.recipe_id)
        if req then
            for mat, count_per in pairs(req) do
                totals[mat] = (totals[mat] or 0) + (count_per * item.amount * scale)
            end
        end
    end
    return totals
end

local function validate_queue_stock()
    local totals = get_queue_total_requirements()
    local missing = {}
    local all_ok = true
    for mat, needed in pairs(totals) do
        local available = read_silo_ore_amount(mat)
        if available < needed then
            missing[mat] = needed - available
            all_ok = false
        end
    end
    return all_ok, missing
end

function save_smelting_queue()
    local count = #smelting_queue
    write(MEM_QUEUE_COUNT, count)
    for i = 1, math.min(count, 50) do
        local item = smelting_queue[i]
        local base = MEM_QUEUE_START + (i - 1) * 2
        write(base, item.recipe_id or 0)
        write(base + 1, item.amount or 0)
    end
    log_step("save_smelting_queue: saved " .. tostring(count) .. " items")
end

function load_smelting_queue()
    local count = tonumber(read(MEM_QUEUE_COUNT)) or 0
    smelting_queue = {}
    if count > 0 then
        for i = 1, math.min(count, 50) do
            local base = MEM_QUEUE_START + (i - 1) * 2
            local recipe_id = tonumber(read(base)) or 0
            local amount = tonumber(read(base + 1)) or 0
            if recipe_id > 0 then
                table.insert(smelting_queue, { recipe_id = recipe_id, amount = amount })
            end
        end
    end
    log_step("load_smelting_queue: loaded " .. tostring(#smelting_queue) .. " items")
end


function set_status_visuals()
    local function commit_status_log()
        if status_text ~= last_status_text then
            log_step("set_status_visuals: status changed to '" .. tostring(status_text) .. "'")
            last_status_text = status_text
        end
    end

    if not role_is_bound(roles.furnace) then
        status_text = "Assign Furnace"
        status_color = C.red
        commit_status_log()
        return
    end

    if not roles_are_bound({ "fuel_pump", "coolant_pump", "fuel_mixer" }) then
        status_text = "Assign flow devices"
        status_color = C.red
        commit_status_log()
        return
    end

    if requested_recipe <= 0 then
        status_text = "Idle"
        status_color = C.text_dim
        commit_status_log()
        return
    end

    stock_ok = recipe_has_stock(requested_recipe, requested_amount)
    if not stock_ok then
        status_text = "Missing materials"
        status_color = C.red
        commit_status_log()
        return
    end

    if furnace_run_active then
        status_text = "Running"
        status_color = C.green
    else
        status_text = "Ready"
        status_color = C.yellow
    end
    commit_status_log()
end

function run_recovery_logic(tick_count)
    if not is_recovery_active or not is_batch_running then return end

    local furnace = roles.furnace
    if not role_is_bound(furnace) then
        is_recovery_active = false
        return
    end

    if recovery_timer > 0 then
        recovery_timer = recovery_timer - 1
        status_text = "Failsafe Wait (" .. tostring(recovery_timer) .. ")"
        status_color = C.orange
        return
    end

    local exp = readings.furnace_export_count or 0
    local rgn = readings.furnace_reagents or 0
    local target = recipe_target_reagents(requested_recipe, requested_amount)

    log_step(string.format("run_recovery_logic: phase=%d exp=%s reagents=%s target=%s", recovery_phase, tostring(exp), tostring(rgn), tostring(target)))


    if lever_pulse_remaining > 0 then
        return
    end

    if recovery_phase == 0 then

        if exp > 0 then
            log_step("recovery: items exported - clearing memory and moving to next")
            safe_batch_write_name(furnace.prefab, furnace.namehash, LT.ClearMemory, 1)
            if rgn > 0 then

                log_step("recovery: leftovers detected - triggering double eject pulse")
                lever_pulse_remaining = 4
                lever_pulse_timer = 1
            end

            batch_wait_finish = true
            is_recovery_active = false
            return
        end
        

        if rgn > 0 then
            log_step("recovery: reagents present, waiting for stable result")
            recovery_last_reagents = rgn
            recovery_timer = 10
            recovery_phase = 1
            return
        else

            log_step("recovery: empty furnace - starting recipe")
            is_recovery_active = false
            start_selected_recipe()
            return
        end
    elseif recovery_phase == 1 then

        if rgn ~= recovery_last_reagents then
            log_step(string.format("recovery: reagents still changing (%s -> %s) - resetting stability timer", tostring(recovery_last_reagents), tostring(rgn)))
            recovery_last_reagents = rgn
            recovery_timer = 10
            return
        end
        

        log_step(string.format("recovery: reagents stable at %s - proceeding to decision", tostring(rgn)))
        recovery_phase = 2
        
    elseif recovery_phase == 2 then

        if rgn == target then
            log_step("recovery: reagents match - resuming smelting")
            furnace_run_active = true
            has_seen_reagents = true
            is_recovery_active = false
        else
            local req = recipe_requirements[requested_recipe]
            local ingredient_count = 0
            for _ in pairs(req or {}) do ingredient_count = ingredient_count + 1 end

            if ingredient_count == 1 and requested_recipe <= 7 then
                local diff = math.max(0, target - rgn)
                if diff > 0 then
                    log_step(string.format("recovery: partial ore match (%s/%s) - requesting %s more", tostring(rgn), tostring(target), tostring(diff)))
                    local mat = MATERIAL_ORDER[requested_recipe]
                    local role_key = silo_role_by_material[mat]
                    if role_key then
                        silo_request.active = true
                        silo_request.items = {{ material = mat, role_key = role_key, remaining = diff / 50 }}
                        silo_request.item_index = 1
                        silo_request.phase = 0
                    end
                end
                furnace_run_active = true
                has_seen_reagents = true
                is_recovery_active = false
            else
                log_step(string.format("recovery: reagent mismatch (%s/%s) for %s - ejecting and restarting", tostring(rgn), tostring(target), tostring(recipe_names[requested_recipe])))
                lever_pulse_remaining = 4
                lever_pulse_timer = 1
                is_recovery_active = false
                start_selected_recipe()
            end
        end
    end
end

function run_furnace_activity_monitor()
    if not furnace_run_active or silo_request.active or is_recovery_active then
        furnace_stuck_ticks = 0
        return
    end

    local rgn = readings.furnace_reagents or 0
    local imp = readings.furnace_import_count or 0
    local exp = readings.furnace_export_count or 0

    if rgn ~= last_activity_reagents or imp ~= last_activity_import or exp ~= last_activity_export then
        furnace_stuck_ticks = 0
        last_activity_reagents = rgn
        last_activity_import = imp
        last_activity_export = exp
    else
        furnace_stuck_ticks = furnace_stuck_ticks + 1
        if furnace_stuck_ticks % 20 == 0 then
            log_step("monitor: no physical activity for " .. tostring(furnace_stuck_ticks) .. " ticks")
        end

        if furnace_stuck_ticks >= 100 then
            log_step("monitor: STUCK DETECTED - triggering failsafe recovery eject")
            lever_pulse_remaining = 4 
            lever_pulse_timer = 1
            furnace_stuck_ticks = 0
            
        end
    end
end

local function handle_power_toggle()
    global_power_on = not global_power_on
    local val = global_power_on and 1 or 0
    
    log_step("handle_power_toggle: power_on=" .. tostring(global_power_on) .. " target_all=" .. tostring(power_target_all))
    
    for _, role in pairs(roles) do
        if role_is_bound(role) then
            local is_storage = role.key:find("silo") or role.key:find("vend")
            if power_target_all or not is_storage then
                safe_batch_write_name(role.prefab, role.namehash, LT.On, val)
            end
        end
    end

    if power_target_all then
        log_action("power_target_all is true")
        for _, p_hash in ipairs(OTHER_PREFABS or {}) do
            log_action("power_target_all is true - writing to prefab: " .. tostring(p_hash))
            safe_batch_write_prefab(p_hash, LT.On, val)
        end
    end

    save_control_settings()
    dashboard_render(true)
end

function run_lever_pulse_logic()
    if lever_pulse_remaining <= 0 then return end

    local furnace = roles.furnace
    if not role_is_bound(furnace) then
        lever_pulse_remaining = 0
        return
    end

    lever_pulse_timer = lever_pulse_timer - 1
    if lever_pulse_timer <= 0 then
        local setting = (lever_pulse_remaining % 2 == 0) and 1 or 0
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.Open, setting)
        lever_pulse_remaining = lever_pulse_remaining - 1
        lever_pulse_timer = 5 
        log_step("lever: pulse transition - Open=" .. tostring(setting) .. " (rem=" .. tostring(lever_pulse_remaining) .. ")")
    end
end


FUEL_MIXER_FILL_ON_THRESHOLD    = 10000
FUEL_MIXER_FILL_OFF_THRESHOLD   = 30000
FUEL_MIXER_FAST_CHECK_TICKS     = 1
FUEL_MIXER_RATIO_TOLERANCE      = 0.025  -- 2.5% molar fraction tolerance
FUEL_MIXER_RATIO_CORRECTION_GAIN = 2.5   -- how hard to push setting when off-ratio
FUEL_MIXER_RATIO_MAX_OFFSET     = 40     -- max deviation from nominal setting

local function get_fuel_tank_oxidiser_ratio(opt)
    local fuel_pa = roles.fuel_pa
    if not role_is_bound(fuel_pa) or opt.oxidiser_lt == nil then return nil end
    return safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, opt.oxidiser_lt, LBM.Average)
end

local function desired_mixer_setting(opt, current_oxidiser_ratio)
    if current_oxidiser_ratio == nil then return opt.setting end
    local target = opt.setting / 100
    local err = target - current_oxidiser_ratio
    if math.abs(err) < FUEL_MIXER_RATIO_TOLERANCE then
        return opt.setting
    end
    local correction = err * 100 * FUEL_MIXER_RATIO_CORRECTION_GAIN
    local lo = math.max(5,  opt.setting - FUEL_MIXER_RATIO_MAX_OFFSET)
    local hi = math.min(95, opt.setting + FUEL_MIXER_RATIO_MAX_OFFSET)
    return clamp(opt.setting + correction, lo, hi)
end

local function run_mixer_ratio_logic()
    if fuel_mixer_fill_active then return end
    local mixer = roles.fuel_mixer
    if not role_is_bound(mixer) then return end
    local opt = GAS_MIX_OPTIONS[gas_mix_index] or GAS_MIX_OPTIONS[1]
    safe_batch_write_name(mixer.prefab, mixer.namehash, LT.Setting, opt.setting)
end

local function run_fuel_mixer_fill_logic()
    local fuel_pa = roles.fuel_pa
    local fuel_mixer = roles.fuel_mixer
    if not role_is_bound(fuel_pa) or not role_is_bound(fuel_mixer) then
        fuel_mixer_fill_active = false
        return
    end
    local pressure = safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, LT.Pressure, LBM.Average) or 0
    local opt = GAS_MIX_OPTIONS[gas_mix_index] or GAS_MIX_OPTIONS[1]
    if pressure >= FUEL_MIXER_FILL_OFF_THRESHOLD then
        safe_batch_write_name(fuel_mixer.prefab, fuel_mixer.namehash, LT.On, 0)
        fuel_mixer_fill_active = false
        return
    end
    if pressure < FUEL_MIXER_FILL_ON_THRESHOLD then
        if not fuel_mixer_fill_active then
            safe_batch_write_name(fuel_mixer.prefab, fuel_mixer.namehash, LT.Setting, opt.setting)
            safe_batch_write_name(fuel_mixer.prefab, fuel_mixer.namehash, LT.On, 1)
            fuel_mixer_fill_active = true
            log_step(string.format("fuel_mixer: START | press=%.0f | nominal_setting=%.1f",
                pressure, opt.setting))
        end
    end
end

local function run_fuel_mixer_fast_safety_check()
    if not fuel_mixer_fill_active then return end
    local fuel_pa = roles.fuel_pa
    local fuel_mixer = roles.fuel_mixer
    if not role_is_bound(fuel_pa) or not role_is_bound(fuel_mixer) then
        fuel_mixer_fill_active = false
        return
    end
    local pressure = safe_batch_read_name(fuel_pa.prefab, fuel_pa.namehash, LT.Pressure, LBM.Average) or 0
    local opt = GAS_MIX_OPTIONS[gas_mix_index] or GAS_MIX_OPTIONS[1]
    if pressure >= FUEL_MIXER_FILL_OFF_THRESHOLD then
        safe_batch_write_name(fuel_mixer.prefab, fuel_mixer.namehash, LT.On, 0)
        fuel_mixer_fill_active = false
        log_step("fuel_mixer_fast_check: target pressure reached - mixer OFF")
        return
    end
    local current_ratio = get_fuel_tank_oxidiser_ratio(opt)
    if gas_mix_mole_based then
        local setting = desired_mixer_setting(opt, current_ratio)
        safe_batch_write_name(fuel_mixer.prefab, fuel_mixer.namehash, LT.Setting, setting)
    end

end

function run_furnace_automation()
    local furnace = roles.furnace
    local fuel_pump = roles.fuel_pump
    local coolant_pump = roles.coolant_pump
    local fuel_mixer = roles.fuel_mixer

    if not roles_are_bound({ "furnace", "fuel_pump", "coolant_pump", "fuel_mixer" }) then
        furnace_run_active = false
        recipe_ready = false
        log_step("run_furnace_automation: stopped missing required bindings")
        return
    end

    local t = readings.furnace_temp or 0
    local p = readings.furnace_press or 0
    local recipe_min_temp, recipe_max_temp, recipe_min_press, recipe_max_press = recipe_window(requested_recipe)

    local flush_open = flush_enabled
    if flush_open or p > 55000 then
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingOutput, 100)
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingInput, 0)
        safe_batch_write_name(fuel_pump.prefab, fuel_pump.namehash, LT.On, 0)
        safe_batch_write_name(coolant_pump.prefab, coolant_pump.namehash, LT.On, 0)
        safe_batch_write_name(fuel_pump.prefab, fuel_pump.namehash, LT.Setting, 0)
        safe_batch_write_name(coolant_pump.prefab, coolant_pump.namehash, LT.Setting, 0)
        return
    end

    if not furnace_run_active or requested_recipe <= 0 or not stock_ok then
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingInput, 0)
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingOutput, 0)
        safe_batch_write_name(fuel_pump.prefab, fuel_pump.namehash, LT.On, 0)
        safe_batch_write_name(coolant_pump.prefab, coolant_pump.namehash, LT.On, 0)
        safe_batch_write_name(fuel_pump.prefab, fuel_pump.namehash, LT.Setting, 0)
        safe_batch_write_name(coolant_pump.prefab, coolant_pump.namehash, LT.Setting, 0)
        return
    end

    safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingInput, 100)
    
    if furnace_ignition_ticks > 0 then
        furnace_ignition_ticks = furnace_ignition_ticks - 1
        if (furnace_ignition_ticks % 5) < 2 then
            safe_batch_write_name(furnace.prefab, furnace.namehash, LT.Activate, 1)
            log_step("run_furnace_automation: Ignition Pulse Activate=1 (rem=" .. tostring(furnace_ignition_ticks) .. ")")
        end
    end

    if t < recipe_min_temp and t <= max_temp_hard then
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.Activate, 1)
        log_step("run_furnace_automation: Activate=1 (t=" .. tostring(t) .. " < " .. tostring(recipe_min_temp) .. ")")
    end

    local fuel_v = readings.fuel_pa_vol or 0
    local fuel_T = readings.fuel_pa_temp or 0
    local fuel_n = readings.fuel_pa_moles or 0
    local coolant_v = readings.coolant_pa_vol or 0
    local coolant_T = readings.coolant_pa_temp or 0
    local coolant_n = readings.coolant_pa_moles or 0

    local fuel_setting = 0
    if fuel_T > 0 and fuel_n > 0 and fuel_v > 0 then
        local temp_ref = math.max(t, 300)
        local ratio = recipe_max_temp / temp_ref
        fuel_setting = fuel_v * recipe_min_press * ratio * 500
        fuel_setting = fuel_setting / (fuel_T * fuel_n * 8314.46)
    end

    local coolant_setting = 0
    if coolant_T > 0 and coolant_n > 0 and coolant_v > 0 then
        local temp_ratio = clamp(t / math.max(recipe_max_temp, 1), 0, 1)
        local cterm = coolant_T * 250000
        coolant_setting = coolant_v * temp_ratio * cterm
        coolant_setting = coolant_setting / (coolant_T * coolant_n * 8314.46)
    end

    safe_batch_write_name(fuel_pump.prefab, fuel_pump.namehash, LT.Setting, clamp(fuel_setting, 0, 100))
    safe_batch_write_name(coolant_pump.prefab, coolant_pump.namehash, LT.Setting, clamp(coolant_setting, 0, 100))

    local fuel_on = (t < recipe_min_temp or p < recipe_min_press) and 1 or 0
    local coolant_on = (t > recipe_max_temp) and 1 or 0
    local output_setting = (p > recipe_max_press) and 30 or 0

    safe_batch_write_name(fuel_pump.prefab, fuel_pump.namehash, LT.On, fuel_on)
    safe_batch_write_name(coolant_pump.prefab, coolant_pump.namehash, LT.On, coolant_on)
    safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingOutput, output_setting)

    if requested_hash ~= 0 then
        safe_batch_write_name(furnace.prefab, furnace.namehash, LT.RequestHash, requested_hash)
    end

    local current_recipe_hash = math.floor(readings.furnace_recipe_hash or 0)
    local reagents = readings.furnace_reagents or 0
    local target_reagents = recipe_target_reagents(requested_recipe, requested_amount)

    if current_recipe_hash == requested_hash and reagents >= target_reagents then
        if t >= recipe_min_temp and t <= recipe_max_temp and p >= recipe_min_press and p <= recipe_max_press then
            recipe_ready = true
        end
    end
    if reagents > 0 or recipe_ready then has_seen_reagents = true end

    local is_empty = reagents <= 0
    local request_done = not silo_request.active
    
    local can_reset = (recipe_ready or has_seen_reagents or (currenttime - furnace_start_tick > 45)) and not silo_request.active
    
    if furnace_run_active and is_empty and request_done then
        if can_reset then
            if waiting_for_export_clear == 0 then
                waiting_for_export_clear = 5
                log_step("run_furnace_automation: smelting finished - waiting 5 ticks for memory sync")
                return
            end
            
            waiting_for_export_clear = waiting_for_export_clear - 1
            if waiting_for_export_clear > 0 then return end

            log_step("run_furnace_automation: clearing furnace memory before next task")
            safe_batch_write_name(furnace.prefab, furnace.namehash, LT.ClearMemory, 1)
            
            lever_pulse_remaining = 0 
            safe_batch_write_name(furnace.prefab, furnace.namehash, LT.Open, 0)
            safe_batch_write_name(furnace.prefab, furnace.namehash, LT.SettingOutput, 0)
            furnace_run_active = false
            has_seen_reagents = false
            recipe_ready = false
            log_step("run_furnace_automation: smelting completed/reset")
        elseif current_recipe_hash == requested_hash then
            recipe_ready = true
            if lever_pulse_remaining == 0 and waiting_for_export_clear == 0 then
                lever_pulse_remaining = 2
                lever_pulse_timer = 1
            end
        end
    elseif recipe_ready then
        if lever_pulse_remaining == 0 and waiting_for_export_clear == 0 then
            lever_pulse_remaining = 2
            lever_pulse_timer = 1
        end
    end
end

local function safe_batch_read_slot(prefab, namehash, slot, logic_slot_type)
    if batch_read_slot_name == nil then return nil end
    local p = tonumber(prefab) or 0
    local n = tonumber(namehash) or 0
    if p == 0 or n == 0 then return nil end
    local ok, value = pcall(batch_read_slot_name, p, n, slot, logic_slot_type, LBM.Average)
    if not ok then return nil end
    return value
end

local function update_vending_readings()
    readings.vend_ingot_totals = {}
    local function scan_vend(role, free_key)
        readings[free_key] = nil
        if not role_is_bound(role) then return end
        local free = 0
        for slot = 0, 100 do
            local occupied = safe_batch_read_slot(role.prefab, role.namehash, slot, LST.Occupied)
            if occupied == nil then break end
            if occupied == 0 then
                free = free + 1
            else
                local h = safe_batch_read_slot(role.prefab, role.namehash, slot, LST.OccupantHash)
                local q = safe_batch_read_slot(role.prefab, role.namehash, slot, LST.Quantity)
                if h ~= nil and h ~= 0 then
                    readings.vend_ingot_totals[h] = (readings.vend_ingot_totals[h] or 0) + (q or 0)
                end
            end
        end
        readings[free_key] = free
    end
    scan_vend(roles.vend_normal, "vend_normal_free")
    scan_vend(roles.vend_alloy,  "vend_alloy_free")
end

function update_room_ventilation(tick_count)
    local r_vent_in = roles.vent_1
    local r_vent_out = roles.vent_2_out
    local r_sensor = roles.room_sensor
    
    if not roles_are_bound({"vent_1", "vent_2_out", "room_sensor"}) then return end
    
    if vent_enabled then
        vent_pulse_state = 0 
        safe_batch_write_name(r_vent_in.prefab, r_vent_in.namehash, LT.On, 0)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.On, 1)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.Mode, 1)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.PressureInternal, 40000)
        last_vent_enabled = true
        return
    end

    if last_vent_enabled then
        last_vent_enabled = false
        vent_pulse_state = 3
        vent_pulse_start = tick_count
        log_step("vent: manual mode ended - starting 10t refill pulse")
    end

    local temp = readings.room_temp or 0
    local pres = readings.room_press or 0


    if vent_pulse_state == 0 then
        if temp > 520 or pres > 250 then
            vent_pulse_state = 1
            vent_pulse_start = tick_count
            log_step("vent: auto-pulse start - extracting")
        end
    elseif vent_pulse_state == 1 then
        if tick_count - vent_pulse_start >= 4 then
            vent_pulse_state = 2
            vent_pulse_start = tick_count
            log_step("vent: auto-pulse phase - filling")
        end
    elseif vent_pulse_state == 2 then
        if tick_count - vent_pulse_start >= 4 then
            vent_pulse_state = 0
            log_step("vent: auto-pulse end - idle")
        end
    elseif vent_pulse_state == 3 then
        if tick_count - vent_pulse_start >= 10 then
            vent_pulse_state = 0
            log_step("vent: manual refill pulse end - idle")
        end
    end


    if vent_pulse_state == 1 then
        safe_batch_write_name(r_vent_in.prefab, r_vent_in.namehash, LT.On, 0)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.On, 1)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.Mode, 1)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.PressureInternal, 40000)
    elseif vent_pulse_state == 2 or vent_pulse_state == 3 then
        safe_batch_write_name(r_vent_in.prefab, r_vent_in.namehash, LT.On, 1)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.On, 0)
        safe_batch_write_name(r_vent_in.prefab, r_vent_in.namehash, LT.Mode, 0)
        safe_batch_write_name(r_vent_in.prefab, r_vent_in.namehash, LT.PressureExternal, 101)
    else
        safe_batch_write_name(r_vent_in.prefab, r_vent_in.namehash, LT.On, 0)
        safe_batch_write_name(r_vent_out.prefab, r_vent_out.namehash, LT.On, 0)
    end
end

local batch_status_text = "Idle (Ready)"
function run_batch_sequencer()
    if not is_batch_running then 
        if #smelting_queue == 0 then
            batch_status_text = "Idle (Queue Empty)"
        else
            if not batch_status_text:find("Error") and not batch_status_text:find("Missing") then
                batch_status_text = "Idle (Ready)"
            end
        end
        return 
    end

    if furnace_run_active then
        batch_wait_finish = true
        if silo_request.active then
            batch_status_text = "Requesting Ores..."
        elseif not has_seen_reagents then
            batch_status_text = "Waiting for Ores..."
        else
            batch_status_text = "Smelting..."
        end
        return
    end

    if batch_wait_finish then
        batch_status_text = "Finalizing Batch..."
        if #smelting_queue > 0 then
            table.remove(smelting_queue, 1)
            save_smelting_queue()
            dashboard_render(true)
        end
        batch_wait_finish = false
    end

    if #smelting_queue > 0 then
        local next_item = smelting_queue[1]
        local recipe_id = next_item.recipe_id
        
        for i, ing in ipairs(ingots) do
            if ing[3] == recipe_id then
                selected_ingot_index = i
                break
            end
        end
        
        requested_amount = next_item.amount
        sync_selected_recipe()
        if not start_selected_recipe() then
            is_batch_running = false
            save_control_settings()
            batch_status_text = "Idle (Error: Check Bindings/Stock)"
            log_step("sequencer: batch stopped - start failed")
            dashboard_render(true)
        else
            log_step("sequencer: started next batch item")
            batch_wait_finish = true
            dashboard_render(true)
        end
    else
        is_batch_running = false
        save_control_settings()
        batch_status_text = "Idle (All Batches Done)"
        log_step("sequencer: all batches completed")
        dashboard_render(true)
    end
end

function main_logic_tick(tick_count)
    update_readings()
    run_lever_pulse_logic()
    run_furnace_activity_monitor()
    
    if is_recovery_active then
        run_recovery_logic(tick_count)
        if is_recovery_active then return end
    end

    run_furnace_automation()
    run_batch_sequencer()
    update_room_ventilation(tick_count)
    sync_selected_recipe()

    if furnace_run_active and silo_request.active then
        process_silo_request_tick()
    end

    if (tick_count % FUEL_MIXER_CHECK_TICKS) == 0 then
        run_mixer_ratio_logic()
        run_fuel_mixer_fill_logic()
    elseif (tick_count % FUEL_MIXER_FAST_CHECK_TICKS) == 0 then
        run_fuel_mixer_fast_safety_check()
    end

    set_status_visuals()
end

-- ==================== UI RENDER ====================

local function reset_handles()
    handles = { nav = {}, footer = {}, overview = {}, settings = {}, batch = {} }
end


function render_header()
    local header = s:element({
        id = "header_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = 0, w = W, h = 30 },
        style = { bg = C.header }
    })

    header:element({
        id = "line_left",
        type = "line",
        props = { x1 = 10, y1 = 16, x2 = 170, y2 = 16 },
        style = { color = C.accent, thickness = 1 }
    })

    header:element({
        id = "title",
        type = "label",
        rect = { unit = "px", x = 0, y = 6, w = W, h = 20 },
        props = { text = "Smelting Buddy" },
        style = { font_size = 14, color = C.title, align = "center" }
    })

    header:element({
        id = "line_right",
        type = "line",
        props = { x1 = 290, y1 = 16, x2 = W - 10, y2 = 16 },
        style = { color = C.accent, thickness = 1 }
    })
end

function render_nav(surface)
    local tabs = {
        { id = "nav_overview", page = "overview", text = "Overview" },
        { id = "nav_batch",    page = "batch",    text = "Batch" },
        { id = "nav_settings", page = "settings", text = "Settings" },
    }
    local tab_gap = 4
    local tab_w = math.floor((W - 10 - tab_gap) / #tabs)
    local total_w = (#tabs * tab_w) + ((#tabs - 1) * tab_gap)
    local start_x = math.floor((W - total_w) / 2)

    for i, tab in ipairs(tabs) do
        local active = (view == tab.page)
        local target = tab.page
        handles.nav[tab.page] = s:element({
            id = tab.id,
            type = "button",
            rect = { unit = "px", x = start_x + (i - 1) * (tab_w + tab_gap), y = 34, w = tab_w, h = 22 },
            props = { text = tab.text },
            style = {
                bg = active and "#6844aa" or "#333344",
                text = "#FFFFFF",
                font_size = 11,
                gradient = active and "#3b1f88" or "#1c1c2e",
                gradient_dir = "vertical"
            },
            on_click = function()
                set_view(target)
            end
        })
    end
end

function update_nav_dynamic()
    local function set_nav(key)
        if handles.nav[key] == nil then return end
        local active = (view == key)
        handles.nav[key]:set_style({
            bg = active and "#6844aa" or "#333344",
            text = "#FFFFFF",
            font_size = 11,
            gradient = active and "#3b1f88" or "#1c1c2e",
            gradient_dir = "vertical"
        })
    end
    set_nav("overview")
    set_nav("batch")
    set_nav("settings")
end

function update_batch_dynamic()
    if not handles.batch or not handles.batch.start_btn then return end

    local entry = ingots[batch_selected_ingot_index] or ingots[1]
    if handles.batch.icon then handles.batch.icon:set_props({ name = tostring(entry[2]) }) end
    if handles.batch.ingot_name then handles.batch.ingot_name:set_props({ text = entry[1] }) end
    if handles.batch.amount_value then handles.batch.amount_value:set_props({ text = tostring(batch_requested_amount) }) end

    local all_ok, missing = validate_queue_stock()
    
    local missing_text = ""
    if not all_ok then
        missing_text = "Missing: "
        for mat, amt in pairs(missing) do
            missing_text = missing_text .. string.format("%d %s, ", amt, mat)
        end
        missing_text = missing_text:sub(1, -3)
    elseif #smelting_queue > 0 then
        missing_text = "All materials available. Ready to start."
    end
    
    if handles.batch.missing_label then
        handles.batch.missing_label:set_props({ text = missing_text })
        handles.batch.missing_label:set_style({ color = all_ok and C.green or C.red })
    end

    local b_text = is_batch_running and "Stop Batch" or "Start Batch"
    local b_bg = is_batch_running and C.red or (all_ok and #smelting_queue > 0 and C.green or C.bar_bg)
    local b_color = (is_batch_running or (all_ok and #smelting_queue > 0)) and C.bg or C.text_dim

    handles.batch.start_btn:set_props({ text = b_text })
    handles.batch.start_btn:set_style({ bg = b_bg, color = b_color })
end

function render_batch(surface)
    local left_col_x = 8
    local left_col_w = 220

    local entry = ingots[batch_selected_ingot_index] or ingots[1]
    
    s:element({
        id = "batch_selector_bg",
        type = "panel",
        rect = { unit = "px", x = left_col_x, y = 60, w = left_col_w, h = H - 82 },
        style = { bg = C.panel }
    })

    local center_x = function(w) return left_col_x + math.floor((left_col_w - w) / 2) end

    handles.batch.icon = s:element({
        id = "batch_icon",
        type = "icon",
        rect = { unit = "px", x = center_x(84), y = 82, w = 84, h = 84 },
        props = { name = tostring(entry[2]), icon_type = "prefab" },
        style = { tint = "#FFFFFF" },
    })

    handles.batch.ingot_name = s:element({
        id = "batch_name",
        type = "label",
        rect = { unit = "px", x = center_x(206), y = 168, w = 206, h = 16 },
        props = { text = entry[1] },
        style = { color = C.text, font_size = 11, align = "center" },
    })

    local btn_w = 40
    s:element({
        id = "batch_prev",
        type = "button",
        rect = { unit = "px", x = center_x(2 * btn_w + 20), y = 185, w = btn_w, h = 18 },
        props = { text = "<" },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            batch_selected_ingot_index = ((batch_selected_ingot_index - 2) % totalIngots) + 1
            dashboard_render(false)
        end
    })
    s:element({
        id = "batch_next",
        type = "button",
        rect = { unit = "px", x = center_x(2 * btn_w + 20) + btn_w + 20, y = 185, w = btn_w, h = 18 },
        props = { text = ">" },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            batch_selected_ingot_index = (batch_selected_ingot_index % totalIngots) + 1
            dashboard_render(false)
        end
    })

    local b_label_w = 60
    local b_val_w = 40
    local b_btn_w = 26
    local b_total_w = b_label_w + b_val_w + 2 * b_btn_w + 8
    local b_x = center_x(b_total_w)
    s:element({
        id = "batch_amt_label",
        type = "label",
        rect = { unit = "px", x = b_x, y = 205, w = b_label_w, h = 14 },
        props = { text = "Batches" },
        style = { color = C.text_dim, font_size = 9, align = "left" },
    })
    handles.batch.amount_value = s:element({
        id = "batch_amt_value",
        type = "label",
        rect = { unit = "px", x = b_x + b_label_w, y = 205, w = b_val_w, h = 14 },
        props = { text = tostring(batch_requested_amount) },
        style = { color = C.text, font_size = 10, align = "center" },
    })
    s:element({
        id = "batch_amt_dec",
        type = "button",
        rect = { unit = "px", x = b_x + b_label_w + b_val_w, y = 205, w = b_btn_w, h = 18 },
        props = { text = "-" },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            batch_requested_amount = math.max(1, batch_requested_amount - 1)
            dashboard_render(false)
        end
    })
    s:element({
        id = "batch_amt_inc",
        type = "button",
        rect = { unit = "px", x = b_x + b_label_w + b_val_w + b_btn_w + 4, y = 205, w = b_btn_w, h = 18 },
        props = { text = "+" },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            batch_requested_amount = math.min(50, batch_requested_amount + 1)
            dashboard_render(false)
        end
    })

    s:element({
        id = "batch_add_btn",
        type = "button",
        rect = { unit = "px", x = center_x(120), y = 226, w = 120, h = 20 },
        props = { text = "Add to Queue" },
        style = { bg = C.accent, text = C.bg, font_size = 9, gradient = "#0f4c63", gradient_dir = "vertical" },
        on_click = function()
            local current_entry = ingots[batch_selected_ingot_index] or ingots[1]
            local id = current_entry[3]
            
            local merged = false
            for _, q in ipairs(smelting_queue) do
                if q.recipe_id == id then
                    q.amount = q.amount + batch_requested_amount
                    merged = true
                    break
                end
            end
            
            if not merged then
                table.insert(smelting_queue, { recipe_id = id, amount = batch_requested_amount })
            end
            save_smelting_queue()
            dashboard_render(true)
        end
    })

    s:element({
        id = "queue_requirements_title",
        type = "label",
        rect = { unit = "px", x = left_col_x + 20, y = 270, w = 150, h = 14 },
        props = { text = "Total Required Ores:" },
        style = { color = C.accent, font_size = 9, align = "left" }
    })

    local req_totals = get_queue_total_requirements()
    local req_y = 285
    for mat, amt in pairs(req_totals) do
        s:element({
            id = "total_req_" .. mat,
            type = "label",
            rect = { unit = "px", x = left_col_x + 25, y = req_y, w = 150, h = 12 },
            props = { text = string.format("- %d %s", amt, mat) },
            style = { color = C.text, font_size = 8, align = "left" }
        })
        req_y = req_y + 11
        if req_y > H - 15 then break end
    end

    s:element({
        id = "queue_bg",
        type = "panel",
        rect = { unit = "px", x = 232, y = 60, w = W - 240, h = H - 82 },
        style = { bg = C.panel }
    })

    s:element({
        id = "queue_title",
        type = "label",
        rect = { unit = "px", x = 232, y = 70, w = W - 240, h = 14 },
        props = { text = "Smelting Queue" },
        style = { color = C.accent, font_size = 10, align = "center" }
    })

    local q_y = 100
    for i, item in ipairs(smelting_queue) do
        local recipe_id = item.recipe_id
        local ingot_name = "Unknown"
        for _, ing in ipairs(ingots) do
            if ing[3] == recipe_id then ingot_name = ing[1] break end
        end
        local scale = recipe_amount_scale(recipe_id)
        local total_qty = item.amount * scale
        
        s:element({
            id = "q_item_" .. i,
            type = "label",
            rect = { unit = "px", x = 282, y = q_y, w = 180, h = 10 },
            props = { text = string.format("%d. %dx %s", i, total_qty, ingot_name) },
            style = { color = C.text, font_size = 8, align = "left" }
        })
        s:element({
            id = "q_rem_" .. i,
            type = "button",
            rect = { unit = "px", x = W - 60, y = q_y, w = 12, h = 10 },
            props = { text = "X" },
            style = { bg = C.red, text = "#FFFFFF", font_size = 7 },
            on_click = function()
                table.remove(smelting_queue, i)
                save_smelting_queue()
                dashboard_render(true)
            end
        })
        q_y = q_y + 10
        if i >= 17 then break end
        if q_y > H - 28 then break end
    end

    handles.batch.missing_label = s:element({
        id = "queue_missing_info",
        type = "label",
        rect = { unit = "px", x = 232, y = H - 140, w = W - 240, h = 30 },
        props = { text = "" },
        style = { color = C.red, font_size = 8, align = "center" }
    })

    s:element({
        id = "nav_batch_temp",
        type = "label",
        rect = { unit = "px", x = 242, y = H - 115, w = W - 260, h = 14 },
        props = { text = "Furnace Temp: " .. furnace_temp_text(readings.furnace_temp) },
        style = { color = furnace_temp_color(readings.furnace_temp), font_size = 9, align = "center" }
    })
    
    s:element({
        id = "nav_batch_press",
        type = "label",
        rect = { unit = "px", x = 242, y = H - 100, w = W - 260, h = 14 },
        props = { text = "Furnace Press: " .. fmt(readings.furnace_press, 1) .. " kPa" },
        style = { color = furnace_pressure_color(readings.furnace_press), font_size = 9, align = "center" }
    })
    
    s:element({
        id = "nav_batch_status",
        type = "label",
        rect = { unit = "px", x = 242, y = H - 85, w = W - 260, h = 14 },
        props = { text = "Status: " .. batch_status_text },
        style = { color = C.text_dim, font_size = 9, align = "center" }
    })
    
    handles.batch.start_btn = s:element({
        id = "batch_start_stop",
        type = "button",
        rect = { unit = "px", x = 242, y = H - 65, w = W - 260, h = 22 },
        props = { text = is_batch_running and "Stop Batch" or "Start Batch" },
        style = { bg = C.green, text = C.bg, font_size = 11, gradient = "#0f4c63", gradient_dir = "vertical" },
        on_click = function()
            if is_batch_running then
                is_batch_running = false
                save_control_settings()
            elseif #smelting_queue > 0 then
                local ok, _ = validate_queue_stock()
                if ok then
                    is_batch_running = true
                    save_control_settings()
                    log_step("batch: started")
                end
            end
            dashboard_render(true)
        end
    })
    
    update_batch_dynamic()
end

function render_footer(surface)
    local footer = s:element({
        id = "footer_bg",
        type = "panel",
        rect = { unit = "px", x = 0, y = H - 18, w = W, h = 18 },
        style = { bg = C.header }
    })

    handles.footer.left = footer:element({
        id = "footer_left",
        type = "label",
        rect = { unit = "px", x = 8, y = 3, w = 120, h = 14 },
        props = { text = "Time: " .. currenttime2 },
        style = { font_size = 8, color = C.text_muted, align = "left" }
    })

    local toggle_w = 120
    local toggle_x = math.floor((W - toggle_w) / 2)
    local active = global_power_on
    handles.footer.power_toggle = footer:element({
        id = "power_toggle",
        type = "button",
        rect = { unit = "px", x = toggle_x, y = 0, w = toggle_w, h = 18 },
        props = { text = "Power Devices: " .. (active and "ON" or "OFF") },
        style = {
            bg = active and C.green or C.bar_bg,
            text = active and C.bg or C.text_dim,
            font_size = 9,
            align = "center",
            gradient = active and "#0f4c63" or "#182133",
            gradient_dir = "vertical"
        },
        on_click = handle_power_toggle
    })

    handles.footer.right = footer:element({
        id = "footer_right",
        type = "label",
        rect = { unit = "px", x = W - 220, y = 3, w = 212, h = 14 },
        props = { text = string.format("Tick %.0f | Refresh %dt", math.floor(elapsed), LIVE_REFRESH_TICKS) },
        style = { font_size = 8, color = C.text_muted, align = "right" }
    })
end

function update_footer_dynamic()
    if handles.footer.left ~= nil then
        handles.footer.left:set_props({ text = "Time: " .. currenttime2 })
    end
    if handles.footer.power_toggle ~= nil then
        local active = global_power_on
        handles.footer.power_toggle:set_props({ text = "Power Devices: " .. (active and "ON" or "OFF") })
        handles.footer.power_toggle:set_style({
            bg = active and C.green or C.bar_bg,
            text = active and C.bg or C.text_dim,
            gradient = active and "#0f4c63" or "#182133"
        })
    end
    if handles.footer.right ~= nil then
        handles.footer.right:set_props({ text = string.format("Tick %.0f | Refresh %dt", math.floor(elapsed), LIVE_REFRESH_TICKS) })
    end
end

function render_overview(surface)
    local ui_vis = global_power_on
    local left_col_x = 8
    local left_col_w = 220

    local entry = selected_ingot_entry()
    local preview = material_preview_lines(requested_recipe, requested_amount)
    local can_start = selected_recipe_can_start()

    s:element({
        id = "selector_bg",
        type = "panel",
        rect = { unit = "px", x = left_col_x, y = 60, w = left_col_w, h = H - 82 },
        props = { visible = ui_vis },
        style = { bg = C.panel }
    })

    local center_x = function(w) return left_col_x + math.floor((left_col_w - w) / 2) end

    if handles.overview.icon == nil then
        handles.overview.icon = s:element({
            id = "selector_icon",
            type = "icon",
            rect = { unit = "px", x = center_x(96), y = 70, w = 96, h = 96 },
            props = { name = tostring(entry[2]), icon_type = "prefab", visible = ui_vis },
            style = { tint = "#FFFFFF" },
        })
    end

    if not global_power_on then
        handles.overview.power_warning = s:element({
            id = "power_warning",
            type = "label",
            rect = { unit = "px", x = center_x(300) + 110, y = 200, w = 300, h = 40 },
            props = { text = "WARNING: TURN ON POWER FIRST" },
            style = { color = C.red, font_size = 14, align = "center", font_weight = "bold" }
        })
    end
    if handles.overview.ingot_name == nil then
        handles.overview.ingot_name = s:element({
            id = "selector_name",
            type = "label",
            rect = { unit = "px", x = center_x(206), y = 170, w = 206, h = 22 },
            props = { text = entry[1], visible = ui_vis },
            style = { color = C.text, font_size = 14, align = "center" },
        })
    end
    if handles.overview.ingot_counter == nil then
        handles.overview.ingot_counter = s:element({
            id = "selector_counter",
            type = "label",
            rect = { unit = "px", x = center_x(206), y = 190, w = 206, h = 16 },
            props = { text = string.format("%d / %d", selected_ingot_index, totalIngots), visible = ui_vis },
            style = { color = C.text_dim, font_size = 10, align = "center" },
        })
    end

    local btn_w = 40
    s:element({
        id = "selector_prev",
        type = "button",
        rect = { unit = "px", x = center_x(2 * btn_w + 20), y = 210, w = btn_w, h = 18 },
        props = { text = "<", visible = ui_vis },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            selected_ingot_index = ((selected_ingot_index - 2) % totalIngots) + 1
            sync_selected_recipe()
            dashboard_render(false)
        end
    })
    s:element({
        id = "selector_next",
        type = "button",
        rect = { unit = "px", x = center_x(2 * btn_w + 20) + btn_w + 20, y = 210, w = btn_w, h = 18 },
        props = { text = ">", visible = ui_vis },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            selected_ingot_index = (selected_ingot_index % totalIngots) + 1
            sync_selected_recipe()
            dashboard_render(false)
        end
    })

    handles.overview.preview_label = s:element({
        id = "preview_label",
        type = "label",
        rect = { unit = "px", x = center_x(178), y = 230, w = 178, h = 12 },
        props = { text = materials_preview_title(), visible = ui_vis },
        style = { color = C.text_dim, font_size = 8, align = "center" },
    })
    handles.overview.preview_1 = s:element({
        id = "preview_1",
        type = "label",
        rect = { unit = "px", x = center_x(178), y = 245, w = 178, h = 12 },
        props = { text = preview[1], visible = ui_vis },
        style = { color = C.text, font_size = 8, align = "center" },
    })
    handles.overview.preview_2 = s:element({
        id = "preview_2",
        type = "label",
        rect = { unit = "px", x = center_x(178), y = 260, w = 178, h = 12 },
        props = { text = preview[2], visible = ui_vis },
        style = { color = C.text, font_size = 8, align = "center" },
    })
    handles.overview.preview_3 = s:element({
        id = "preview_3",
        type = "label",
        rect = { unit = "px", x = center_x(178), y = 275, w = 178, h = 12 },
        props = { text = preview[3], visible = ui_vis },
        style = { color = C.text, font_size = 8, align = "center" },
    })

    local batch_label_w = 70
    local batch_value_w = 30
    local batch_btn_w = 26
    local batch_total_w = batch_label_w + batch_value_w + 2 * batch_btn_w + 8
    local batch_x = center_x(batch_total_w)
    s:element({
        id = "batch_label",
        type = "label",
        rect = { unit = "px", x = batch_x + 20, y = 290, w = batch_label_w, h = 14 },
        props = { text = "Batches", visible = ui_vis },
        style = { color = C.text_dim, font_size = 9, align = "left" },
    })
    if handles.overview.batch_value == nil then
        handles.overview.batch_value = s:element({
            id = "batch_value",
            type = "label",
            rect = { unit = "px", x = batch_x + batch_label_w, y = 290, w = batch_value_w, h = 14 },
            props = { text = tostring(requested_amount), visible = ui_vis },
            style = { color = C.text, font_size = 10, align = "center" },
        })
    end
    s:element({
        id = "batch_dec",
        type = "button",
        rect = { unit = "px", x = batch_x + batch_label_w + batch_value_w, y = 290, w = batch_btn_w, h = 18 },
        props = { text = "-", visible = ui_vis },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            requested_amount = clamp(requested_amount - 1, MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
            dashboard_render(false)
        end
    })
    s:element({
        id = "batch_inc",
        type = "button",
        rect = { unit = "px", x = batch_x + batch_label_w + batch_value_w + batch_btn_w + 4, y = 290, w = batch_btn_w, h = 18 },
        props = { text = "+", visible = ui_vis },
        style = { bg = C.panel_light, text = C.text, font_size = 10 },
        on_click = function()
            requested_amount = clamp(requested_amount + 1, MIN_BATCH_AMOUNT, MAX_BATCH_AMOUNT)
            dashboard_render(false)
        end
    })

    local output_label_w = 90
    local output_value_w = 70
    local output_total_w = output_label_w + output_value_w
    local output_x = center_x(output_total_w)
    s:element({
        id = "output_label",
        type = "label",
        rect = { unit = "px", x = output_x + 20, y = 310, w = output_label_w, h = 14 },
        props = { text = "Output Ingots", visible = ui_vis },
        style = { color = C.text_dim, font_size = 9, align = "left" },
    })
    if handles.overview.output_value == nil then
        handles.overview.output_value = s:element({
            id = "output_value",
            type = "label",
            rect = { unit = "px", x = output_x + output_label_w, y = 310, w = output_value_w, h = 14 },
            props = { text = tostring(selected_output_amount()), visible = ui_vis },
            style = { color = C.accent, font_size = 10, align = "left" },
        })
    end

    local start_btn_w = 150
    local start_bg = C.green
    local start_gradient = "#166534"
    local start_text = C.bg
    local start_label = "Start Smelting"
    if furnace_run_active then
        start_bg = C.red
        start_gradient = "#7F1D1D"
        start_text = "#FFFFFF"
        start_label = "Smelting..."
    elseif not can_start then
        start_bg = C.bar_bg
        start_gradient = "#1B2433"
        start_text = C.text_dim
        start_label = "Missing Materials"
    end
    handles.overview.start_button = s:element({
        id = "start_button",
        type = "button",
        rect = { unit = "px", x = center_x(start_btn_w), y = 330, w = start_btn_w, h = 22 },
        props = { text = start_label, visible = ui_vis },
        style = {
            bg = start_bg,
            text = start_text,
            font_size = 10,
            gradient = start_gradient,
            gradient_dir = "vertical"
        },
        on_click = function()
            if not selected_recipe_can_start() then
                dashboard_render(false)
                return
            end
            start_selected_recipe()
            dashboard_render(true)
        end
    })

    local press_label_w = 85
    local press_value_w = 56
    local press_total_w = press_label_w + press_value_w
    local press_x = center_x(press_total_w)
    s:element({
        id = "fuel_press_label",
        type = "label",
        rect = { unit = "px", x = press_x, y = 355, w = press_label_w, h = 12 },
        props = { text = "Fuel Press", visible = ui_vis },
        style = { color = C.text_dim, font_size = 8, align = "left" },
    })
    if handles.overview.fuel_press_value == nil then
        handles.overview.fuel_press_value = s:element({
            id = "fuel_press_value",
            type = "label",
            rect = { unit = "px", x = press_x + press_label_w, y = 355, w = press_value_w, h = 12 },
            props = { text = fmt(readings.fuel_pa_press, 1) .. " kPa", visible = ui_vis },
            style = { color = C.text, font_size = 8, align = "left" },
        })
    end
    s:element({
        id = "coolant_press_label",
        type = "label",
        rect = { unit = "px", x = press_x, y = 370, w = press_label_w, h = 12 },
        props = { text = "Coolant Press", visible = ui_vis },
        style = { color = C.text_dim, font_size = 8, align = "left" },
    })
    if handles.overview.coolant_press_value == nil then
        handles.overview.coolant_press_value = s:element({
            id = "coolant_press_value",
            type = "label",
            rect = { unit = "px", x = press_x + press_label_w, y = 370, w = press_value_w, h = 12 },
            props = { text = fmt(readings.coolant_pa_press, 1) .. " kPa", visible = ui_vis },
            style = { color = C.text, font_size = 8, align = "left" },
        })
    end


    s:element({
        id = "overview_stats_bg",
        type = "panel",
        rect = { unit = "px", x = 232, y = 60, w = W - 240, h = H - 82 },
        props = { visible = ui_vis },
        style = { bg = C.panel }
    })

    local x0 = 265
    local stat_label_w = 112
    local stat_gap = 114 - 15
    local function stat_line(id, y, label, value, color)
        local label_color = C.text_dim
        if id == "ov_room_press" or id == "ov_room_temp" then
            label_color = C.text_dim
        end
        handles.overview[id .. "_label"] = s:element({
            id = id .. "_label",
            type = "label",
            rect = { unit = "px", x = x0, y = y, w = stat_label_w, h = 14 },
            props = { text = label, visible = ui_vis },
            style = { font_size = 9, color = label_color, align = "left" }
        })
        handles.overview[id] = s:element({
            id = id .. "_value",
            type = "label",
            rect = { unit = "px", x = x0 + stat_gap, y = y, w = 120, h = 14 },
            props = { text = value, visible = ui_vis },
            style = { font_size = 9, color = color or C.text, align = "left" }
        })
    end

    stat_line("ov_temp", 74, "Furnace Temp", furnace_temp_text(readings.furnace_temp), furnace_temp_color(readings.furnace_temp))
    stat_line("ov_press", 90, "Furnace Press", fmt(readings.furnace_press, 1) .. " kPa", furnace_pressure_color(readings.furnace_press))
    stat_line("ov_room_temp", 122, "Room Temp", room_temp_text(readings.room_temp), room_temp_color(readings.room_temp))
    stat_line("ov_room_press", 106, "Room Press", fmt(readings.room_press, 1) .. " kPa", room_pressure_color(readings.room_press))
    stat_line("ov_o2_press", 138, "O2 Pressure", fmt(readings.o2_pa_press, 1) .. " kPa", C.text)
    stat_line("ov_ch4_press", 154, "CH4 Pressure", fmt(readings.ch4_pa_press, 1) .. " kPa", C.text)
    stat_line("ov_reagents", 170, "Input Qty", fmt(readings.furnace_reagents, 2), C.text)
    stat_line("ov_stock", 186, "Recipe Check", stock_ok and "OK" or "LOW", stock_ok and C.green or C.red)
    stat_line("ov_state", 202, "Run State", status_text, status_color)
    
    local left_col_x = 8
    local left_col_w = 206
    local left_col_bottom_y = H - 60


    local btn_w = math.floor((left_col_w - 8) / 2)
    local btn_gap = 8
    local chute_btn_y = left_col_bottom_y - 20
    local flush_btn_y = left_col_bottom_y + 20
    if _G.steel_output_to_vend == nil then _G.steel_output_to_vend = false end
    if handles.overview["ov_chute_toggle_btn"] == nil then
        handles.overview["ov_chute_toggle_btn"] = s:element({
            id = "ov_chute_toggle_btn",
            type = "button",
            rect = { unit = "px", x = left_col_x + 7, y = chute_btn_y + 10, w = left_col_w, h = 18 },
            props = { text = "Steel Output", visible = ui_vis },
            style = {
                bg = C.panel_light,
                text = C.text,
                font_size = 10,
                gradient = "#182133",
                gradient_dir = "vertical"
            },
            on_click = function()
                _G.steel_output_to_vend = not _G.steel_output_to_vend
                set_chute_valve_open(_G.steel_output_to_vend)
                dashboard_render(false)
            end
        })
    end

    local function overview_toggle_button(id, x, y, w, label, active, on_click)
        handles.overview[id] = s:element({
            id = id,
            type = "button",
            rect = { unit = "px", x = x, y = y, w = w, h = 18 },
            props = { text = string.format("%s: %s", label, active and "ON" or "OFF"), visible = ui_vis },
            style = {
                bg = active and C.accent or C.panel_light,
                text = active and C.bg or C.text,
                font_size = 8,
                gradient = active and "#0f4c63" or "#182133",
                gradient_dir = "vertical"
            },
            on_click = on_click
        })
    end
    overview_toggle_button("ov_flush_toggle", left_col_x + 7, flush_btn_y, btn_w, "Flush", flush_enabled, function()
        flush_enabled = not flush_enabled
        dashboard_render(false)
    end)
    overview_toggle_button("ov_vent_toggle", left_col_x + btn_w + btn_gap + 7, flush_btn_y, btn_w, "Vent", vent_enabled, function()
        vent_enabled = not vent_enabled
        dashboard_render(false)
    end)

    local x0 = 225
    s:element({
        id = "silo_totals_title",
        type = "label",
        rect = { unit = "px", x = x0 - 44, y = 240, w = 234, h = 12 },
        props = { text = "Silo: Ore Quantity", visible = ui_vis },
        style = { font_size = 8, color = "#7bbcc6", align = "center" }
    })

    local silo_rows = math.ceil(#MATERIAL_ORDER)
    local silo_col_gap = 118 - 20
    for i, mat in ipairs(MATERIAL_ORDER) do
        local col = ((i - 1) >= silo_rows) and 1 or 0
        local row = (i - 1) % silo_rows
        local col_x = x0 + (col * silo_col_gap)
        local y = 255 + row * 9
        local key = SILO_HANDLE_KEY[mat]
        local ore_amount = read_silo_ore_amount(mat)

        s:element({
            id = key .. "_label",
            type = "label",
            rect = { unit = "px", x = col_x + 44, y = y, w = 58, h = 9 },
            props = { text = mat, visible = ui_vis },
            style = { font_size = 8, color = C.text_dim, align = "left" }
        })

        if handles.overview[key] == nil then
            handles.overview[key] = s:element({
                id = key .. "_value",
                type = "label",
                rect = { unit = "px", x = col_x + 78, y = y, w = 54, h = 9 },
                props = { text = fmt(ore_amount, 0), visible = ui_vis },
                style = { font_size = 8, color = stock_amount_color(ore_amount), align = "left" }
            })
        end
    end
    if handles.overview.vend_title == nil then
        handles.overview.vend_title = s:element({
            id = "vend_title",
            type = "label",
            rect = { unit = "px", x = x0 + 50, y = 240, w = 234, h = 12 },
            props = { text = "Vend Inventory", visible = ui_vis },
            style = { font_size = 8, color = "#7bbcc6", align = "center" }
        })
    end

    if handles.overview.vend_free_normal_label == nil then
        handles.overview.vend_free_normal_label = s:element({
            id = "vend_free_normal_label",
            type = "label",
            rect = { unit = "px", x = x0 + 127, y = 255, w = 58, h = 9 },
            props = { text = "Slots: Normal", visible = ui_vis },
            style = { font_size = 8, color = C.text_dim, align = "right" }
        })
    end

    if handles.overview.vend_free_special_label == nil then
        handles.overview.vend_free_special_label = s:element({
            id = "vend_free_special_label",
            type = "label",
            rect = { unit = "px", x = x0 + 127, y = 265, w = 58, h = 9 },
            props = { text = "Slots: Special", visible = ui_vis },
            style = { font_size = 8, color = C.text_dim, align = "right" }
        })
    end

    local nf = readings.vend_normal_free
    local af = readings.vend_alloy_free
    if handles.overview.ov_vend_free_normal == nil then
        handles.overview.ov_vend_free_normal = s:element({
            id = "vend_free_normal_value",
            type = "label",
            rect = { unit = "px", x = x0 + 187, y = 255, w = 54, h = 9 },
            props = { text = nf ~= nil and tostring(nf) or "--", visible = ui_vis },
            style = { font_size = 8, color = vend_free_slots_color(nf), align = "left" }
        })
    end
    if handles.overview.ov_vend_free_special == nil then
        handles.overview.ov_vend_free_special = s:element({
            id = "vend_free_special_value",
            type = "label",
            rect = { unit = "px", x = x0 + 187, y = 265, w = 54, h = 9 },
            props = { text = af ~= nil and tostring(af) or "--", visible = ui_vis },
            style = { font_size = 8, color = vend_free_slots_color(af), align = "left" }
        })
    end

    local vend_col_gap = 118 - 20
    local vend_rows = math.ceil(#ingots)
    for i, ingot in ipairs(ingots) do
        local col = ((i - 1) >= vend_rows) and 1 or 0
        local row = (i - 1) % vend_rows
        local col_x = x0 + (col * vend_col_gap) + 120
        local vy = 280 + row * 9
        local ingot_name = ingot[1]:gsub(" Ingot", "")
        local recipe_idx = ingot[3]
        local ingot_hash = recipe_hashes[recipe_idx]
        local qty = ingot_hash and (readings.vend_ingot_totals[ingot_hash] or 0) or 0
        local vkey = "ov_vend_ingot_" .. i

        if handles.overview[vkey .. "_label"] == nil then
            handles.overview[vkey .. "_label"] = s:element({
                id = vkey .. "_label",
                type = "label",
                rect = { unit = "px", x = col_x + 15, y = vy, w = 58, h = 9 },
                props = { text = ingot_name, visible = ui_vis },
                style = { font_size = 8, color = C.text_dim, align = "left" }
            })
        end

        if handles.overview[vkey] == nil then
            handles.overview[vkey] = s:element({
                id = vkey .. "_value",
                type = "label",
                rect = { unit = "px", x = col_x + 65, y = vy, w = 54, h = 9 },
                props = { text = tostring(qty), visible = ui_vis },
                style = { font_size = 8, color = stock_amount_color(qty), align = "left" }
            })
        end
    end
end

function update_overview_dynamic()
    if not global_power_on then return end

        if handles.overview["ov_chute_toggle_btn"] ~= nil then
            local output_active = _G.steel_output_to_vend
            local output_label = output_active and "Steel Output: Vending" or "Steel Output: Silo"
            handles.overview["ov_chute_toggle_btn"]:set_props({ text = output_label })
            handles.overview["ov_chute_toggle_btn"]:set_style({
                bg = output_active and C.accent or C.panel_light,
                text = output_active and C.bg or C.text,
                font_size = 10,
                gradient = output_active and "#0f4c63" or "#182133",
                gradient_dir = "vertical"
            })
        end
    local function set(id, text, color, label_color)
        local h = handles.overview[id]
        if h == nil then return end
        h:set_props({ text = text })
        h:set_style({ font_size = 9, color = color or C.text, align = "left" })

        local label = handles.overview[id .. "_label"]
        if label ~= nil then
            label:set_style({ font_size = 9, color = label_color or C.text_dim, align = "left" })
        end
    end

    local function set_toggle(id, label, active)
        local h = handles.overview[id]
        if h == nil then return end
        h:set_props({ text = string.format("%s: %s", label, active and "ON" or "OFF") })
        h:set_style({
            bg = active and C.accent or C.panel_light,
            text = active and C.bg or C.text,
            font_size = 8,
            gradient = active and "#0f4c63" or "#182133",
            gradient_dir = "vertical"
        })
    end

    local entry = selected_ingot_entry()
    local preview = material_preview_lines(requested_recipe, requested_amount)
    local can_start = selected_recipe_can_start()

    if handles.overview.icon ~= nil then
        handles.overview.icon:set_props({ name = tostring(entry[2]), icon_type = "prefab" })
    end
    if handles.overview.ingot_name ~= nil then
        handles.overview.ingot_name:set_props({ text = entry[1] })
    end
    if handles.overview.ingot_counter ~= nil then
        handles.overview.ingot_counter:set_props({ text = string.format("%d / %d", selected_ingot_index, totalIngots) })
    end
    if handles.overview.batch_value ~= nil then
        handles.overview.batch_value:set_props({ text = tostring(requested_amount) })
    end
    if handles.overview.output_value ~= nil then
        handles.overview.output_value:set_props({ text = tostring(selected_output_amount()) })
    end
    if handles.overview.preview_1 ~= nil then
        handles.overview.preview_1:set_props({ text = preview[1] })
    end
    if handles.overview.preview_2 ~= nil then
        handles.overview.preview_2:set_props({ text = preview[2] })
    end
    if handles.overview.preview_3 ~= nil then
        handles.overview.preview_3:set_props({ text = preview[3] })
    end
    if handles.overview.start_button ~= nil then
        local start_bg = C.green
        local start_gradient = "#166534"
        local start_text = C.bg
        local start_label = "Start Smelting"
        if furnace_run_active then
            start_bg = C.red
            start_gradient = "#7F1D1D"
            start_text = "#FFFFFF"
            start_label = "Smelting..."
        elseif not can_start then
            start_bg = C.bar_bg
            start_gradient = "#1B2433"
            start_text = C.text_dim
            start_label = "Missing Materials"
        end

        handles.overview.start_button:set_props({ text = start_label })
        handles.overview.start_button:set_style({
            bg = start_bg,
            text = start_text,
            font_size = 10,
            gradient = start_gradient,
            gradient_dir = "vertical"
        })
    end

    if handles.overview.fuel_press_value ~= nil then
        local v = readings.fuel_pa_press
        handles.overview.fuel_press_value:set_props({ text = fmt(v, 1) .. " kPa" })
        handles.overview.fuel_press_value:set_style({ color = pressure_color(v), font_size = 8, align = "right" })
        local label = handles.overview["fuel_press_value_label"] or handles.overview["fuel_press_label"]
        if label then label:set_style({ color = pressure_color(v), font_size = 8, align = "left" }) end
    end

    if handles.overview.coolant_press_value ~= nil then
        local v = readings.coolant_pa_press
        handles.overview.coolant_press_value:set_props({ text = fmt(v, 1) .. " kPa" })
        handles.overview.coolant_press_value:set_style({ color = pressure_color(v), font_size = 8, align = "right" })
        local label = handles.overview["coolant_press_value_label"] or handles.overview["coolant_press_label"]
        if label then label:set_style({ color = pressure_color(v), font_size = 8, align = "left" }) end
    end

    if handles.overview.ov_o2_press ~= nil then
        local v = readings.o2_pa_press
        local c = pressure_color(v)
        handles.overview.ov_o2_press:set_props({ text = fmt(v, 1) .. " kPa" })
        handles.overview.ov_o2_press:set_style({ color = c, font_size = 9, align = "left" })
        if handles.overview.ov_o2_press_label ~= nil then
            handles.overview.ov_o2_press_label:set_style({ color = C.text, font_size = 9, align = "left" })
        end
    end
    if handles.overview.ov_ch4_press ~= nil then
        local v = readings.ch4_pa_press
        local c = pressure_color(v)
        handles.overview.ov_ch4_press:set_props({ text = fmt(v, 1) .. " kPa" })
        handles.overview.ov_ch4_press:set_style({ color = c, font_size = 9, align = "left" })
        if handles.overview.ov_ch4_press_label ~= nil then
            handles.overview.ov_ch4_press_label:set_style({ color = C.text, font_size = 9, align = "left" })
        end
    end

    if handles.overview.preview_label ~= nil then
        handles.overview.preview_label:set_props({ text = materials_preview_title() })
    end

    set("ov_temp", furnace_temp_text(readings.furnace_temp), furnace_temp_color(readings.furnace_temp), C.text)
    set("ov_press", fmt(readings.furnace_press, 1) .. " kPa", furnace_pressure_color(readings.furnace_press), C.text)
    local room_press_color = room_pressure_color(readings.room_press)
    local room_temp_color_val = room_temp_color(readings.room_temp)
    set("ov_room_press", fmt(readings.room_press, 1) .. " kPa", room_press_color, C.text)
    if handles.overview.ov_room_press_label ~= nil then
        handles.overview.ov_room_press_label:set_style({ color = C.text_dim, font_size = 9, align = "left" })
    end
    set("ov_room_temp", room_temp_text(readings.room_temp), room_temp_color_val, C.text)
    if handles.overview.ov_room_temp_label ~= nil then
        handles.overview.ov_room_temp_label:set_style({ color = C.text_dim, font_size = 9, align = "left" })
    end
    set("ov_o2_press", fmt(readings.o2_pa_press, 1) .. " kPa", pressure_color(readings.o2_pa_press))
    set("ov_ch4_press", fmt(readings.ch4_pa_press, 1) .. " kPa", pressure_color(readings.ch4_pa_press))
    set("ov_reagents", fmt(readings.furnace_reagents, 2), C.text)
    set("ov_stock", stock_ok and "OK" or "LOW", stock_ok and C.green or C.red)
    set("ov_state", status_text, status_color)

    set_toggle("ov_flush_toggle", "Flush", flush_enabled)
    set_toggle("ov_vent_toggle", "Vent", vent_enabled)

    for _, mat in ipairs(MATERIAL_ORDER) do
        local key = SILO_HANDLE_KEY[mat]
        local h = handles.overview[key]
        if h ~= nil then
            local ore_amount = read_silo_ore_amount(mat)
            h:set_props({ text = fmt(ore_amount, 0) })
            h:set_style({ font_size = 8, color = stock_amount_color(ore_amount), align = "left" })
        end
    end

    local nf2 = readings.vend_normal_free
    local af2 = readings.vend_alloy_free
    if handles.overview.ov_vend_free_normal ~= nil then
        handles.overview.ov_vend_free_normal:set_props({ text = nf2 ~= nil and tostring(nf2) or "--" })
        handles.overview.ov_vend_free_normal:set_style({ font_size = 8, color = vend_free_slots_color(nf2), align = "left" })
    end
    if handles.overview.ov_vend_free_special ~= nil then
        handles.overview.ov_vend_free_special:set_props({ text = af2 ~= nil and tostring(af2) or "--" })
        handles.overview.ov_vend_free_special:set_style({ font_size = 8, color = vend_free_slots_color(af2), align = "left" })
    end

    for i, ingot in ipairs(ingots) do
        local vkey = "ov_vend_ingot_" .. i
        local vh = handles.overview[vkey]
        if vh ~= nil then
            local ingot_hash = recipe_hashes[ingot[3]]
            local qty = ingot_hash and (readings.vend_ingot_totals[ingot_hash] or 0) or 0
            vh:set_props({ text = tostring(qty) })
            vh:set_style({ font_size = 8, color = stock_amount_color(qty), align = "left" })
        end
    end

    local vend_active = (role_is_bound(roles.vend_normal) or role_is_bound(roles.vend_alloy)) and global_power_on
    local v_props = { visible = vend_active }

    if handles.overview.vend_title then handles.overview.vend_title:set_props(v_props) end
    if handles.overview.vend_free_normal_label then handles.overview.vend_free_normal_label:set_props(v_props) end
    if handles.overview.ov_vend_free_normal then handles.overview.ov_vend_free_normal:set_props(v_props) end
    if handles.overview.vend_free_special_label then handles.overview.vend_free_special_label:set_props(v_props) end
    if handles.overview.ov_vend_free_special then handles.overview.ov_vend_free_special:set_props(v_props) end

    for i = 1, #ingots do
        local vkey = "ov_vend_ingot_" .. i
        if handles.overview[vkey .. "_label"] then handles.overview[vkey .. "_label"]:set_props(v_props) end
        if handles.overview[vkey] then handles.overview[vkey]:set_props(v_props) end
    end

    if handles.overview["ov_chute_toggle_btn"] then handles.overview["ov_chute_toggle_btn"]:set_props({ visible = global_power_on }) end
end

function update_settings_dynamic()
    return
end

function render_settings(surface)
    local panel_x, panel_y = 8, 60
    local panel_w, panel_h = W - 16, H - 82
    local tab_y = panel_y + 8

    s:element({
        id = "settings_bg",
        type = "panel",
        rect = { unit = "px", x = panel_x, y = panel_y, w = panel_w, h = panel_h },
        style = { bg = "#0A0A15" }
    })

    local subtabs = {
        { id = "settings_flow", text = "MAIN", key = "flow" },
        { id = "settings_silos", text = "SILOS", key = "silos" },
        { id = "settings_control", text = "CONTROL", key = "control" },
    }

    local settings_tab_count = #subtabs
    local settings_button_w = math.floor((panel_w - 18) / settings_tab_count)

    for i, tab in ipairs(subtabs) do
        local active = (settings_subtab == tab.key)
        local target = tab.key
        s:element({
            id = tab.id,
            type = "button",
            rect = { unit = "px", x = panel_x + 6 + (i - 1) * settings_button_w, y = tab_y, w = settings_button_w - 2, h = 20 },
            props = { text = tab.text },
            style = {
                bg = active and C.accent or C.panel_light,
                text = active and C.bg or C.text,
                font_size = 8,
                gradient = active and "#0f4c63" or "#182133",
                gradient_dir = "vertical"
            },
            on_click = function()
                settings_subtab = target
                settings_device_page = 1
                dashboard_render(true)
            end
        })
    end

    local content_y = tab_y + 30

    if settings_subtab ~= "control" then
        local grouped_roles = current_settings_roles()

        local y = content_y + 18
        local items_per_page = 12
        local total_pages = math.ceil(#grouped_roles / items_per_page)
        local start_idx = (settings_device_page - 1) * items_per_page + 1
        local end_idx = math.min(#grouped_roles, start_idx + items_per_page - 1)

        for i = start_idx, end_idx do
            local role = grouped_roles[i]
            local def = role ~= nil and role_defs[role.index] or nil
            local cache = cached_role_dropdowns[def.key] or { opts = { "Select device..." }, cands = {}, sel = 0 }
            local options, candidates, selected_idx = cache.opts, cache.cands, cache.sel
            local row_candidates = candidates
            settings_dropdown_selected[def.key] = selected_idx

            s:element({
                id = "dev_label_" .. def.key,
                type = "label",
                rect = { unit = "px", x = panel_x + 14, y = y + 2, w = 125, h = 14 },
                props = { text = role.label },
                style = { font_size = 8, color = C.text, align = "left" }
            })

            s:element({
                id = "dev_select_" .. def.key,
                type = "select",
                rect = { unit = "px", x = panel_x + 131, y = y, w = 300, h = 20 },
                props = {
                    options = table.concat(options, "|"),
                    selected = settings_dropdown_selected[def.key],
                    open = settings_dropdown_open[def.key],
                },
                on_toggle = function()
                    local opening = settings_dropdown_open[def.key] ~= "true"
                    if opening then
                        local devs = device_list_safe()
                        local opts, cands, sel = build_filtered_device_options(devs, role)
                        cached_role_dropdowns[def.key] = { opts = opts, cands = cands, sel = sel }
                    end
                    settings_dropdown_open[def.key] = opening and "true" or "false"
                    dashboard_render(true)
                end,
                on_change = function(optionIndex)
                    local selected_option = tonumber(optionIndex) or 0
                    settings_dropdown_selected[def.key] = selected_option
                    settings_dropdown_open[def.key] = "false"

                    if selected_option == 0 then
                        role.prefab = 0
                        role.namehash = 0
                    else
                        local picked = row_candidates[selected_option]
                        if picked ~= nil then
                            role.prefab = tonumber(picked.prefab_hash) or 0
                            role.namehash = tonumber(picked.name_hash) or 0
                        end
                    end

                    save_role_to_memory(role)
                    if cached_role_dropdowns[def.key] then
                        cached_role_dropdowns[def.key].sel = selected_option
                    end
                    dashboard_render(true)
                end
            })

            y = y + 22
        end

        if total_pages > 1 then
            local page_y = y + 5
            s:element({
                id = "settings_prev_page",
                type = "button",
                rect = { unit = "px", x = panel_x + 14, y = page_y, w = 60, h = 18 },
                props = { text = "< Prev" },
                style = { bg = C.panel_light, text = settings_device_page > 1 and C.text or C.text_dim, font_size = 9, gradient = "#292929ff", gradient_dir = "vertical" },
                on_click = function()
                    if settings_device_page > 1 then
                        settings_device_page = settings_device_page - 1
                        dashboard_render(true)
                    end
                end
            })

            s:element({
                id = "settings_page_label",
                type = "label",
                rect = { unit = "px", x = panel_x + 84, y = page_y + 2, w = 150, h = 14 },
                props = { text = "Page " .. settings_device_page .. " / " .. total_pages },
                style = { font_size = 9, color = C.accent, align = "center" }
            })

            s:element({
                id = "settings_next_page",
                type = "button",
                rect = { unit = "px", x = panel_x + 244, y = page_y, w = 60, h = 18 },
                props = { text = "Next >" },
                style = { bg = C.panel_light, text = settings_device_page < total_pages and C.text or C.text_dim, font_size = 9, gradient = "#292929ff", gradient_dir = "vertical" },
                on_click = function()
                    if settings_device_page < total_pages then
                        settings_device_page = settings_device_page + 1
                        dashboard_render(true)
                    end
                end
            })
        end

        return
    end

    function row(label, value, y, on_change)
        s:element({
            id = "ctl_label_" .. label,
            type = "label",
            rect = { unit = "px", x = panel_x + 18, y = y + 2, w = 190, h = 16 },
            props = { text = label },
            style = { font_size = 9, color = C.text, align = "left" }
        })
        s:element({
            id = "ctl_input_" .. label,
            type = "textinput",
            rect = { unit = "px", x = panel_x + 212, y = y, w = 110, h = 20 },
            props = { value = value, placeholder = value },
            on_change = on_change
        })
    end

    s:element({
        id = "control_title",
        type = "label",
        rect = { unit = "px", x = panel_x + 14, y = content_y, w = panel_w - 28, h = 14 },
        props = { text = "Runtime Controls" },
        style = { font_size = 10, color = C.accent, align = "left" }
    })

    local y = content_y + 22
    row("Furnace activation - Max Temp (K)", ui_max_temp_hard, y, function(v)
        max_temp_hard = to_number_or(v, max_temp_hard)
        save_control_settings()
    end)
    y = y + 24

    row("Refresh Ticks (UI)", ui_live_refresh, y, function(v)
        LIVE_REFRESH_TICKS = to_number_or(v, LIVE_REFRESH_TICKS)
        save_control_settings()
    end)
    
    y = y + 24
    local label = power_target_all and "All Devices" or "Smelting Devices Only"
    s:element({
        id = "row_power_target_lbl",
        type = "label",
        rect = { unit = "px", x = panel_x + 18, y = y + 2, w = 150, h = 14 },
        props = { text = "Power Target" },
        style = { font_size = 9, color = C.text, align = "left" }
    })
    s:element({
        id = "row_power_target_btn",
        type = "button",
        rect = { unit = "px", x = panel_x + 212, y = y, w = 150, h = 18 },
        props = { text = label },
        style = { bg = C.panel_light, text = C.text, font_size = 9, gradient = "#292929ff", gradient_dir = "vertical" },
        on_click = function()
            power_target_all = not power_target_all
            save_control_settings()
            dashboard_render(true)
        end
    })

    y = y + 30
    s:element({
        id = "gas_mix_header",
        type = "label",
        rect = { unit = "px", x = panel_x + 14, y = y, w = panel_w - 28, h = 14 },
        props = { text = "Gas Mix" },
        style = { font_size = 10, color = C.accent, align = "left" }
    })

    y = y + 18
    local gas_mix_opts = {}
    for _, opt in ipairs(GAS_MIX_OPTIONS) do
        table.insert(gas_mix_opts, opt.label)
    end
    s:element({
        id = "gas_mix_select",
        type = "select",
        rect = { unit = "px", x = panel_x + 14, y = y, w = 220, h = 20 },
        props = {
            options = table.concat(gas_mix_opts, "|"),
            selected = gas_mix_index - 1,
            open = gas_mix_dropdown_open,
        },
        on_toggle = function()
            gas_mix_dropdown_open = (gas_mix_dropdown_open == "true") and "false" or "true"
            dashboard_render(true)
        end,
        on_change = function(optionIndex)
            local idx = (tonumber(optionIndex) or 0) + 1
            gas_mix_index = clamp(math.floor(idx), 1, #GAS_MIX_OPTIONS)
            gas_mix_dropdown_open = "false"
            save_control_settings()
            local mixer = roles.fuel_mixer
            if role_is_bound(mixer) then
                local opt = GAS_MIX_OPTIONS[gas_mix_index] or GAS_MIX_OPTIONS[1]
                safe_batch_write_name(mixer.prefab, mixer.namehash, LT.Setting, opt.setting)
            end
            dashboard_render(true)
        end
    })

    y = y + 24
    s:element({
        id = "gas_mix_hint",
        type = "label",
        rect = { unit = "px", x = panel_x + 14, y = y, w = panel_w - 28, h = 12 },
        props = { text = "Oxidiser goes to Input 1 on the Mixer" },
        style = { font_size = 8, color = C.text_dim, align = "left" }
    })

    y = y + 18
    s:element({
        id = "mole_mix_lbl",
        type = "label",
        rect = { unit = "px", x = panel_x + 18, y = y + 2, w = 150, h = 14 },
        props = { text = "Mole-based Mixing (Experimental)" },
        style = { font_size = 9, color = C.text, align = "left" }
    })
    local mole_active = gas_mix_mole_based
    s:element({
        id = "mole_mix_btn",
        type = "button",
        rect = { unit = "px", x = panel_x + 212, y = y, w = 150, h = 18 },
        props = { text = mole_active and "ON  (ratio feedback active)" or "OFF (nominal setting only)" },
        style = {
            bg = mole_active and C.accent or C.panel_light,
            text = mole_active and C.bg or C.text,
            font_size = 9,
            gradient = mole_active and "#0f4c63" or "#292929ff",
            gradient_dir = "vertical"
        },
        on_click = function()
            gas_mix_mole_based = not gas_mix_mole_based
            save_control_settings()
            dashboard_render(true)
        end
    })
end

-- ==================== RENDER ENTRY ====================

dashboard_render = function(force_rebuild)
    log_ui("dashboard_render: begin")
    if force_rebuild == nil then force_rebuild = true end

    local desired = view or "overview"
    if surfaces[desired] == nil then desired = "overview" end
    s = surfaces[desired]

    if force_rebuild or handles.view ~= desired then
        s:clear()
        reset_handles()

        s:element({
            id = "bg",
            type = "panel",
            rect = { unit = "px", x = 0, y = 0, w = W, h = H },
            style = { bg = C.bg }
        })

        render_header()
        render_nav(surface)

        if desired == "overview" then
            render_overview()
        elseif desired == "batch" then
            render_batch()
        else
            render_settings()
        end

        render_footer()
        handles.view = desired
        ss.ui.activate(desired)
        s:commit()
        log_ui("dashboard_render: full rebuild commit")
        return
    end

    update_nav_dynamic()
    update_footer_dynamic()
    if desired == "overview" then
        update_overview_dynamic()
    elseif desired == "batch" then
        update_batch_dynamic()
    elseif desired == "settings" then
        update_settings_dynamic()
    end

    ss.ui.activate(desired)
    s:commit()
    log_ui("dashboard_render: incremental commit")
end

set_view = function(name)
    local desired = name or "overview"
    if surfaces[desired] == nil then desired = "overview" end
    view = desired
    s = surfaces[desired]
    ss.ui.activate(desired)
    log_ui("set_view: " .. tostring(desired))
    safe_call("set_view dashboard_render", function()
        dashboard_render(true)
    end)
end

-- ==================== SERIALIZATION ====================

function serialize()
    log_step("serialize: begin")
    local state = {
        view = view,
        settings_subtab = settings_subtab,
        settings_device_page = settings_device_page,
        selected_ingot_index = selected_ingot_index,
        requested_recipe = requested_recipe,
        requested_amount = requested_amount,
        furnace_run_active = furnace_run_active,
        flush_enabled = flush_enabled,
        vent_enabled = vent_enabled,
        smelting_queue = smelting_queue,
        is_batch_running = is_batch_running,
        global_power_on = global_power_on,
        power_target_all = power_target_all,
        gas_mix_index = gas_mix_index,
    }
    local ok, json = pcall(util.json.encode, state)
    if not ok then return nil end
    log_step("serialize: success")
    return json
end

function deserialize(blob)
    log_step("deserialize: begin")
    if type(blob) ~= "string" or blob == "" then return end
    local ok, decoded = pcall(util.json.decode, blob)
    if not ok or type(decoded) ~= "table" then return end

    if type(decoded.view) == "string" then view = decoded.view end
    if type(decoded.settings_subtab) == "string" then settings_subtab = decoded.settings_subtab end
    settings_device_page = to_number_or(decoded.settings_device_page, settings_device_page)
    selected_ingot_index = clamp(math.floor(to_number_or(decoded.selected_ingot_index, selected_ingot_index)), 1, totalIngots)
    requested_recipe = to_number_or(decoded.requested_recipe, requested_recipe)
    requested_amount = to_number_or(decoded.requested_amount, requested_amount)
    furnace_run_active = decoded.furnace_run_active and true or false
    flush_enabled = decoded.flush_enabled and true or false
    vent_enabled = decoded.vent_enabled and true or false
    if type(decoded.smelting_queue) == "table" then smelting_queue = decoded.smelting_queue end
    is_batch_running = (decoded.is_batch_running == true)
    if decoded.global_power_on ~= nil then global_power_on = (decoded.global_power_on == true) end
    if decoded.power_target_all ~= nil then power_target_all = (decoded.power_target_all == true) end
    if decoded.gas_mix_index ~= nil then gas_mix_index = clamp(math.floor(to_number_or(decoded.gas_mix_index, 1)), 1, #GAS_MIX_OPTIONS) end
    normalize_settings_subtab()
    sync_selected_recipe()
    log_step("deserialize: applied saved state")
end

-- ==================== BOOT ====================

load_roles_from_memory()
local boot_devs = device_list_safe()
for _, def in ipairs(role_defs) do
    local role = roles[def.key]
    if role ~= nil and role_is_bound(role) then
        local label = nil
        for _, dev in ipairs(boot_devs) do
            if (tonumber(dev.prefab_hash) or 0) == (tonumber(role.prefab) or 0)
                and (tonumber(dev.name_hash) or 0) == (tonumber(role.namehash) or 0) then
                label = tostring(dev.display_name or "")
                break
            end
        end
        if label == nil or label == "" then
            label = resolve_name_hash(role.namehash)
        end
        cached_role_dropdowns[def.key] = { opts = { "Select device...", label }, cands = {}, sel = 1 }
    end
end

for _, role_key in ipairs(MATERIAL_ORDER) do
    local s_key = silo_role_by_material[role_key]
    local s_role = roles[s_key]
    if s_role and role_is_bound(s_role) then
        safe_batch_write_name(s_role.prefab, s_role.namehash, LT.Open, 0)
    end
end

load_control_settings()
load_smelting_queue()
sync_selected_recipe()
normalize_settings_subtab()

if is_batch_running then
    is_recovery_active = true
    recovery_timer = 20
    recovery_phase = 0
    log_step("boot: active batch detected - entering failsafe recovery")
end

update_readings()

last_activity_reagents = readings.furnace_reagents or 0
last_activity_import = readings.furnace_import_count or 0
last_activity_export = readings.furnace_export_count or 0
furnace_stuck_ticks = 0

update_vending_readings()

if not global_power_on then
    log_step("boot: global power is OFF - silencing devices")
    for _, role in pairs(roles) do
        if role_is_bound(role) then
            local is_storage = role.key:find("silo") or role.key:find("vend")
            if power_target_all or not is_storage then
                safe_batch_write_name(role.prefab, role.namehash, LT.On, 0)
            end
        end
    end
    if power_target_all then
        for _, p_hash in ipairs(OTHER_PREFABS or {}) do
            safe_batch_write_prefab(p_hash, LT.On, 0)
        end
    end
else
    log_step("boot: global power is ON - ensuring devices are active")
    for _, role in pairs(roles) do
        if role_is_bound(role) then
            local is_storage = role.key:find("silo") or role.key:find("vend")
            if power_target_all or not is_storage then
                safe_batch_write_name(role.prefab, role.namehash, LT.On, 1)
            end
        end
    end
    if power_target_all then
        for _, p_hash in ipairs(OTHER_PREFABS or {}) do
            safe_batch_write_prefab(p_hash, LT.On, 1)
        end
    end
end
log_step("boot: initialization complete")
safe_call("boot set_view", function()
    set_view(view)
end)

-- ==================== MAIN LOOP ====================

local tick = 0
while true do
    tick = tick + 1
    elapsed = elapsed + 1
    currenttime = util.game_time() or 0
    currenttime2 = util.clock_time()

    safe_call("main_logic_tick", function()
        main_logic_tick(tick)
    end)

    if tick % LIVE_REFRESH_TICKS == 0 then
        log_ui("loop: dashboard refresh")
        update_vending_readings()
        safe_call("loop dashboard_render", function()
            dashboard_render(false)
        end)
    end

    ic.yield()
end
