--[[ Options.lua - 设置面板（仿游戏系统设置面板，注册走 Settings API）
	 顶部固定标题 + 内嵌滚动区，四个区块：
	   ① 显示设置（位置 / 锁定 / 背景透明度）
	   ② 系统频道（7 个勾选框，缩写固定）
	   ③ 通用频道（与游戏聊天设置同源，每行勾选框 + 缩写输入框）
	   ④ 其他功能（骰子 / 刷新）
]]

local ADDON_NAME, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

-- 两列网格：标签左对齐到 LABEL_X，控件列起点按最宽标签实测算出
local LABEL_X = 4
local CTRL_GAP = 50
-- 勾选框美术在 30×29 框体里居中，◄/► 底图差不多铺满 —— 往左补几个像素三行才齐
local CHECK_ART_INSET = 3

local STEP     = 30   -- 行距
local SEC_GAP  = -5   -- 上一区块底边 → 下一区块标题
local HEADER_H = 20   -- 区块标题 → 区域顶边
local BOX_PAD  = 10   -- 带边框区块的内边距

-- 顶部标题区（照 SettingsListTemplate.Header）
local TITLE_Y       = -8
local TITLE_LINE_DY = 38
local TITLE_GAP     = 14
local SCROLL_TOP    = TITLE_Y - TITLE_LINE_DY - TITLE_GAP

-- 滚动条几何照抄系统设置面板锚点（MinimalScrollBar 8px 宽，箭头左右各溢约 4.5px）
local SCROLL_RIGHT  = -14
local BAR_DY_TOP    = -4
local BAR_DY_BOTTOM = 7
local BAR_X_TOP     = 0
local BAR_X_BOTTOM  = -1

local SLIDER_W = 220

-- GameFontNormal/GameFontNormalLarge 原生色是金色，凡是要白的地方必须显式染白
local TEXT_GOLD  = { 1, 0.82, 0 }
local TEXT_WHITE = { 1, 1, 1 }
local TEXT_DIM   = { 0.5, 0.5, 0.5 }

local function Tint(text, c) text:SetTextColor(c[1], c[2], c[3]) end

local ANCHOR_VALUES = { "input", "free" }

local widgets = {}   -- { sync = function }：把 db 当前值刷回控件

local function AnchorText(v)
	return (v == "free") and L.AnchorFree or L.AnchorInput
end

local function CreateHint(parent, text, width)
	local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f:SetText(text)
	Tint(f, TEXT_WHITE)
	f:SetWidth(width)
	f:SetJustifyH("LEFT")
	return f
end

local function CreateLabel(parent, text)
	local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f:SetJustifyH("LEFT")
	f:SetText(text)
	Tint(f, TEXT_WHITE)
	return f
end

local function ControlColumnX(labels)
	local maxW = 0
	for i = 1, #labels do
		local w = labels[i]:GetStringWidth()
		if w > maxW then maxW = w end
	end
	return LABEL_X + maxW + CTRL_GAP
end

