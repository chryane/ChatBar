--[[ Core.lua - 频道模型 / 切换 / Tab 循环 / 事件
	 目标客户端：泰坦重铸 3.80.2（Interface 38002）。API 一律直调，不做存在性判断与兜底。
]]

local ADDON_NAME, ns = ...
local L = ns.L

local EMPTY = {}

local DEFAULTS = {
	anchor  = "input", -- "input" 吸附输入框 | "free" 任意位置
	locked  = true,    -- 仅 anchor == "free" 时有效
	bgAlpha = 0.5,     -- 0 = 最实、1 = 全透明（换算见 Bar.FillAlpha）
	systems = {},      -- [key] = false 表示不显示
	channels = {},     -- [频道基名] = { off = true, label = "自定义缩写" }
	funcs   = {},      -- [key] = true 表示显示
	point   = nil,     -- { point, relPoint, x, y }（恒相对 UIParent）
}

ns.SYSTEMS = {
	{ key = "SAY",      chatType = "SAY",           order = 10 },
	{ key = "YELL",     chatType = "YELL",          order = 20 },
	{ key = "PARTY",    chatType = "PARTY",         order = 30,
		avail = function() return IsInGroup(LE_PARTY_CATEGORY_HOME) end },
	{ key = "RAID",     chatType = "RAID",          order = 40,
		avail = function() return IsInRaid(LE_PARTY_CATEGORY_HOME) end },
	{ key = "INSTANCE", chatType = "INSTANCE_CHAT", order = 50,
		avail = function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end },
	{ key = "GUILD",    chatType = "GUILD",         order = 60,
		avail = function() return IsInGuild() end },
	{ key = "OFFICER",  chatType = "OFFICER",       order = 70,
		avail = function() return IsInGuild() end },
}

-- 功能方格：追加在频道方格之后（order 900+）；doubleClick 格单击不做任何事，只走 OnDoubleClick
ns.FUNCS = {
	{ key = "ROLL", order = 900, icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
		name = "FuncRoll", tip = "FuncRollTip", barTip = "TipRoll",
		run = function() RandomRoll(1, 100) end },
	{ key = "RELOAD", order = 910, icon = "Interface\\Buttons\\UI-RefreshButton",
		iconRatio = 0.66, doubleClick = true,
		name = "FuncReload", tip = "FuncReloadTip", barTip = "TipReload",
		run = function() ReloadUI() end },
}

-- 输入框的 leader/子类型在快捷条上归属的主类型（高亮匹配用）
ns.SUBTYPE_OF = {
	PARTY_LEADER = "PARTY", RAID_LEADER = "RAID", RAID_WARNING = "RAID",
	INSTANCE_CHAT_LEADER = "INSTANCE_CHAT", GUILD_ACHIEVEMENT = "GUILD",
}

-- "综合 - 奥格瑞玛" -> "综合"（名字可能带分区后缀，分隔符也可能是全角破折号）
local function ChannelBaseName(name)
	local pos = string.find(name, "-", 1, true)
	if not pos then pos = string.find(name, "\226\128\148", 1, true) end -- U+2014
	if not pos then pos = string.find(name, "\226\128\147", 1, true) end -- U+2013
	if not pos or pos == 1 then return name end
	return (string.gsub(string.sub(name, 1, pos - 1), "%s+$", ""))
end

-- UTF-8 安全取第一个字（中文一个字 3 字节）
local function Utf8First(s)
	return string.match(s, "^([\1-\127\194-\244][\128-\191]*)") or s
end

ns.Utf8First = Utf8First

local zoneAliasCache

local function NormalizeName(s)
	return (string.gsub(string.lower(s or ""), "%s+", ""))
end

local function GetZoneAliasTable()
	if not zoneAliasCache then
		-- pairs() 不走 ns.L 的 __index 元表，必须用 Localization 暴露的原始表
		zoneAliasCache = {}
		for _, def in pairs(ns.LOCALE) do
			if type(def) == "table" and def.aliases then
				for _, alias in ipairs(def.aliases) do
					zoneAliasCache[NormalizeName(alias)] = def
				end
			end
		end
	end
	return zoneAliasCache
end

local function MatchZoneChannel(name)
	local alias = GetZoneAliasTable()
	local base = ChannelBaseName(name)
	return alias[NormalizeName(base)] or alias[NormalizeName(name)], base
end

-- 号位 -> 已加入的 /N 号位；没加入返回 0（GetChannelName 对未加入频道不给号位）
local function JoinedChannelID(id, name)
	local n = GetChannelName(id)
	if n and n > 0 then return n end
	local byName = GetChannelName(name)
	if byName and byName > 0 then return byName end
	return 0
