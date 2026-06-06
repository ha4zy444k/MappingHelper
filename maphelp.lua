-- =========================================================
-- House Desc & Web API Integration (MERGED)
-- Взято:
-- 1 скрипт:
--  - help_notif
--  - парсинг
--  - команды house_info / trailer_info / biz_info
--  - автокопирование ника
--
-- 2 скрипт:
--  - весь UI
--  - очередь
--  - API
--  - стили
--  - массовая отправка
-- =========================================================

script_name("House Desc & Web API Integration (Merged)")
script_author("haz1k & AI")
script_version('0.1')

local sampev = require('lib.samp.events')
local imgui = require 'imgui'
local key = require 'vkeys'
local encoding = require 'encoding'
local cjson = require 'cjson'
local ffi = require 'ffi'
local dlstatus = require('moonloader').download_status

ffi.cdef[[
    typedef struct _STARTUPINFOA {
        unsigned long cb;
        char* lpReserved;
        char* lpDesktop;
        char* lpTitle;
        unsigned long dwX;
        unsigned long dwY;
        unsigned long dwXSize;
        unsigned long dwYSize;
        unsigned long dwXCountChars;
        unsigned long dwYCountChars;
        unsigned long dwFillAttribute;
        unsigned long dwFlags;
        unsigned short wShowWindow;
        unsigned short cbReserved2;
        char* lpReserved2;
        void* hStdInput;
        void* hStdOutput;
        void* hStdError;
    } STARTUPINFOA, *LPSTARTUPINFOA;

    typedef struct _PROCESS_INFORMATION {
        void* hProcess;
        void* hThread;
        unsigned long dwProcessId;
        unsigned long dwThreadId;
    } PROCESS_INFORMATION, *LPPROCESS_INFORMATION;

    int CreateProcessA(
        const char* lpApplicationName,
        char* lpCommandLine,
        void* lpProcessAttributes,
        void* lpThreadAttributes,
        int bInheritHandles,
        unsigned long dwCreationFlags,
        void* lpEnvironment,
        const char* lpCurrentDirectory,
        LPSTARTUPINFOA lpStartupInfo,
        LPPROCESS_INFORMATION lpProcessInformation
    );

    int CloseHandle(void* hObject);
]]

encoding.default = 'CP1251'
u8 = encoding.UTF8

local API_URL = "https://map.queen-creek.ru/api/forms_create.php"

-- =========================================================
-- GITHUB AUTOUPDATE CONFIG
-- Р—Р°РјРµРЅРё РЅР° СЃРІРѕРё РґР°РЅРЅС‹Рµ РїРµСЂРµРґ РїСѓР±Р»РёРєР°С†РёРµР№:
--   GITHUB_USER        вЂ” С‚РІРѕР№ РЅРёРє РЅР° GitHub
--   GITHUB_REPO        вЂ” РЅР°Р·РІР°РЅРёРµ СЂРµРїРѕР·РёС‚РѕСЂРёСЏ
--   GITHUB_BRANCH      вЂ” РІРµС‚РєР° (main РёР»Рё master)
--   GITHUB_SCRIPT_PATH вЂ” РїСѓС‚СЊ Рє .lua С„Р°Р№Р»Сѓ РІ СЂРµРїРѕР·РёС‚РѕСЂРёРё
-- =========================================================
local GITHUB_USER        = "ha4zy444k"
local GITHUB_REPO        = "MappingHelper"
local GITHUB_BRANCH      = "main"
local GITHUB_SCRIPT_PATH = "maphelp.lua"
local GITHUB_VERSION_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/version.json"
local GITHUB_SCRIPT_URL  = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/" .. GITHUB_BRANCH .. "/" .. GITHUB_SCRIPT_PATH

--[[
РџСЂРёРјРµСЂ version.json, РєРѕС‚РѕСЂС‹Р№ РЅСѓР¶РЅРѕ РїРѕР»РѕР¶РёС‚СЊ РІ РєРѕСЂРµРЅСЊ СЂРµРїРѕР·РёС‚РѕСЂРёСЏ:
{
    "version": "11.1",
    "download_url": "https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO_NAME/main/maphelp.lua",
    "changelog": [
        "РќРѕРІР°СЏ С„РёС‡Р° 1",
        "Р�СЃРїСЂР°РІР»РµРЅ Р±Р°Рі X"
    ]
}
РџРѕР»Рµ "download_url" РІ version.json РёРјРµРµС‚ РїСЂРёРѕСЂРёС‚РµС‚ РЅР°Рґ GITHUB_SCRIPT_URL.
--]]

local scriptVersion = "11.0"

-- РЎРѕСЃС‚РѕСЏРЅРёРµ СЃРёСЃС‚РµРјС‹ Р°РІС‚РѕРѕР±РЅРѕРІР»РµРЅРёСЏ
local updateState = {
    checking       = false,
    checked        = false,
    available      = false,
    showModal      = false,
    popupRequested = false,
    remoteVersion  = nil,
    downloadUrl    = nil,
    remoteChangelog = {},
    downloading    = false,
    downloadStatus = "",
}

local config_dir = "moonloader\\config"
local config_file_path = config_dir .. "\\HouseNotifConfig.json"
local saved_notifs_file = "moonloader\\saved_notifs.txt"
local autosave_file = config_dir .. "\\pending_forms.json"
local last_autosave = os.clock()

local config = { api_key = "" }

local houses, trailers, businesses = {}, {}, {}

local total_houses_found = 0
local total_trailers_found = 0
local total_biz_found = 0

local upload_queue = {}

local main_window_state = imgui.ImBool(false)
local auth_window_state = imgui.ImBool(false)

local create_notif_nicks = imgui.ImBuffer(u8(""), 1500)
local create_notif_text = imgui.ImBuffer(u8(""), 1500)

local property_type = imgui.ImInt(0)
local property_id = imgui.ImBuffer(u8(""), 200)

local templates = {
    { title = u8"Дерево из асфальта", pattern = u8"Уберите объект Дерево из асфальта возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Дерево/гриб на здании", pattern = u8"Уберите дерево/гриб из текстур %s %s", state = imgui.ImBool(false) },
    { title = u8"Грибы из асфальта", pattern = u8"Уберите объект Гриб из асфальта возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Летающий маппинг", pattern = u8"Уберите левитирующие объекты возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Помеха маппинг", pattern = u8"Уберите объекты, мешающие проезду транспорта возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Перегрузка территории", pattern = u8"Уберите массивные объекты возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Маппинг в людном месте", pattern = u8"Уберите объекты, создающие помеху возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Трейлер в текстуре", pattern = u8"Уберите трейлер из текстур, %s %s", state = imgui.ImBool(false) },
    { title = u8"Несоотв. тематике биза", pattern = u8"Уберите объекты, несоответствующие тематике возле %s %s", state = imgui.ImBool(false) },
    { title = u8"НРП", pattern = u8"Уберите НРП объекты возле %s %s", state = imgui.ImBool(false) },
    { title = u8"Неадекват название", pattern = u8"Поменяйте название имущества %s %s", state = imgui.ImBool(false) },
    { title = u8"Кривой мап", pattern = u8"Уберите кривостоящие объекты возле %s %s", state = imgui.ImBool(false) },
    { title = u8"2 этаж", pattern = u8"Уберите второй этаж из объектов возле %s %s", state = imgui.ImBool(false) },
}