-- opts = { label, tipTitle, tipBody, icon, get, set, enabled, labelAfter }
local function CreateCheckbox(parent, opts)
	local cb = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
	cb:SetSize(30, 29)

	local after = cb
	if opts.icon then
		cb.icon = cb:CreateTexture(nil, "ARTWORK")
		cb.icon:SetTexture(opts.icon)
		cb.icon:SetSize(16, 16)
		cb.icon:SetPoint("LEFT", cb, "RIGHT", 6, 0)
		after = cb.icon
	end

	cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	cb.label:SetText(opts.label or "")
	Tint(cb.label, TEXT_WHITE)
	if opts.labelAfter ~= false then
		cb.label:SetJustifyH("LEFT")
		cb.label:SetPoint("LEFT", after, "RIGHT", 8, 0)
	end

	cb:SetScript("OnClick", function(button)
		if not button.canToggle then return end
		opts.set(button:GetChecked() and true or false)
		Options:Changed()
	end)
	if opts.tipTitle or opts.tipBody then
		cb.tipTitle, cb.tipBody = opts.tipTitle, opts.tipBody
		cb:SetScript("OnEnter", function(f)
			GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
			local t = type(f.tipTitle) == "function" and f.tipTitle() or f.tipTitle
			local b = type(f.tipBody) == "function" and f.tipBody() or f.tipBody
			if t then GameTooltip:AddLine(t, 1, 1, 1, true) end
			if b and b ~= "" then GameTooltip:AddLine(b, 0.9, 0.9, 0.9, true) end
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end

	cb.updateState = function(enabled)
		cb.canToggle = enabled
		cb:SetEnabled(enabled)
		local c = enabled and TEXT_WHITE or TEXT_DIM
		Tint(cb.label, c)
		if cb.icon then cb.icon:SetAlpha(enabled and 1 or 0.4) end
	end
	cb.updateState(opts.enabled ~= false)

	widgets[#widgets + 1] = {
		sync = function()
			cb:SetChecked(opts.get() and true or false)
			if opts.enabled then cb.updateState(opts.enabled() and true or false) end
		end,
	}
	return cb
end

-- ◄ / ► 按钮：状态手动切换（这对按钮从不置灰，无 disabled 态）
local function CreateArrowButton(parent, iconAtlas)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(26, 25)

	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAtlas("common-dropdown-c-button", true)
	b.bg:SetPoint("CENTER")

	b.icon = b:CreateTexture(nil, "OVERLAY")
	b.icon:SetAtlas(iconAtlas, true)
	b.icon:SetPoint("CENTER")

	local function state(hover, down)
		local name
		if hover and down then
			name = "common-dropdown-c-button-pressedhover-2"
		elseif hover then
			name = "common-dropdown-c-button-hover-2"
		elseif down then
			name = "common-dropdown-c-button-pressed-2"
		else
			name = "common-dropdown-c-button"
		end
		b.bg:SetAtlas(name, true)
		b.icon:ClearAllPoints()
		b.icon:SetPoint("CENTER", down and 2 or 0, down and -1 or 0)
	end

	b:SetScript("OnEnter", function() state(true, false) end)
	b:SetScript("OnLeave", function() state(false, false) end)
	b:SetScript("OnMouseDown", function() state(true, true) end)
	b:SetScript("OnMouseUp", function() state(true, false) end)
	return b
end

-- 弹出的选项列表 = 客户端自带的上下文菜单，元素用 CreateHighlightRadio（系统设置下拉同款）
local function ValueMenuGenerator(_, root, opts)
	for i = 1, #ANCHOR_VALUES do
		local v = ANCHOR_VALUES[i]
		local isSel = function() return opts.get() == v end
		local onSel = function() opts.set(v); Options:Changed() end
		root:CreateHighlightRadio(AnchorText(v), isSel, onSel, v)
	end
end

local function OpenValueMenu(owner, opts)
	-- MenuUtil 在 Blizzard_Menu（LoadOnDemand），面板打开时未必已加载
	if not MenuUtil then C_AddOns.LoadAddOn("Blizzard_Menu") end
	local root = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultContextMenuMixin())
	Menu.PopulateDescription(ValueMenuGenerator, owner, root, opts)
	root:SetMinimumWidth(owner:GetWidth())
	Menu.GetManager():OpenMenu(owner, root,
		AnchorUtil.CreateAnchor("TOPLEFT", owner, "BOTTOMLEFT", 0, 0))
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function CreateStepper(parent, opts)
	local dec = CreateArrowButton(parent, "common-dropdown-icon-back")

	local box = CreateFrame("Button", nil, parent)
	box:SetSize(opts.width or 150, 25)
	box.bg = box:CreateTexture(nil, "BACKGROUND")
	box.bg:SetAtlas("common-dropdown-c-button", true)
	-- 底图外扩 ±7 拉伸（该 atlas 自带 9-slice）
	box.bg:SetPoint("TOPLEFT", box, "TOPLEFT", -7, 7)
	box.bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 7, -7)
	box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	box.text:SetPoint("CENTER")
	Tint(box.text, TEXT_WHITE)

	local inc = CreateArrowButton(parent, "common-dropdown-icon-next")

	box:SetPoint("LEFT", dec, "RIGHT", 5, 0)
	inc:SetPoint("LEFT", box, "RIGHT", 5, 0)

	local function Shift(delta)
		local cur = opts.get()
		local idx = 1
		for i = 1, #ANCHOR_VALUES do
			if ANCHOR_VALUES[i] == cur then idx = i break end
		end
		idx = idx + delta
		if idx < 1 then idx = #ANCHOR_VALUES elseif idx > #ANCHOR_VALUES then idx = 1 end
		opts.set(ANCHOR_VALUES[idx])
		Options:Changed()
	end

	dec:SetScript("OnClick", function() Shift(-1) end)
	inc:SetScript("OnClick", function() Shift(1) end)
	box:SetScript("OnClick", function() OpenValueMenu(box, opts) end)
	-- hover 换底 + 提示写在同一个处理器里（SetScript 会互相覆盖）
	box:SetScript("OnEnter", function(f)
		box.bg:SetAtlas("common-dropdown-c-button-hover-2", true)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(opts.label, 1, 1, 1, true)
		GameTooltip:AddLine(opts.tipFunc(), 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(L.TipPickOpen, 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", function()
		box.bg:SetAtlas("common-dropdown-c-button", true)
		GameTooltip:Hide()
	end)

	widgets[#widgets + 1] = { sync = function() box.text:SetText(opts.textFunc()) end }
	return dec, box, inc
end

-- 进度条式滑条：MinimalSliderTemplate 的 Middle 段就是"已填充"，看起来即进度条
local function CreateSlider(parent, opts)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(15 + SLIDER_W + 15 + 8 + 44, 25)

	local slider = CreateFrame("Slider", nil, holder, "MinimalSliderTemplate")
	slider:SetSize(SLIDER_W, 19)
	slider:SetPoint("LEFT", holder, "LEFT", 15, 0)
	slider:SetMinMaxValues(opts.min, opts.max)
	slider:SetValueStep(opts.step)
	slider:SetObeyStepOnDrag(true)

	local function MakeStepButton(atlas, w, h, dir)
		local b = CreateFrame("Button", nil, holder)
		b:SetSize(w, h)
		b.tex = b:CreateTexture(nil, "BACKGROUND")
		b.tex:SetAtlas(atlas, true)
		b.tex:SetPoint("CENTER")
		if dir < 0 then
			b:SetPoint("RIGHT", slider, "LEFT", -4, 0)
		else
			b:SetPoint("LEFT", slider, "RIGHT", 4, 0)
		end
		return b
	end
	local back = MakeStepButton("Minimal_SliderBar_Button_Left", 11, 19, -1)
	local fwd  = MakeStepButton("Minimal_SliderBar_Button_Right", 9, 18, 1)

	local valueText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	valueText:SetPoint("LEFT", fwd, "RIGHT", 10, 0)
	Tint(valueText, TEXT_WHITE)

	-- Reload 把 db 值灌回滑条时不回写，避免触发多余的重建
	local syncing = false

	local function Apply(value, fromUser)
		-- 吸附到步进并夹在范围内：0.1 连加会给出 0.30000000000000004 这种值
		local v = opts.min + math.floor((value - opts.min) / opts.step + 0.5) * opts.step
		if v < opts.min then v = opts.min elseif v > opts.max then v = opts.max end
		ns.db.bgAlpha = v
		valueText:SetText(opts.format(v))
		-- 拖动过程每帧都进来：只改底色浓度（整条重建 = 每帧重新枚举频道，太贵）
		if fromUser then ns.Bar:RefreshFill() end
	end

	slider:SetScript("OnValueChanged", function(_, value)
		if not syncing then Apply(value, true) end
	end)
	back:SetScript("OnClick", function() Apply(ns.db.bgAlpha - opts.step, true) end)
	fwd:SetScript("OnClick", function() Apply(ns.db.bgAlpha + opts.step, true) end)

	-- 提示挂 holder：滑条自己播放 hover 反馈时不会把提示顶掉
	holder:EnableMouse(true)
	holder:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(opts.label, 1, 1, 1, true)
		GameTooltip:AddLine(opts.tip, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	holder:SetScript("OnLeave", function() GameTooltip:Hide() end)

	widgets[#widgets + 1] = {
		sync = function()
			syncing = true
			slider:SetValue(ns.db.bgAlpha)
			syncing = false
			valueText:SetText(opts.format(ns.db.bgAlpha))
		end,
	}
	return holder
end

-- 带边框区域：TooltipBackdropTemplate 的细亮边；底色 alpha=0 只要那一圈边
local function CreateBox(parent, width, height)
	local box = CreateFrame("Frame", nil, parent, "TooltipBackdropTemplate")
	box:SetBackdropColor(0, 0, 0, 0)
	box:SetBackdropBorderColor(0.62, 0.62, 0.62, 1)
	-- NineSlice 默认 frameLevel 很高，压回本框同层，免得盖住里面的勾选框
	box.NineSlice:SetFrameLevel(box:GetFrameLevel())
	box:SetSize(width, height)
	return box
end

local function CreateSectionHeader(parent, text)
	local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f:SetText(text)
	Tint(f, TEXT_GOLD)
	return f
end

-- 本客户端的 SCROLL_FRAME_SCROLL_BAR_TEMPLATE 指向未定义模板，
-- 必须自建 MinimalScrollBar 并用 ScrollUtil 胶水绑定
local function CreateScrollArea(panel)
	local s = CreateFrame("ScrollFrame", nil, panel)
	local b = CreateFrame("EventFrame", nil, s, "MinimalScrollBar")
	b:SetPoint("TOPLEFT", s, "TOPRIGHT", BAR_X_TOP, BAR_DY_TOP)
	b:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", BAR_X_BOTTOM, BAR_DY_BOTTOM)
	b:Show()
	ScrollUtil.InitScrollFrameWithScrollBar(s, b)
	return s
end

-- 标题悬停提示：FontString 收不到鼠标事件，挂在只盖住标题区的透明小框上；
-- 小框会吃掉滚轮，OnMouseWheel 里转回滚动框
local function CreateTitle(parent, scroll)
	if parent.title then return parent.title, parent.titleLine end

	parent.title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	parent.title:SetJustifyH("LEFT")
	parent.title:SetText(L.OptTitle)

	-- useAtlasSize=true：高度交给 atlas 原生粗细，宽度在 Layout 里用左右两锚点撑开
	parent.titleLine = parent:CreateTexture(nil, "ARTWORK")
	parent.titleLine:SetAtlas("Options_HorizontalDivider", true)

	local hover = CreateFrame("Frame", nil, parent)
	hover:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	hover:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	hover:SetHeight(48)
	hover:EnableMouse(true)
	hover:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L.OptTitle, 1, 1, 1, true)
		GameTooltip:AddLine(L.OptHint, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
	hover:SetScript("OnMouseWheel", function(_, delta)
		local handler = scroll:GetScript("OnMouseWheel")
		if handler then handler(scroll, delta) end
	end)
	return parent.title, parent.titleLine
end

function Options:Changed()
	ns:Refresh()
	ns.Bar:ApplyPosition()
	ns.Bar:SyncVisible()
	self:Reload()
end

-- 内容推迟到首次打开才建：整套帧/纹理不小，注册只需要空面板
function Options:Build()
	if self.panel then return end

	local panel = CreateFrame("Frame")
	panel.name = ADDON_NAME
	-- 必须显式 Hide：CreateFrame 默认显示，等设置界面真正挂载本面板时就不会触发 OnShow
	panel:Hide()
	self.panel = panel

	panel:SetScript("OnShow", function()
		if not self.content then self:BuildContent() end
		-- 填满 canvas 可视区：外层不产生第二根滚动条，滚动交给内嵌 scroll
		panel:ClearAllPoints()
		panel:SetAllPoints(panel:GetParent())
		self.content:SetWidth(self.scroll:GetWidth())
		Options:Reload()
	end)
end

function Options:BuildContent()
	local panel = self.panel

	local scroll = CreateScrollArea(panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, SCROLL_TOP)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", SCROLL_RIGHT, 4)
	self.scroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(520, 640)
	scroll:SetScrollChild(content)
	self.content = content

	scroll:SetScript("OnSizeChanged", function(_, w)
		if w > 0 then content:SetWidth(w) end
	end)

	self.title, self.titleLine = CreateTitle(panel, scroll)

	self:BuildDisplay(content)
	self:BuildSystems(content)
	self:BuildGeneralChannels(content)
	self:BuildFuncs(content)
end

function Options:BuildDisplay(parent)
	self.displayHeader = CreateSectionHeader(parent, L.SecDisplay)
	self.anchorLabel = CreateLabel(parent, L.OptAnchor)

	self.anchorDec, self.anchorBox, self.anchorInc = CreateStepper(parent, {
		label = L.OptAnchor,
		width = 150,
		get = function() return ns.db.anchor end,
		set = function(v) ns.db.anchor = v end,
		textFunc = function() return AnchorText(ns.db.anchor) end,
		tipFunc  = function()
			return ns.db.anchor == "free" and L.AnchorTipFree or L.AnchorTipInput
		end,
	})

	self.lockCheck = CreateCheckbox(parent, {
		label = L.OptLock,
		labelAfter = false,
		enabled = function() return ns.db.anchor == "free" end,
		get = function() return ns.db.locked end,
		set = function(v) ns.db.locked = v end,
		tipTitle = L.OptLock,
		tipBody  = L.LockTip,
	})
	self.lockLabel = self.lockCheck.label

	-- 背景透明度：0% = 最实、100% = 只剩边框；填充 alpha = 1 - bgAlpha
	self.bgLabel = CreateLabel(parent, L.OptBgAlpha)
	self.bgHolder = CreateSlider(parent, {
		min = 0, max = 1, step = 0.1,
		label = L.OptBgAlpha,
		tip = L.BgAlphaTip,
		format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
	})
end

function Options:BuildSystems(parent)
	self.sysHeader = CreateSectionHeader(parent, L.SecSystems)
	self.sysBox = CreateBox(parent, 480, 100)
	self.sysChecks = {}
	for i, sys in ipairs(ns.SYSTEMS) do
		local cb = CreateCheckbox(self.sysBox, {
			label = L["Name" .. sys.key],
			get = function() return ns.db.systems[sys.key] ~= false end,
			set = function(v) ns.db.systems[sys.key] = v end,
			tipTitle = L["Name" .. sys.key],
			-- 缩写固定值写进提示；再加一句"当前是否可用"，置灰的格子在面板上看不出原因
			tipBody = function()
				local text = string.format(L.SysFixedTip, L["Label" .. sys.key])
				if sys.avail and not sys.avail() then
					text = text .. "\n" .. L.SysUnavail
				end
				return text
			end,
		})
		cb.col = (i - 1) % 3
		cb.row = math.floor((i - 1) / 3)
		self.sysChecks[#self.sysChecks + 1] = cb
	end
end

function Options:BuildGeneralChannels(parent)
	self.chanHeader = CreateSectionHeader(parent, L.SecChannels)
	self.chanBox = CreateBox(parent, 480, 100)
	self.chanEmpty = CreateHint(self.chanBox, L.ChanEmpty, 440)
	self.chanEmpty:SetPoint("TOPLEFT", self.chanBox, "TOPLEFT", BOX_PAD + 4, -BOX_PAD - 4)
	self.chanRows = {}
end

local MAX_CHAN_ROWS = 20
function Options:GetChannelRow(i)
	local rows = self.chanRows
	if rows[i] then return rows[i] end

	local row = {}
	row.cb = CreateCheckbox(self.chanBox, {
		get = function()
			local cfg = ns.db.channels[row.base]
			return not (cfg and cfg.off)
		end,
		set = function(v)
			local chans = ns.db.channels
			chans[row.base] = chans[row.base] or {}
			-- 必须写成 if：`v and nil or true` 恒为 true，取消勾选就再也勾不回来
			if v then
				chans[row.base].off = nil
			else
				chans[row.base].off = true
			end
		end,
	})

	row.edit = CreateFrame("EditBox", nil, self.chanBox, "InputBoxTemplate")
	row.edit:SetSize(70, 20)
	row.edit:SetAutoFocus(false)
	-- 缩写只允许一个字：中文一个字 3 字节，上限给 3 字节正好一个汉字
	row.edit:SetMaxLetters(3)
	row.edit:SetScript("OnEscapePressed", function(f) f:ClearFocus() end)
	row.edit:SetScript("OnEnterPressed", function(f)
		f:ClearFocus()
		Options:CommitChannelLabel(row)
	end)
	row.edit:SetScript("OnEditFocusLost", function() Options:CommitChannelLabel(row) end)
	row.edit:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(f.titleText, 1, 1, 1, true)
		GameTooltip:AddLine(f.tipText, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	row.edit:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row.cb:SetScript("OnEnter", function(f)
		GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
		GameTooltip:AddLine(f.tipTitle, 1, 1, 1, true)
		GameTooltip:AddLine(f.tipBody, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	row.cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

	rows[i] = row
	widgets[#widgets + 1] = {
		sync = function()
			-- 刚建好、还没被布局分配过频道的行 row.base 为 nil，必须跳过
			if not row.base then return end
			local cfg = ns.db.channels[row.base]
			row.cb:SetChecked(not (cfg and cfg.off))
			-- 正在输入时不回写，否则光标/内容被打断
			if not row.edit:HasFocus() then row.edit:SetText(row.custom or "") end
		end,
	}
	return row
end

function Options:CommitChannelLabel(row)
	if not row.base then return end
	local text = string.match(row.edit:GetText(), "^%s*(.-)%s*$")
	local chans = ns.db.channels
	chans[row.base] = chans[row.base] or {}
	if text ~= "" then
		chans[row.base].label = ns.Utf8First(text)
	else
		chans[row.base].label = nil
	end
	ns:Refresh()
end

function Options:BuildFuncs(parent)
	self.funcHeader = CreateSectionHeader(parent, L.SecFuncs)
	self.funcBox = CreateBox(parent, 480, 100)
	self.funcChecks = {}
	for i, fn in ipairs(ns.FUNCS) do
		local cb = CreateCheckbox(self.funcBox, {
			label = L[fn.name],
			icon = fn.icon,
			get = function() return ns.db.funcs[fn.key] end,
			set = function(v) ns.db.funcs[fn.key] = v and true or nil end,
			tipTitle = L[fn.name],
			tipBody = L[fn.tip],
		})
		cb.rowIndex = i - 1
		self.funcChecks[#self.funcChecks + 1] = cb
	end
end

-- 每次 Reload 重算：通用频道行数随加入/退出变化
function Options:Layout()
	-- SetPoint 是"占位"语义，上一次的锚点不会自己消失，每次先清空
	local cleared = {
		self.title, self.titleLine,
		self.displayHeader, self.anchorLabel, self.anchorDec, self.lockLabel, self.lockCheck,
		self.bgLabel, self.bgHolder,
		self.sysHeader, self.sysBox, self.chanHeader, self.chanBox,
		self.funcHeader, self.funcBox,
	}
	for i = 1, #cleared do cleared[i]:ClearAllPoints() end
	for _, cb in ipairs(self.sysChecks) do cb:ClearAllPoints() end
	for _, cb in ipairs(self.funcChecks) do cb:ClearAllPoints() end

	local content = self.content
	local W = content:GetWidth()
	if W < 100 then W = 520 end
	local boxW = W - 8
	local colW = (boxW - BOX_PAD * 2) / 3

	local y = 0
	local rowMid = STEP / 2

	-- ⓪ 标题 + 横线锚在面板上（不参与滚动）
	self.title:SetPoint("TOPLEFT", LABEL_X, TITLE_Y)
	local lineY = TITLE_Y - TITLE_LINE_DY
	self.titleLine:SetPoint("TOPLEFT", 0, lineY)
	self.titleLine:SetPoint("TOPRIGHT", 0, lineY)

	local ctrlX = ControlColumnX({ self.anchorLabel, self.lockLabel, self.bgLabel })

	-- ① 显示设置
	self.displayHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - 26

	self.anchorLabel:SetPoint("LEFT", content, "TOPLEFT", LABEL_X, y - rowMid)
	self.anchorDec:SetPoint("LEFT", content, "TOPLEFT", ctrlX, y - rowMid)
	self.anchorBox:SetPoint("LEFT", self.anchorDec, "RIGHT", 5, 0)
	self.anchorInc:SetPoint("LEFT", self.anchorBox, "RIGHT", 5, 0)
	y = y - STEP

	self.lockLabel:SetPoint("LEFT", content, "TOPLEFT", LABEL_X, y - rowMid)
	-- 勾选框往左补回美术内缩，"看得见的框"才和另外两行对齐
	self.lockCheck:SetPoint("LEFT", content, "TOPLEFT", ctrlX - CHECK_ART_INSET, y - rowMid)
	y = y - STEP

	self.bgLabel:SetPoint("LEFT", content, "TOPLEFT", LABEL_X, y - rowMid)
	self.bgHolder:SetPoint("LEFT", content, "TOPLEFT", ctrlX, y - rowMid)
	y = y - STEP

	-- ② 系统频道
	local sysRows = math.ceil(#self.sysChecks / 3)
	local sysBoxH = BOX_PAD * 2 + sysRows * STEP + (sysRows - 1) * 2
	y = y - SEC_GAP - HEADER_H
	self.sysHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - HEADER_H
	self.sysBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	self.sysBox:SetSize(boxW, sysBoxH)
	for _, cb in ipairs(self.sysChecks) do
		cb:SetPoint("TOPLEFT", self.sysBox, "TOPLEFT",
			BOX_PAD + cb.col * colW, -(BOX_PAD + cb.row * (STEP + 2)))
	end
	y = y - sysBoxH

	-- ③ 通用频道：复用 ns:Refresh() 枚举的那一份，不在这里再枚举一遍
	local chans = ns.channels
	local rowCount = math.min(#chans, MAX_CHAN_ROWS)
	local boxRows = math.max(1, rowCount)
	local chanBoxH = BOX_PAD * 2 + boxRows * STEP + (boxRows - 1) * 2
	y = y - SEC_GAP - HEADER_H
	self.chanHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - HEADER_H
	self.chanBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	self.chanBox:SetSize(boxW, chanBoxH)
	self.chanEmpty:SetShown(#chans == 0)

	-- 行按需创建：只建到实际频道数，多建的旧行（频道变少后）隐藏复用
	for i = 1, math.max(rowCount, #self.chanRows) do
		local ch = chans[i]
		local row = ch and self:GetChannelRow(i) or self.chanRows[i]
		if row then
			if ch then
				local rowY = -(BOX_PAD + (i - 1) * (STEP + 2))
				row.base = ch.base
				row.custom = ch.custom -- 只回显用户自己写的那个，默认缩写不进输入框
				row.cb.label:SetText(ch.display)
				row.cb:ClearAllPoints()
				row.cb:SetPoint("TOPLEFT", self.chanBox, "TOPLEFT", BOX_PAD, rowY)
				row.edit:ClearAllPoints()
				row.edit:SetPoint("TOPLEFT", self.chanBox, "TOPLEFT",
					boxW - BOX_PAD - 70, rowY - 5)
				-- 提示文字随行换频道才重建，不必每次布局都拼
				if row.tipName ~= ch.name then
					row.tipName = ch.name
					row.cb.tipTitle = ch.display
					row.cb.tipBody = string.format(L.ChanNameTip, ch.id, ch.name)
					row.edit.titleText = ch.display
					row.edit.tipText = string.format(L.ChanInputTip, ch.defaultLabel)
				end
			end
			row.cb:SetShown(ch ~= nil)
			row.edit:SetShown(ch ~= nil)
		end
	end
	y = y - chanBoxH

	-- ④ 其他功能
	local funcBoxH = BOX_PAD * 2 + #self.funcChecks * STEP
	y = y - SEC_GAP - HEADER_H
	self.funcHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	y = y - HEADER_H
	self.funcBox:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
	self.funcBox:SetSize(boxW, funcBoxH)
	for _, cb in ipairs(self.funcChecks) do
		cb:SetPoint("TOPLEFT", self.funcBox, "TOPLEFT", BOX_PAD,
			-(BOX_PAD + cb.rowIndex * STEP))
	end
	y = y - funcBoxH - 10

	content:SetHeight(-y + 12)
end

function Options:Reload()
	self:Layout()
	for i = 1, #widgets do
		widgets[i].sync()
	end
end

function Options:Open()
	Settings.OpenToCategory(self.category:GetID())
end

-- 文件加载即构建 + 注册（登录时系统设置已就绪，注册只需要空面板）
Options:Build()

local category = Settings.RegisterCanvasLayoutCategory(Options.panel, L.OptPanel)
Settings.RegisterAddOnCategory(category)
Options.category = category