end

-- 枚举常规聊天频道：与游戏设置面板同源（GetChannelList 变参返回，3 步长消费 id/name/disabled）
local function EnumerateChannels()
	local list, seen = {}, {}
	local packed = { GetChannelList() }
	for i = 1, #packed - 2, 3 do
		local id, name = packed[i], packed[i + 1]
		if id > 0 and not seen[id] and not string.find(name, "^Community:") then
			seen[id] = true
			list[#list + 1] = { id = id, name = name, joined = JoinedChannelID(id, name) > 0 }
		end
	end
	return list
end

function ns:BuildEntries()
	local db = self.db
	local out = {}

	for _, sys in ipairs(self.SYSTEMS) do
		if db.systems[sys.key] ~= false then
			out[#out + 1] = {
				key = "TYPE:" .. sys.chatType,
				kind = "type",
				sys = sys,
				chatType = sys.chatType,
				label = L["Label" .. sys.key],
				available = not sys.avail or sys.avail(),
				order = sys.order,
			}
		end
	end

	for _, ch in ipairs(self.channels) do
		if not ch.off then
			out[#out + 1] = {
				key = "CHAN:" .. ch.id,
				kind = "channel",
				channelID = ch.id,
				available = ch.joined,
				label = ch.label,
				order = 100 + ch.id,
			}
		end
	end

	for _, fn in ipairs(self.FUNCS) do
		if db.funcs[fn.key] then
			out[#out + 1] = {
				key = "FUNC:" .. fn.key,
				kind = "func",
				func = fn,
				order = fn.order,
			}
		end
	end

	table.sort(out, function(a, b) return a.order < b.order end)
	return out
end

-- 频道表：快捷条条目与设置面板共用（含被关掉的与未加入的）
function ns:ListChannels()
	local list = {}
	for _, ch in ipairs(EnumerateChannels()) do
		local zoneDef, base = MatchZoneChannel(ch.name)
		local cfg = self.db.channels[base] or EMPTY
		local defaultLabel = (zoneDef and zoneDef.label) or Utf8First(base)
		list[#list + 1] = {
			id = ch.id,
			name = ch.name,
			base = base,
			joined = ch.joined,
			display = (zoneDef and zoneDef.name) or base,
			-- 缩写优先级：自定义 > 本地化默认 > 频道名首字
			label = cfg.label or defaultLabel,
			custom = cfg.label,
			defaultLabel = defaultLabel,
			off = cfg.off,
		}
	end
	return list
end

function ns:Refresh()
	self.channels = self:ListChannels()
	local entries = self:BuildEntries()
	self.entries = entries
	self.Bar:Update()
end

function ns:RefreshPanels()
	if self.Options.panel:IsShown() then self.Options:Reload() end
end

-- 名单事件只改可用性，轻刷状态即可，不必重建整组方格
function ns:UpdateAvailability()
	local changed
	for _, e in ipairs(self.entries or EMPTY) do
		if e.kind == "type" then
			local avail = not e.sys.avail or e.sys.avail()
			if e.available ~= avail then
				e.available = avail
				changed = true
			end
		end
	end
	if changed then self.Bar:RefreshStates() end
end

-- 开着就复用输入框（保住已敲的字），没开就把它叫出来
function ns:AcquireEditBox()
	local eb = ChatFrameUtil.GetActiveWindow()
	if eb then return eb end
	-- 不传文字：OpenChat 只在 text 非 nil 时才写文本框，传 "" 会清掉已敲内容
	return ChatFrameUtil.OpenChat()
end

function ns:SelectEntry(entry)
	if not entry then return false end
	if entry.kind == "func" then
		entry.func.run()
		return true
	end
	if entry.available == false then return false end

	local eb = self:AcquireEditBox()
	-- 社群/公会面板的聊天框占着焦点时，OpenChat 会把焦点让给它并返回 nil
	if not eb then return false end

	if entry.kind == "channel" then
		eb:SetChannelTarget(entry.channelID)
		eb:SetChatType("CHANNEL")
	else
		eb:SetChatType(entry.chatType)
	end
	-- 与暴雪一致：粘滞类型同步设为当前类型，发送后下次打开仍停在该频道
	eb:SetStickyType(eb:GetChatType())
	eb:UpdateHeader()
	self:RefreshActive()
	return true
end

-- -> 输入框所在格子的 key（"TYPE:SAY"/"CHAN:1"），不在条上返回 nil
function ns:ActiveKeyOf(eb)
	if not eb then return nil end
	local t = eb:GetChatType()
	if t == "CHANNEL" then
		local target = eb:GetChannelTarget()
		if target and target > 0 then return "CHAN:" .. target end
	elseif t then
		return "TYPE:" .. (self.SUBTYPE_OF[t] or t)
	end
end

function ns:GetActiveIndex(eb, entries)
	local key = self:ActiveKeyOf(eb)
	if not key then return 0 end
	for i = 1, #entries do
		if entries[i].key == key then return i end
	end
	return 0
end

-- Tab 轮转按条序循环（Shift 反向）；功能格跳过免得误触发，一圈无可用则交还客户端默认
function ns:Cycle(editBox, reverse)
	local entries = self.entries
	local n = #entries
	if n == 0 then return false end

	local cur = self:GetActiveIndex(editBox, entries)
	local step = reverse and -1 or 1
	local idx
	if cur == 0 then
		idx = reverse and n or 1
	else
		idx = cur + step
		if idx < 1 then idx = n elseif idx > n then idx = 1 end
	end

	for _ = 1, n do
		local e = entries[idx]
		if e.kind ~= "func" and e.available ~= false then
			return self:SelectEntry(e)
		end
		idx = idx + step
		if idx < 1 then idx = n elseif idx > n then idx = 1 end
	end
	return false
end

-- 官方预留的全局扩展点（返回 true 中止默认补全）；"/" 开头交回暴雪命令补全
local function TabHook(editBox)
	local text = editBox:GetText()
	if text and text ~= "" and string.sub(text, 1, 1) == "/" then return false end
	return ns:Cycle(editBox, IsShiftKeyDown())
end

function ns:InitDB()
	ChatBarDB = ChatBarDB or {}
	local db = ChatBarDB
	for k, v in pairs(DEFAULTS) do
		if type(v) == "table" then
			if type(db[k]) ~= "table" then db[k] = {} end
		elseif db[k] == nil then
			db[k] = v
		end
	end
	self.db = db
end

function ns:InitEvents()
	local f = CreateFrame("Frame")

	local function FullRefresh()
		self:Refresh()
		self:RefreshPanels()
		self.Bar:SyncVisible()
		self:RefreshActive()
	end

	-- 换序只重画快捷条：客户端不发 CHANNEL_UI_UPDATE，拖拽排序/上移下移都走这个入口；
	-- 不刷面板（游戏自带的聊天设置面板与插件设置面板互斥，刷了也是白刷）
	local function BarRefresh()
		self:Refresh()
		self.Bar:SyncVisible()
		self:RefreshActive()
	end

	local function AvailRefresh()
		self:UpdateAvailability()
	end

	-- 通用频道常常晚于 LOGIN / 换图才加入，各自兜一次延迟刷新
	local function LateRefresh(delay)
		C_Timer.After(delay, function() self:Refresh() self:RefreshPanels() end)
	end

	local HANDLERS = {
		PLAYER_LOGIN = function()
			ChatEdit_CustomTabPressed = TabHook
			hooksecurefunc(C_ChatInfo, "SwapChatChannelsByChannelIndex", BarRefresh)
			FullRefresh()
			LateRefresh(3)
		end,
		PLAYER_ENTERING_WORLD = function() FullRefresh() LateRefresh(2) end,
		GROUP_ROSTER_UPDATE = AvailRefresh,
		GUILD_ROSTER_UPDATE = AvailRefresh,
		CHANNEL_UI_UPDATE = FullRefresh,
		CHAT_MSG_CHANNEL_NOTICE = FullRefresh,
		ZONE_CHANGED_NEW_AREA = FullRefresh,
		-- 整扇聊天窗口被隐藏而输入框自己没 Hide 时，只有这两个 C 层事件会到
		UPDATE_CHAT_WINDOWS = FullRefresh,
		UPDATE_FLOATING_CHAT_WINDOWS = FullRefresh,
	}

	f:SetScript("OnEvent", function(_, event) HANDLERS[event]() end)
	for event in pairs(HANDLERS) do f:RegisterEvent(event) end
end

function ns:OnLoad()
	self:InitDB()
	self.Bar:Create()
	self:InitEvents()
end

SLASH_CHATBAR1 = "/cbar"
SlashCmdList["CHATBAR"] = function() ns.Options:Open() end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == ADDON_NAME then
		loader:UnregisterEvent("ADDON_LOADED")
		ns:OnLoad()
	end
end)