-- Список обновлений (заполняется вручную)
local updates_list = {
    { version = "11.1", changes = { "Добавлена вкладка с обновлениями", "Возможность указывать свою причину формы", "Исправлена ошибка с вводом текста в imgui-поля" } },
    { version = "11.0", changes = { "Система очередей и API" } }
}

-- Буфер для своей причины
local custom_reason_buffer = imgui.ImBuffer(u8(""), 500)
local tab_selected = imgui.ImInt(0) -- 0 - Конструктор, 1 - Обновления

function sendGradientMessage(tag, text)
    sampAddChatMessage("{3399FF}[" .. tag .. "] {66CCFF}" .. text:gsub("{FFFFFF}", "{FFFFFF}{66CCFF}"), -1)
end

function logDebug(module, type, text)
    local colors = {
        success = "{00FF00}",
        error = "{FF3333}",
        warn = "{FFCC00}",
        info = "{66CCFF}"
    }

    local prefixes = {
        success = "[SUCCESS]",
        error = "[ERROR]",
        warn = "[WARN]",
        info = "[INFO]"
    }

    print(string.format(
        "{3399FF}[%s]%s %s%s",
        module,
        prefixes[type] or "[INFO]",
        colors[type] or "{66CCFF}",
        text
    ), -1)
end

function loadConfig()
    local file = io.open(config_file_path, "r")

    if file then
        local content = file:read("*a")
        file:close()

        local status, parsed = pcall(cjson.decode, content)

        if status and parsed and parsed.api_key then
            config.api_key = parsed.api_key
            return true
        end
    end

    return false
end

function saveConfig(new_key)
    createDirectory(config_dir)

    config.api_key = new_key

    local file = io.open(config_file_path, "w")

    if file then
        file:write(cjson.encode({
            api_key = new_key
        }))
        file:close()
        return true
    end

    return false
end

-- =========================================================
-- AUTOSAVE SYSTEM
-- =========================================================

function savePendingData()
    createDirectory(config_dir)

    local template_states = {}

    for i, t in ipairs(templates) do
        template_states[i] = t.state.v
    end

    local data = {
        create_notif_nicks = create_notif_nicks.v,
        create_notif_text = create_notif_text.v,
        property_type = property_type.v,
        property_id = property_id.v,
        upload_queue = upload_queue,
        template_states = template_states
    }

    local file = io.open(autosave_file, "w")

    if file then
        file:write(cjson.encode(data))
        file:close()

        logDebug(
            "Autosave",
            "info",
            "Данные сохранены"
        )
    end
end

function loadPendingData()
    local file = io.open(autosave_file, "r")

    if not file then
        return
    end

    local content = file:read("*a")
    file:close()

    if not content or content == "" then
        return
    end

    local ok, data = pcall(cjson.decode, content)

    if not ok or not data then
        logDebug(
            "Autosave",
            "error",
            "Ошибка чтения autosave"
        )
        return
    end

    if data.create_notif_nicks then
        create_notif_nicks.v = data.create_notif_nicks
    end

    if data.create_notif_text then
        create_notif_text.v = data.create_notif_text
    end

    if data.property_type ~= nil then
        property_type.v = data.property_type
    end

    if data.property_id then
        property_id.v = data.property_id
    end

    if data.upload_queue then
        upload_queue = data.upload_queue
    end

    if data.template_states then
        for i, state in ipairs(data.template_states) do
            if templates[i] then
                templates[i].state.v = state
            end
        end
    end

    logDebug(
        "Autosave",
        "success",
        "Незавершённые формы восстановлены"
    )
end

function clearPendingData()
    os.remove(autosave_file)
end

