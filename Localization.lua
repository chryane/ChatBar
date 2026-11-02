--[[ Localization.lua - 本地化字符串
     默认中文，缺失的键回退英文，再缺失则回显键名。
]]

local ADDON_NAME, ns = ...

local LOCALES = {
	zhCN = {
		-- 系统频道缩写（方格上的固定文字）
		LabelSAY      = "说",
		LabelYELL     = "喊",
		LabelPARTY    = "队",
		LabelRAID     = "团",
		LabelINSTANCE = "副",
		LabelGUILD    = "会",
		LabelOFFICER  = "官",

		-- 系统频道全名（勾选框文字 + 提示标题）
		NameSAY      = "说",
		NameYELL     = "喊",
		NamePARTY    = "小队",
		NameRAID     = "团队",
		NameINSTANCE = "副本/战场",
		NameGUILD    = "公会",
		NameOFFICER  = "官员",

		-- 通用频道：识别别名 + 默认缩写 + 全名
		ZoneGeneral     = { aliases = { "general", "综合", "一般" }, label = "综", name = "综合" },
		ZoneTrade       = { aliases = { "trade", "交易" }, label = "交", name = "交易" },
		ZoneLFG         = { aliases = { "lookingforgroup", "looking for group", "寻求组队", "组队" }, label = "组", name = "寻求组队" },
		ZoneLocalDef    = { aliases = { "localdefense", "local defense", "本地防务" }, label = "防", name = "本地防务" },
		ZoneWorldDef    = { aliases = { "worlddefense", "world defense", "世界防务" }, label = "世", name = "世界防务" },
		ZoneRecruit     = { aliases = { "guildrecruitment", "guild recruitment", "公会招募" }, label = "招", name = "公会招募" },

		-- 鼠标提示：频道格不弹，只有抓手与功能方格弹
		TipGripTitle = "移动快捷条",
		TipRoll      = "|cffeda55f左键|r：发送 /roll（1-100）",
		TipReload    = "|cffeda55f双击|r：重载界面（/reload）|cff808080（防误触）|r",

		-- 设置面板
		OptTitle     = "ChatBar - 聊天频道快捷条",
		OptPanel     = "ChatBar",
		SecDisplay   = "显示设置",
		SecSystems   = "系统频道",
		SecChannels  = "通用频道",
		SecFuncs     = "其他功能",

		OptAnchor      = "位置",
		AnchorInput    = "吸附输入框",
		AnchorFree     = "任意位置",
		OptLock        = "锁定",
		OptBgAlpha     = "背景透明度",
		BgAlphaTip     = "方格底色的透明度。0% = 底色最实，100% = 完全透明（只剩边框）。百分比越大越透明。",
		LockTip        = "锁定后无法拖动快捷条。",
		AnchorTipInput = "快捷条吸附在聊天输入框下方，并跟随输入框显隐。",
		AnchorTipFree  = "可以在游戏界面内自由拖动快捷条（需先取消勾选「锁定」）。",
		TipPickOpen    = "点击展开列表，也可以用两侧箭头逐项切换。",

		SysFixedTip  = "固定缩写：|cffffffff%s|r",
		SysUnavail   = "|cff808080当前不可用|r",
		ChanInputTip = "自定义缩写（留空 = %s）",
		ChanEmpty    = "当前没有已加入的通用频道。",
		ChanNameTip  = "频道 %d：%s",

		FuncRoll       = "投掷骰子",
		FuncRollTip    = "在快捷条末尾追加一个骰子方格，点击后发送 /roll（1-100）。",
		FuncReload     = "重载界面",
		FuncReloadTip  = "在快捷条末尾追加一个刷新方格，|cffffffff双击|r后重载界面（/reload）—— 单击不动作，避免误触。",

		OptHint      = "通用频道来自你已加入的聊天频道，勾选即时生效。方格尺寸、间距、字号等在 Bar.lua 顶部常量中调整。",
	},
	enUS = {
		LabelSAY      = "S",
		LabelYELL     = "Y",
		LabelPARTY    = "P",
		LabelRAID     = "R",
		LabelINSTANCE = "I",
		LabelGUILD    = "G",
		LabelOFFICER  = "O",

		NameSAY      = "Say",
		NameYELL     = "Yell",
		NamePARTY    = "Party",
		NameRAID     = "Raid",
		NameINSTANCE = "Instance/Battleground",
		NameGUILD    = "Guild",
		NameOFFICER  = "Officer",

		ZoneGeneral     = { aliases = { "general" }, label = "Gen", name = "General" },
		ZoneTrade       = { aliases = { "trade" }, label = "Trd", name = "Trade" },
		ZoneLFG         = { aliases = { "lookingforgroup", "looking for group" }, label = "LFG", name = "Looking For Group" },
		ZoneLocalDef    = { aliases = { "localdefense", "local defense" }, label = "Def", name = "Local Defense" },
		ZoneWorldDef    = { aliases = { "worlddefense", "world defense" }, label = "WDef", name = "World Defense" },
		ZoneRecruit     = { aliases = { "guildrecruitment", "guild recruitment" }, label = "Rec", name = "Guild Recruitment" },

		TipGripTitle = "Move the bar",
		TipRoll      = "|cffeda55fLeft-click|r: send /roll (1-100)",
		TipReload    = "|cffeda55fDouble-click|r: reload the UI (/reload)|cff808080 (guards against misclicks)|r",

		OptTitle     = "ChatBar - Chat Channel Bar",
		OptPanel     = "ChatBar",
		SecDisplay   = "Display",
		SecSystems   = "System Channels",
		SecChannels  = "General Channels",
		SecFuncs     = "Other Functions",

		OptAnchor      = "Position",
		AnchorInput    = "Attach to edit box",
		AnchorFree     = "Anywhere",
		OptLock        = "Lock",
		OptBgAlpha     = "Background",
		BgAlphaTip     = "Transparency of the square background. 0% = solid, 100% = fully see-through (border only). Higher = more transparent.",
		LockTip        = "Prevents the bar from being dragged.",
		AnchorTipInput = "The bar sits just below the chat edit box and follows its visibility.",
		AnchorTipFree  = "Drag the bar anywhere on screen (uncheck Lock first).",
		TipPickOpen    = "Click to open the list, or use the arrows to step through values.",

		SysFixedTip  = "Fixed label: |cffffffff%s|r",
		SysUnavail   = "|cff808080Currently unavailable|r",
		ChanInputTip = "Custom label (empty = %s)",
		ChanEmpty    = "No general channel joined yet.",
		ChanNameTip  = "Channel %d: %s",

		FuncRoll       = "Roll dice",
		FuncRollTip    = "Appends a dice button that sends /roll (1-100).",
		FuncReload     = "Reload UI",
		FuncReloadTip  = "Appends a refresh button; |cffffffffdouble-click|r it to reload the UI (/reload) - a single click does nothing.",

		OptHint      = "General channels come from the channels you joined; changes apply immediately. Size/spacing/font are constants at the top of Bar.lua.",
	},
}

local locale = GetLocale()
local fallback = LOCALES.zhCN
local tbl = LOCALES[locale] or fallback

ns.LOCALE = tbl -- 原始表：pairs() 需要真实遍历（如别名表），不能走 ns.L 的 __index

ns.L = setmetatable({}, {
	__index = function(_, key)
		return tbl[key] or fallback[key] or key
	end,
})