function executeSilentHidden(command)
    local si = ffi.new("STARTUPINFOA")
    local pi = ffi.new("PROCESS_INFORMATION")

    si.cb = ffi.sizeof(si)

    local cmd = "cmd.exe /c " .. command

    local cmd_buffer = ffi.new("char[?]", #cmd + 1)
    ffi.copy(cmd_buffer, cmd)

    local success = ffi.C.CreateProcessA(
        nil,
        cmd_buffer,
        nil,
        nil,
        1,
        0x08000000,
        nil,
        nil,
        si,
        pi
    )

    if success ~= 0 then
        ffi.C.CloseHandle(pi.hProcess)
        ffi.C.CloseHandle(pi.hThread)
        return true
    end

    return false
end

function parseInputString(input)
    local result = {}

    for item in input:gmatch("[%w_]+") do
        table.insert(result, item)
    end

    return result
end

function formatPropertyIds(input)
    local ids = parseInputString(input)

    if #ids == 0 then
        return "ID: ?"
    end

    return "ID: " .. table.concat(ids, ", ")
end

function updateTemplateText()
    local selected_patterns = {}
    local ids_list = parseInputString(property_id.v)
    
    -- Определение типа
    local current_type = "имущества"
    if property_type.v == 0 then
        current_type = (#ids_list > 1) and "домов" or "дома"
    elseif property_type.v == 1 then
        current_type = (#ids_list > 1) and "трейлеров" or "трейлера"
    elseif property_type.v == 2 then
        current_type = (#ids_list > 1) and "бизнесов" or "бизнеса"
    end

    local formatted_ids = formatPropertyIds(property_id.v)

    -- Добавление выбранных шаблонов
    for _, t in ipairs(templates) do
        if t.state.v then
            table.insert(selected_patterns, string.format(u8:decode(t.pattern), current_type, formatted_ids))
        end
    end

    -- Добавление своей причины с автоподстановкой
    if custom_reason_buffer.v ~= "" then
        local custom = u8:decode(custom_reason_buffer.v)
        table.insert(selected_patterns, string.format(custom .. " %s %s", current_type, formatted_ids))
    end

    if #selected_patterns > 0 then
        create_notif_text.v = u8(table.concat(selected_patterns, "; "))
    else
        create_notif_text.v = ""
    end

    savePendingData()
end

function addToQueue()
    local nicks = parseInputString(create_notif_nicks.v)
    local text = create_notif_text.v

    if #nicks == 0 or text == "" then
        logDebug("Queue", "error", "Пустой ник или текст")
        return
    end

    table.insert(upload_queue, {
        nick = nicks[1],
        text = text
    })

    table.remove(nicks, 1)

    create_notif_nicks.v = table.concat(nicks, "\n")

    property_id.v = ""
    create_notif_text.v = ""

    for _, t in ipairs(templates) do
        t.state.v = false
    end

    savePendingData()
end

function processNotifications(action_type)
    if #upload_queue == 0 then
        logDebug("Core", "error", "Очередь пуста!")
        return
    end

    local file = io.open(saved_notifs_file, "a")

    if file then
        for _, item in ipairs(upload_queue) do
            file:write(string.format(
                "/notif %s %s\n",
                u8:decode(item.nick),
                u8:decode(item.text)
            ))
        end

        file:close()
    end

    if action_type == "local" then
        upload_queue = {}
        return
    end

    if config.api_key == "" then
        logDebug("API", "error", "Отсутствует API KEY")
        return
    end

    local payload = {
        items = upload_queue
    }

    local json = cjson.encode(payload)

    local tmp_file_path = config_dir .. "\\payload.json"

    local tmp_file = io.open(tmp_file_path, "w")

    if tmp_file then
        tmp_file:write(json)
        tmp_file:close()
    end

    local curl_command = string.format(
        'curl -s -X POST "%s" -H "Content-Type: application/json; charset=utf-8" -H "X-API-Key: %s" -d "@%s"',
        API_URL,
        config.api_key,
        tmp_file_path
    )

    if executeSilentHidden(curl_command) then
        logDebug("API", "success", "Пакет отправлен")
        upload_queue = {}
    else
        logDebug("API", "error", "Ошибка curl")
    end
end

-- =========================================================
-- ПАРСИНГ ИЗ ПЕРВОГО СКРИПТА
-- =========================================================

function parseHouseData(text)
    local clean = text:gsub("{.-}", ""):gsub("\r", "")

    local houseId, desc, owner = nil, nil, nil

    local lines = {}

    for line in clean:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    for i = 1, #lines do
        local line = lines[i]

        if line:find("Номер дома") then
            houseId = tonumber(line:match("(%d+)"))
        end

        if line:find("%*%*%* Дом занят %*%*%*") then
            local nextLine = lines[i + 1]

            if nextLine and nextLine ~= "" then
                desc = nextLine:find("Номер дома") and "Отсутствует" or nextLine
            else
                desc = lines[i + 2]
            end
        end

        if line:find("Владелец:") then
            owner = line:match("Владелец:%s*(%S+)")

            if owner then
                owner = owner:gsub("%s+$", "")
            end
        end
    end

    return houseId, desc or "Отсутствует", owner or "Отсутствует"
end

function parseTrailerData(text)
    local clean = text:gsub("{.-}", ""):gsub("\r", "")

    local trailerId, owner = nil, nil

    local lines = {}

    for line in clean:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    for i = 1, #lines do
        local line = lines[i]

        if line:find("Трейлер №") then
            trailerId = tonumber(line:match("(%d+)"))
        end

        if line:find("Владелец:") then
            owner = line:match("Владелец:%s*(%S+)")

            if owner then
                owner = owner:gsub("%s+$", "")
            end
        end
    end

    return trailerId, owner or "Отсутствует"
end

function parseBizData(text)
    local clean = text:gsub("{.-}", ""):gsub("\r", "")

    local bizId, owner, desc = nil, nil, nil

    local lines = {}

    for line in clean:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    for i = 1, #lines do
        local line = lines[i]

        if line:find("Номер бизнеса") then
            bizId = tonumber(line:match("(%d+)"))
        end

        if line:find("Номер бизнеса:") then
            local prevLine = lines[i - 1]

            desc = (
                prevLine
                and prevLine ~= ""
                and not prevLine:find("Номер бизнеса:")
            ) and prevLine or "Отсутствует"
        end

        if line:find("Владелец:") then
            owner = line:match("Владелец:%s*(%S+)")

            if owner then
                owner = owner:gsub("%s+$", "")
            end
        end
    end

    return bizId, owner or "Отсутствует", desc or "Отсутствует"
end

-- =========================================================
-- UI
-- =========================================================

function imgui.OnDrawFrame()
    local screenX, screenY = getScreenResolution()

    if auth_window_state.v then
        imgui.ShowCursor = true
        imgui.SetNextWindowPos(imgui.ImVec2(screenX / 2, screenY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(520, 140), imgui.Cond.Always)
        imgui.Begin(u8'Ошибка | Ключ авторизации', auth_window_state, imgui.WindowFlags.NoCollapse)
        imgui.TextWrapped(u8"Персональный X-API-Key не найден. Для работы скрипта укажите ключ:")
        imgui.TextColored(imgui.ImVec4(0.25, 0.53, 0.93, 1.0), u8"/set_apikey [ваш_ключ]")
        imgui.Spacing()
        if imgui.Button(u8"Закрыть окно", imgui.ImVec2(-1, 30)) then auth_window_state.v = false end
        imgui.End()
    
    elseif main_window_state.v then
        imgui.ShowCursor = true
        
        -- ДИНАМИЧЕСКИЙ РАСЧЕТ ВЫСОТЫ
        -- 430 - это фиксированная высота всех блоков сверху, 45 - высота каждой строки в очереди, 
        -- 120 - минимальный отступ снизу/подвал.
        local queue_items = #upload_queue
        local list_height = (queue_items > 0) and (queue_items * 45 + 30) or 60
        local dynamic_height = 430 + list_height
        
        -- Ограничиваем высоту, чтобы окно не вылезало за экран
        dynamic_height = math.min(dynamic_height, screenY - 50)
        
        imgui.SetNextWindowPos(imgui.ImVec2(screenX / 2, screenY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(980, dynamic_height), imgui.Cond.Always)
        
        imgui.Begin(u8'Управление Уведомлениями Имущества', main_window_state, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
        
        imgui.TextColored(imgui.ImVec4(0.25, 0.53, 0.93, 1.0), u8" МАССОВАЯ ОТПРАВКА УВЕДОМЛЕНИЙ НА API")
        imgui.SameLine(460)
        imgui.TextDisabled(u8(string.format("[ Сканер 3D-Text: Домов: %d | Трейлеров: %d | Бизнесов: %d ]", total_houses_found, total_trailers_found, total_biz_found)))

        imgui.SameLine(imgui.GetWindowWidth() - 35)
        if imgui.Button("X", imgui.ImVec2(25, 20)) then main_window_state.v = false end
        imgui.Separator()
        imgui.Spacing()

        imgui.Columns(2, "main_columns", true)
        imgui.SetColumnWidth(0, 470)

        imgui.BeginChild("LeftDataBlock", imgui.ImVec2(-1, 290), true)
        imgui.TextColored(imgui.ImVec4(0.6, 0.6, 0.6, 1.0), u8"[ 1. ОЧЕРЕДЬ НАРУШИТЕЛЕЙ ]")
        imgui.Spacing()
        
        imgui.Text(u8"Список никнеймов (каждый с новой строки / через пробел):")
        imgui.PushItemWidth(-1)
        if imgui.InputTextMultiline( "##nicks_area", create_notif_nicks, imgui.ImVec2(-1, 110) ) then savePendingData() end
        imgui.PopItemWidth()
        
        local detected_nicks = parseInputString(create_notif_nicks.v)
        if #detected_nicks > 0 then
            imgui.TextColored(imgui.ImVec4(0.0, 1.0, 0.3, 1.0), u8(string.format("  -> Осталось распределить ников: %d (След: ", #detected_nicks)) .. detected_nicks[1] .. u8")")
        else
            imgui.TextColored(imgui.ImVec4(1.0, 0.3, 0.3, 1.0), u8"  -> Список ников пуст")
        end
        
        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.45, 0.23, 0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.60, 0.30, 1.00))
        if imgui.Button(u8"ПРИВЯЗАТЬ ИМУЩЕСТВО К ПЕРВОМУ НИКУ", imgui.ImVec2(-1, 42)) then
            addToQueue()
        end
        imgui.PopStyleColor(2)
        imgui.EndChild()

        imgui.NextColumn()

-- ЗАМЕНЕННЫЙ БЛОК КОНСТРУКТОРА И ВКЛАДОК
        imgui.BeginChild("RightConstructorBlock", imgui.ImVec2(-1, 290), true)
        
        -- Вкладки
        if imgui.Button(u8"Конструктор", imgui.ImVec2(220, 25)) then tab_selected.v = 0 end
        imgui.SameLine()
        if imgui.Button(u8"Обновления", imgui.ImVec2(220, 25)) then tab_selected.v = 1 end
        imgui.Separator()
        imgui.Spacing()

        if tab_selected.v == 0 then
            imgui.TextColored(imgui.ImVec4(0.25, 0.53, 0.93, 1.0), u8"[ 2. КОНСТРУКТОР ДАННЫХ ]")
            imgui.Spacing()
            
            imgui.Text(u8"Тип:") 
            imgui.PushItemWidth(120)
            if imgui.Combo("##prop_type", property_type, { u8"Дом", u8"Трейлер", u8"Бизнес" }) then updateTemplateText() end
            imgui.PopItemWidth()
            
            imgui.SameLine()
            imgui.Text(u8"ID (через пробел):")
            imgui.SameLine()
            imgui.PushItemWidth(-1)
            if imgui.InputText("##prop_id", property_id) then
                updateTemplateText()
                savePendingData()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.Text(u8"Своя причина:")
            -- Добавляем условие: если текст изменился, вызываем обновление
            if imgui.InputText("##custom_reason", custom_reason_buffer) then 
                updateTemplateText() 
            end

            imgui.Spacing()
            imgui.BeginChild("TemplatesInnerChild", imgui.ImVec2(-1, 80), true)
            for idx, t in ipairs(templates) do
                if imgui.Checkbox(t.title, t.state) then updateTemplateText() end
            end
            imgui.EndChild()

            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), u8"ПРЕВЬЮ СТРОКИ:")
            imgui.BeginChild("PreviewStringBox", imgui.ImVec2(-1, 42), false)
            if create_notif_text.v ~= "" then
                imgui.TextWrapped(create_notif_text.v)
            else
                imgui.TextDisabled(u8"(выберите чекбоксы или напишите свою причину)")
            end
            imgui.EndChild()
        else
            -- Вкладка обновлений
            imgui.TextColored(imgui.ImVec4(0.25, 0.53, 0.93, 1.0), u8"[ ИСТОРИЯ ОБНОВЛЕНИЙ ]")
            imgui.Spacing()
            imgui.BeginChild("UpdatesChild", imgui.ImVec2(-1, -1), true)
            for _, up in ipairs(updates_list) do
                if imgui.CollapsingHeader(u8("Версия " .. up.version)) then
                    for _, change in ipairs(up.changes) do
                        imgui.Text("- " .. u8(change))
                    end
                end
            end
            imgui.EndChild()
        end
        imgui.EndChild()

        imgui.Columns(1)
        imgui.Spacing()

        imgui.TextColored(imgui.ImVec4(0.25, 0.53, 0.93, 1.0), u8(string.format("ОЧЕРЕДЬ К ОТПРАВКЕ (ВСЕГО ЗАПИСЕЙ В ПАКЕТЕ: %d)", #upload_queue)))
        
        if #upload_queue > 0 then
            imgui.BeginChild("QueueTableChild", imgui.ImVec2(-1, list_height - 5), true)
            for i = #upload_queue, 1, -1 do 
                local entry = upload_queue[i]
                imgui.PushID(i)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.65, 0.15, 0.15, 0.8))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.20, 0.20, 1.0))
                if imgui.Button(u8"Удалить", imgui.ImVec2(70, 22)) then
                    table.remove(upload_queue, i)
                    savePendingData()
                end
                imgui.PopStyleColor(2)
                imgui.SameLine()
                imgui.TextWrapped(string.format("%d. /notif %s %s", i, entry.nick, entry.text))
                imgui.Separator()
                imgui.PopID()
            end
            imgui.EndChild()

            imgui.Spacing()
            imgui.Columns(2, "action_buttons", false)
            if imgui.Button(u8'Сохранить резервный TXT-лог', imgui.ImVec2(-1, 42)) then 
                processNotifications("local")
            end
            imgui.NextColumn()
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.42, 0.77, 1.0))
            if imgui.Button(u8'ОТПРАВИТЬ ВСЮ СФОРМИРОВАННУЮ ПАЧКУ НА WEB API', imgui.ImVec2(-1, 42)) then 
                processNotifications("web")
            end
            imgui.PopStyleColor(1)
            imgui.Columns(1)
        else
            imgui.BeginChild("EmptyQueueNotify", imgui.ImVec2(-1, 50), true)
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 0.8), u8" Очередь пуста. Заполните данные игроков слева, укажите свойства справа и сформируйте пакет.")
            imgui.EndChild()
        end

        imgui.End()
    elseif updateState.showModal then
        imgui.ShowCursor = true
        renderUpdateModal()
    else
    end
end

-- =========================================================
-- AUTOUPDATE FUNCTIONS
-- =========================================================

local function parseVersionParts(version)
    local parts = {}
    for num in tostring(version):gmatch("%d+") do
        table.insert(parts, tonumber(num))
    end
    return parts
end

local function isVersionNewer(remoteVer, localVer)
    local r = parseVersionParts(remoteVer)
    local l = parseVersionParts(localVer)
    for i = 1, math.max(#r, #l) do
        local rv = r[i] or 0
        local lv = l[i] or 0
        if rv > lv then return true end
        if rv < lv then return false end
    end
    return false
end

local function checkForUpdatesAsync()
    if updateState.checking or updateState.checked then
        logDebug("Update", "warn", "РџСЂРѕРІРµСЂРєР° СѓР¶Рµ РІС‹РїРѕР»РЅСЏРµС‚СЃСЏ РёР»Рё Р±С‹Р»Р° РІС‹РїРѕР»РЅРµРЅР° вЂ” РїСЂРѕРїСѓСЃРє")
        return
    end
    updateState.checking = true
    logDebug("Update", "info", "РќР°С‡Р°Р»Рѕ РїСЂРѕРІРµСЂРєРё РѕР±РЅРѕРІР»РµРЅРёР№...")
    logDebug("Update", "info", "URL: " .. GITHUB_VERSION_URL)

    lua_thread.create(function()
        local dir      = getGameDirectory() .. "\\moonloader\\config\\"
        local tempFile = dir .. "maphelp_version_check.tmp"
        logDebug("Update", "info", "Р’СЂРµРјРµРЅРЅС‹Р№ С„Р°Р№Р»: " .. tempFile)

        local downloadDone = false
        local downloadOk   = false

        downloadUrlToFile(GITHUB_VERSION_URL, tempFile, function(id, status, p1, p2)
            if status == dlstatus.STATUS_CONNECTING then
                logDebug("Update", "info", "РџРѕРґРєР»СЋС‡РµРЅРёРµ Рє GitHub...")
            elseif status == dlstatus.STATUS_REQUESTSENT then
                logDebug("Update", "info", "Р—Р°РїСЂРѕСЃ РѕС‚РїСЂР°РІР»РµРЅ")
            elseif status == dlstatus.STATUS_DOWNLOADINGDATA then
                -- Р±РµР· СЃРїР°РјР° вЂ” СЃСЂР°Р±Р°С‚С‹РІР°РµС‚ РЅР° РєР°Р¶РґС‹Р№ С‡Р°РЅРє
            elseif status == dlstatus.STATUS_ENDDOWNLOADDATA
                or status == dlstatus.STATUSEX_ENDDOWNLOAD then
                logDebug("Update", "success", "version.json СѓСЃРїРµС€РЅРѕ СЃРєР°С‡Р°РЅ")
                downloadOk   = true
                downloadDone = true
            else
                logDebug("Update", "error", "РќРµРѕР¶РёРґР°РЅРЅС‹Р№ СЃС‚Р°С‚СѓСЃ Р·Р°РіСЂСѓР·РєРё: " .. tostring(status))
                downloadDone = true
            end
        end)

        -- Р–РґС‘Рј Р·Р°РІРµСЂС€РµРЅРёСЏ, С‚Р°Р№РјР°СѓС‚ 10 СЃРµРєСѓРЅРґ
        local waited = 0
        while not downloadDone and waited < 100 do
            wait(100)
            waited = waited + 1
        end

        if not downloadDone then
            logDebug("Update", "error", "РўР°Р№РјР°СѓС‚ РѕР¶РёРґР°РЅРёСЏ РѕС‚РІРµС‚Р° РѕС‚ GitHub (10 СЃРµРє)")
        end

        updateState.checking = false
        updateState.checked  = true
        logDebug("Update", "info", "РџСЂРѕРІРµСЂРєР° Р·Р°РІРµСЂС€РµРЅР° (checking=false, checked=true)")

        if not downloadOk then
            logDebug("Update", "warn", "РќРµ СѓРґР°Р»РѕСЃСЊ СЃРєР°С‡Р°С‚СЊ version.json вЂ” РѕР±РЅРѕРІР»РµРЅРёРµ РїСЂРѕРїСѓС‰РµРЅРѕ")
            if doesFileExist(tempFile) then os.remove(tempFile) end
            return
        end

        local f = io.open(tempFile, "r")
        if not f then
            logDebug("Update", "error", "РќРµ СѓРґР°Р»РѕСЃСЊ РѕС‚РєСЂС‹С‚СЊ РІСЂРµРјРµРЅРЅС‹Р№ С„Р°Р№Р» РґР»СЏ С‡С‚РµРЅРёСЏ")
            return
        end
        local content = f:read("*a")
        f:close()
        if doesFileExist(tempFile) then os.remove(tempFile) end
        logDebug("Update", "info", "version.json РїСЂРѕС‡РёС‚Р°РЅ (" .. #content .. " Р±Р°Р№С‚)")

        if not content or content == "" then
            logDebug("Update", "warn", "version.json РїСѓСЃС‚РѕР№")
            return
        end

        logDebug("Update", "info", "РџР°СЂСЃРёРЅРі JSON...")
        local ok, data = pcall(cjson.decode, content)
        if not ok or type(data) ~= "table" then
            logDebug("Update", "error", "РћС€РёР±РєР° РїР°СЂСЃРёРЅРіР° JSON: " .. tostring(content):sub(1, 120))
            return
        end
        logDebug("Update", "success", "JSON СѓСЃРїРµС€РЅРѕ СЂР°СЃРїР°СЂСЃРµРЅ")

        local remoteVersion = data.version
        local downloadUrl   = data.download_url or GITHUB_SCRIPT_URL

        if not remoteVersion then
            logDebug("Update", "warn", "Р’ version.json РѕС‚СЃСѓС‚СЃС‚РІСѓРµС‚ РїРѕР»Рµ 'version'")
            return
        end

        logDebug("Update", "info", string.format(
            "Р›РѕРєР°Р»СЊРЅР°СЏ РІРµСЂСЃРёСЏ: %s | РЈРґР°Р»С‘РЅРЅР°СЏ РІРµСЂСЃРёСЏ: %s",
            scriptVersion, remoteVersion
        ))
        logDebug("Update", "info", "URL РґР»СЏ СЃРєР°С‡РёРІР°РЅРёСЏ: " .. downloadUrl)

        if isVersionNewer(remoteVersion, scriptVersion) then
            updateState.available       = true
            updateState.remoteVersion   = tostring(remoteVersion)
            updateState.downloadUrl     = tostring(downloadUrl)
            updateState.remoteChangelog = {}

            if type(data.changelog) == "table" then
                logDebug("Update", "info", "Changelog: " .. #data.changelog .. " РїСѓРЅРєС‚(Р°/РѕРІ)")
                for i, item in ipairs(data.changelog) do
                    logDebug("Update", "info", string.format("  [%d] %s", i, tostring(item)))
                    table.insert(updateState.remoteChangelog, u8(tostring(item)))
                end
            else
                logDebug("Update", "warn", "Changelog РІ version.json РѕС‚СЃСѓС‚СЃС‚РІСѓРµС‚ РёР»Рё РЅРµ СЏРІР»СЏРµС‚СЃСЏ РјР°СЃСЃРёРІРѕРј")
            end

            updateState.showModal = true
            logDebug("Update", "success", string.format(
                "Р’Р•Р Р”Р�РљРў: РґРѕСЃС‚СѓРїРЅР° РЅРѕРІР°СЏ РІРµСЂСЃРёСЏ %s (С‚РµРєСѓС‰Р°СЏ: %s) вЂ” РїРѕРєР°Р·С‹РІР°РµРј РјРѕРґР°Р»СЊРЅРѕРµ РѕРєРЅРѕ",
                remoteVersion, scriptVersion
            ))
        else
            logDebug("Update", "info", string.format(
                "Р’Р•Р Р”Р�РљРў: РІРµСЂСЃРёСЏ Р°РєС‚СѓР°Р»СЊРЅР° (%s >= %s) вЂ” РѕР±РЅРѕРІР»РµРЅРёРµ РЅРµ С‚СЂРµР±СѓРµС‚СЃСЏ",
                scriptVersion, remoteVersion
            ))
        end
    end)
end

local function performScriptUpdate()
    if updateState.downloading then
        logDebug("Update", "warn", "Р—Р°РіСЂСѓР·РєР° СѓР¶Рµ РёРґС‘С‚ вЂ” РїРѕРІС‚РѕСЂРЅС‹Р№ РІС‹Р·РѕРІ РїСЂРѕРёРіРЅРѕСЂРёСЂРѕРІР°РЅ")
        return
    end
    if not updateState.downloadUrl then
        logDebug("Update", "error", "downloadUrl РЅРµ Р·Р°РґР°РЅ вЂ” РЅРµРІРѕР·РјРѕР¶РЅРѕ РЅР°С‡Р°С‚СЊ Р·Р°РіСЂСѓР·РєСѓ")
        return
    end

    updateState.downloading    = true
    updateState.downloadStatus = u8("Р—Р°РіСЂСѓР·РєР° РѕР±РЅРѕРІР»РµРЅРёСЏ...")
    logDebug("Update", "info", "РќР°С‡Р°Р»Рѕ Р·Р°РіСЂСѓР·РєРё СЃРєСЂРёРїС‚Р°...")
    logDebug("Update", "info", "URL: " .. updateState.downloadUrl)

    local targetPath = thisScript().path
    local tempPath   = targetPath .. ".update.tmp"
    logDebug("Update", "info", "Р¦РµР»СЊ: " .. targetPath)
    logDebug("Update", "info", "Р’СЂРµРјРµРЅРЅС‹Р№ С„Р°Р№Р»: " .. tempPath)

    downloadUrlToFile(updateState.downloadUrl, tempPath, function(id, status, p1, p2)
        if status == dlstatus.STATUS_CONNECTING then
            logDebug("Update", "info", "РџРѕРґРєР»СЋС‡РµРЅРёРµ Рє СЃРµСЂРІРµСЂСѓ Р·Р°РіСЂСѓР·РєРё...")
        elseif status == dlstatus.STATUS_REQUESTSENT then
            logDebug("Update", "info", "Р—Р°РїСЂРѕСЃ РЅР° СЃРєР°С‡РёРІР°РЅРёРµ РѕС‚РїСЂР°РІР»РµРЅ")
        elseif status == dlstatus.STATUS_DOWNLOADINGDATA then
            if p2 and p2 > 0 then
                local pct = math.floor((p1 / p2) * 100)
                updateState.downloadStatus = u8("Р—Р°РіСЂСѓР·РєР°: ") .. pct .. "%"
                -- Р»РѕРіРёСЂСѓРµРј С‚РѕР»СЊРєРѕ РЅР° РєСЂСѓРіР»С‹С… Р·РЅР°С‡РµРЅРёСЏС… С‡С‚РѕР±С‹ РЅРµ СЃРїР°РјРёС‚СЊ
                if pct % 25 == 0 then
                    logDebug("Update", "info", "РџСЂРѕРіСЂРµСЃСЃ: " .. pct .. "% (" .. p1 .. "/" .. p2 .. " Р±Р°Р№С‚)")
                end
            else
                updateState.downloadStatus = u8("Р—Р°РіСЂСѓР·РєР°...")
            end
        elseif status == dlstatus.STATUS_ENDDOWNLOADDATA
            or status == dlstatus.STATUSEX_ENDDOWNLOAD then
            logDebug("Update", "info", "Р—Р°РіСЂСѓР·РєР° Р·Р°РІРµСЂС€РµРЅР°, РїСЂРѕРІРµСЂСЏСЋ РІСЂРµРјРµРЅРЅС‹Р№ С„Р°Р№Р»...")
            if doesFileExist(tempPath) then
                logDebug("Update", "success", "Р’СЂРµРјРµРЅРЅС‹Р№ С„Р°Р№Р» СЃСѓС‰РµСЃС‚РІСѓРµС‚ вЂ” Р·Р°РјРµРЅСЏСЋ СЃРєСЂРёРїС‚")
                if doesFileExist(targetPath) then
                    os.remove(targetPath)
                    logDebug("Update", "info", "РЎС‚Р°СЂС‹Р№ С„Р°Р№Р» СѓРґР°Р»С‘РЅ: " .. targetPath)
                end
                os.rename(tempPath, targetPath)
                logDebug("Update", "success", "Р¤Р°Р№Р» РїРµСЂРµРјРµС‰С‘РЅ: " .. tempPath .. " -> " .. targetPath)
                updateState.showModal = false
                sendGradientMessage("Update", u8("РћР±РЅРѕРІР»РµРЅРёРµ СѓСЃС‚Р°РЅРѕРІР»РµРЅРѕ! РџРµСЂРµР·Р°РіСЂСѓР·РєР°..."))
                logDebug("Update", "success", "РЎРєСЂРёРїС‚ РѕР±РЅРѕРІР»С‘РЅ РґРѕ РІРµСЂСЃРёРё " .. tostring(updateState.remoteVersion) .. " вЂ” РїРµСЂРµР·Р°РіСЂСѓР·РєР° С‡РµСЂРµР· 0.6 СЃРµРє")
                lua_thread.create(function()
                    wait(600)
                    thisScript():reload()
                end)
            else
                logDebug("Update", "error", "Р’СЂРµРјРµРЅРЅС‹Р№ С„Р°Р№Р» РЅРµ РЅР°Р№РґРµРЅ РїРѕСЃР»Рµ Р·Р°РІРµСЂС€РµРЅРёСЏ Р·Р°РіСЂСѓР·РєРё: " .. tempPath)
                updateState.downloadStatus = u8("РћС€РёР±РєР°: С„Р°Р№Р» РЅРµ СЃРєР°С‡Р°РЅ")
                updateState.downloading    = false
            end
        else
            logDebug("Update", "error", "РќРµРѕР¶РёРґР°РЅРЅС‹Р№ СЃС‚Р°С‚СѓСЃ РїСЂРё Р·Р°РіСЂСѓР·РєРµ СЃРєСЂРёРїС‚Р°: " .. tostring(status))
        end
    end)
end

local function renderUpdateModal()
    if not updateState.showModal then
        updateState.popupRequested = false
        return
    end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(500, 400), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    if not updateState.popupRequested then
        imgui.OpenPopup(u8("Р”РѕСЃС‚СѓРїРЅРѕ РѕР±РЅРѕРІР»РµРЅРёРµ"))
        updateState.popupRequested = true
        logDebug("Update", "info", "РњРѕРґР°Р»СЊРЅРѕРµ РѕРєРЅРѕ РѕР±РЅРѕРІР»РµРЅРёСЏ РѕС‚РєСЂС‹С‚Рѕ")
    end

    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove
    if imgui.BeginPopupModal(u8("Р”РѕСЃС‚СѓРїРЅРѕ РѕР±РЅРѕРІР»РµРЅРёРµ"), nil, flags) then

        imgui.TextColored(imgui.ImVec4(0.25, 0.80, 0.45, 1.0), u8("Р”РѕСЃС‚СѓРїРЅР° РЅРѕРІР°СЏ РІРµСЂСЃРёСЏ MapHelp!"))
        imgui.Separator()
        imgui.Spacing()

        imgui.Text(u8("РўРµРєСѓС‰Р°СЏ РІРµСЂСЃРёСЏ: ") .. scriptVersion)
        imgui.Text(u8("РќРѕРІР°СЏ РІРµСЂСЃРёСЏ:   ") .. tostring(updateState.remoteVersion))
        imgui.Spacing()

        imgui.TextColored(imgui.ImVec4(0.25, 0.53, 0.93, 1.0), u8("Р§С‚Рѕ РЅРѕРІРѕРіРѕ:"))
        imgui.BeginChild("##UpdateLog", imgui.ImVec2(0, 160), true)
        if #updateState.remoteChangelog > 0 then
            for _, line in ipairs(updateState.remoteChangelog) do
                imgui.BulletText(line)
            end
        else
            imgui.TextDisabled(u8("РЎРїРёСЃРѕРє РёР·РјРµРЅРµРЅРёР№ РЅРµРґРѕСЃС‚СѓРїРµРЅ."))
        end
        imgui.EndChild()

        if updateState.downloadStatus ~= "" then
            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.2, 1.0), updateState.downloadStatus)
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.TextWrapped(u8("Р”Р»СЏ РїСЂРѕРґРѕР»Р¶РµРЅРёСЏ СЂР°Р±РѕС‚С‹ РЅРµРѕР±С…РѕРґРёРјРѕ РѕР±РЅРѕРІРёС‚СЊСЃСЏ. РџСЂРё РѕС‚РєР°Р·Рµ СЃРєСЂРёРїС‚ Р±СѓРґРµС‚ РІС‹РіСЂСѓР¶РµРЅ."))
        imgui.Spacing()

        local btnW = 140
        if not updateState.downloading then
            imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.18, 0.60, 0.28, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.22, 0.72, 0.35, 1.0))
            if imgui.Button(u8("РћР±РЅРѕРІРёС‚СЊ"), imgui.ImVec2(btnW, 30)) then
                logDebug("Update", "info", "РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ РЅР°Р¶Р°Р» 'РћР±РЅРѕРІРёС‚СЊ' вЂ” Р·Р°РїСѓСЃРєР°РµРј Р·Р°РіСЂСѓР·РєСѓ")
                performScriptUpdate()
            end
            imgui.PopStyleColor(2)
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.60, 0.28, 0.5))
            imgui.Button(u8("Р—Р°РіСЂСѓР·РєР°..."), imgui.ImVec2(btnW, 30))
            imgui.PopStyleColor(1)
        end

        imgui.SameLine()

        if not updateState.downloading then
            imgui.PushStyleColor(imgui.Col.Button,        imgui.ImVec4(0.65, 0.15, 0.15, 0.9))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.20, 0.20, 1.0))
            if imgui.Button(u8("РћС‚РєР°Р·Р°С‚СЊСЃСЏ (РІС‹РіСЂСѓР·РёС‚СЊ)"), imgui.ImVec2(200, 30)) then
                logDebug("Update", "warn", "РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ РЅР°Р¶Р°Р» 'РћС‚РєР°Р·Р°С‚СЊСЃСЏ' вЂ” СЃРєСЂРёРїС‚ Р±СѓРґРµС‚ РІС‹РіСЂСѓР¶РµРЅ")
                updateState.showModal = false
                sendGradientMessage("Update", u8("РћР±РЅРѕРІР»РµРЅРёРµ РѕС‚РєР»РѕРЅРµРЅРѕ. РЎРєСЂРёРїС‚ РІС‹РіСЂСѓР¶РµРЅ."))
                lua_thread.create(function()
                    wait(400)
                    thisScript():unload()
                end)
            end
            imgui.PopStyleColor(2)
        end

        imgui.EndPopup()
    end
end

function apply_custom_style()
    imgui.SwitchContext()

    local style = imgui.GetStyle()
    local c = style.Colors

    style.WindowRounding = 10
    style.FrameRounding = 6

    c[imgui.Col.WindowBg] = imgui.ImVec4(0.09, 0.09, 0.12, 0.95)
    c[imgui.Col.Button] = imgui.ImVec4(0.20, 0.25, 0.33, 0.90)
    c[imgui.Col.ButtonHovered] = imgui.ImVec4(0.28, 0.35, 0.45, 1.00)
end

function cmd_create_notif(arg)
    if arg == "" then
        main_window_state.v = not main_window_state.v
        return
    end

    local propTypeStr, ids = arg:match("^(%S+)%s+(.+)$")

    if propTypeStr and ids then
        local typeIdx = -1

        propTypeStr = propTypeStr:lower()

        if propTypeStr == "0" or propTypeStr == "house" or propTypeStr == "дом" then
            typeIdx = 0
        elseif propTypeStr == "1" or propTypeStr == "trailer" or propTypeStr == "трейлер" then
            typeIdx = 1
        elseif propTypeStr == "2" or propTypeStr == "biz" or propTypeStr == "бизнес" then
            typeIdx = 2
        end

        if typeIdx ~= -1 then
            property_type.v = typeIdx
            property_id.v = u8(ids)

            main_window_state.v = true

            updateTemplateText()
        end
    end
end

function main()
    while not isSampAvailable() do
        wait(200)
    end

    loadConfig()
    loadPendingData()
    checkForUpdatesAsync()

    apply_custom_style()

    -- =====================================================
    -- COMMANDS
    -- =====================================================

    sampRegisterChatCommand("create_notif", cmd_create_notif)

    sampRegisterChatCommand("set_apikey", function(arg)
        if saveConfig(arg) then
            sendGradientMessage("API", "Ключ сохранен")
        end
    end)

    sampRegisterChatCommand("house_info", function(arg)
        local id = tonumber(arg)

        if not id then
            sendGradientMessage(
                "House Info",
                "Используй: /house_info [id]"
            )
            return
        end

        if houses[id] then
            local h = houses[id]

            sendGradientMessage(
                "House Info",
                string.format(
                    "Дом №%d | Владелец: {FFFFFF}%s{66CCFF} | Описание: {FFFFFF}%s",
                    id,
                    h.owner or "Отсутствует",
                    h.desc or "Отсутствует"
                )
            )

            if h.owner and h.owner ~= "Отсутствует" then
                setClipboardText(h.owner)
            end
        else
            sendGradientMessage(
                "House Info",
                "{FF3333}Дом не найден в зоне стрима"
            )
        end
    end)

    sampRegisterChatCommand("trailer_info", function(arg)
        local id = tonumber(arg)

        if not id then
            sendGradientMessage(
                "Trailer Info",
                "Используй: /trailer_info [id]"
            )
            return
        end

        if trailers[id] then
            local t = trailers[id]

            sendGradientMessage(
                "Trailer Info",
                string.format(
                    "Трейлер №%d | Владелец: {FFFFFF}%s",
                    id,
                    t.owner or "Отсутствует"
                )
            )

            if t.owner and t.owner ~= "Отсутствует" then
                setClipboardText(t.owner)
            end
        else
            sendGradientMessage(
                "Trailer Info",
                "{FF3333}Трейлер не найден в зоне стрима"
            )
        end
    end)

    sampRegisterChatCommand("biz_info", function(arg)
        local id = tonumber(arg)

        if not id then
            sendGradientMessage(
                "Biz Info",
                "Используй: /biz_info [id]"
            )
            return
        end

        if businesses[id] then
            local b = businesses[id]

            sendGradientMessage(
                "Biz Info",
                string.format(
                    "Бизнес №%d | Владелец: {FFFFFF}%s{66CCFF} | Описание: {FFFFFF}%s",
                    id,
                    b.owner or "Отсутствует",
                    b.desc or "Отсутствует"
                )
            )

            if b.owner and b.owner ~= "Отсутствует" then
                setClipboardText(b.owner)
            end
        else
            sendGradientMessage(
                "Biz Info",
                "{FF3333}Бизнес не найден в зоне стрима"
            )
        end
    end)

    sampRegisterChatCommand("help_notif", function()
        local dialogText = "{FFFFFF}Доступные команды:\n\n"

        dialogText = dialogText ..
        "{3399FF}/house_info [id] {FFFFFF}- Информация о доме\n"

        dialogText = dialogText ..
        "{3399FF}/trailer_info [id] {FFFFFF}- Информация о трейлере\n"

        dialogText = dialogText ..
        "{3399FF}/biz_info [id] {FFFFFF}- Информация о бизнесе\n\n"

        dialogText = dialogText ..
        "{3399FF}/create_notif {FFFFFF}- Открыть меню\n"

        dialogText = dialogText ..
        "{3399FF}/set_apikey [key] {FFFFFF}- Указать API ключ"

        sampShowDialog(
            9999,
            "{3399FF}House Desc | Помощь",
            dialogText,
            "Закрыть",
            ""
        )
    end)

    sendGradientMessage(
        "House Desc",
        "Скрипт загружен. Команды: /help_notif"
    )

    local scan_timer = os.clock()

    while true do
        wait(0)

        imgui.Process = main_window_state.v or auth_window_state.v or updateState.showModal

        -- =====================================================
        -- AUTOSAVE LOOP
        -- =====================================================

        if os.clock() - last_autosave > 5 then
            last_autosave = os.clock()
            savePendingData()
        end

        -- =====================================================
        -- 3D TEXT SCANNER
        -- =====================================================

        if os.clock() - scan_timer > 0.5 then
            scan_timer = os.clock()

            for id = 0, 2048 do
                if sampIs3dTextDefined(id) then
                    local text = sampGet3dTextInfoById(id)

                    if text and text ~= "" then

                        -- =============================
                        -- HOUSE
                        -- =============================

                        if text:find('*** Дом занят ***') then
                            local houseId, desc, owner =
                                parseHouseData(text)

                            if houseId and not houses[houseId] then
                                houses[houseId] = {
                                    desc = desc,
                                    owner = owner
                                }

                                total_houses_found =
                                    total_houses_found + 1
                            end

                        -- =============================
                        -- TRAILER
                        -- =============================

                        elseif text:find('Трейлер {%x+}№') then
                            local trailerId, owner =
                                parseTrailerData(text)

                            if trailerId and not trailers[trailerId] then
                                trailers[trailerId] = {
                                    owner = owner
                                }

                                total_trailers_found =
                                    total_trailers_found + 1
                            end

                        -- =============================
                        -- BUSINESS
                        -- =============================

                        elseif text:find('Номер бизнеса:') then
                            local bizId, owner, desc =
                                parseBizData(text)

                            if bizId and not businesses[bizId] then
                                businesses[bizId] = {
                                    owner = owner,
                                    desc = desc
                                }

                                total_biz_found =
                                    total_biz_found + 1
                            end
                        end
                    end
                end
            end
        end
    end
end

addEventHandler("onWindowMessage", function(msg, wp)
    local window_open = main_window_state.v or auth_window_state.v

    -- Скрываем все нажатия клавиш от игры, пока окно открыто -- штобы ImGui-поля могли получать все нажатия
    if window_open and (msg == 0x100 or msg == 0x101 or msg == 0x102) then
        consumeWindowMessage(true, false)
    end

    if msg == 0x100 and wp == key.VK_ESCAPE and window_open then
        main_window_state.v = false
        auth_window_state.v = false
    end
end)
