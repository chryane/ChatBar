--[[ Bar.lua - 屏幕上的频道快捷条
	 方格两层纹理：底色层（UI-Frame-Button 材质染黑，浓度 = 1 - ns.db.bgAlpha）+ 面层（同材质，选中染金）。
	 文字三态：普通浅粉 / 当前频道金 / 未加入系统频道灰（只灰文字，方框不变）。
	 anchor == "input"：吸附当前输入框下方并跟随显隐；"free"：落在 db.point 坐标，未锁定时条首有细抓手可拖。
	 条的状态全部由事件/钩子驱动，不装 OnUpdate。
]]

local ADDON_NAME, ns = ...
local L = ns.L

local Bar = {}
ns.Bar = Bar

local FRAME_TEX = "Interface\\AddOns\\ChatBar\\Textures\\UI-Frame-Button.tga"
local SIZE, GAP, FONT_SIZE = 24, 1, 14
local PAD = 4
local GRIP_W = 5
local GRIP_HIT_PAD = 8              -- 5px 细条不好点中：命中区只往左扩（右边会抢方格点击区）
local FUNC_ICON_RATIO = 0.78        -- 功能格图标占方格边长比例（fun.iconRatio 可覆盖）
local INPUT_DX, INPUT_DY = 0, 2

local TEXT_WHITE    = { 1, 1, 1 }
local TEXT_CHAT     = { 1, 0.75, 0.75 } -- GameFontNormalSmall 原生是金色，必须显式设色
local TEXT_ACTIVE  = { 1, 0.82, 0 }
local TEXT_DISABLED = { 0.5, 0.5, 0.5 }

local function Tint(text, c) text:SetTextColor(c[1], c[2], c[3]) end
local function Paint(tex, c) tex:SetVertexColor(c[1], c[2], c[3]) end

local function FillAlpha()
	return 1 - ns.db.bgAlpha
end

function Bar:ApplyFill(btn, hover)
	local a = FillAlpha()
	if hover then a = math.min(1, a + 0.22) end
	btn.bg:SetAlpha(a)
end

function Bar:Style(btn, active)
	local e = btn.entry
	if e.available == false then
		Paint(btn.border, TEXT_WHITE)
		Tint(btn.label, TEXT_DISABLED)
	elseif active then
		Paint(btn.border, TEXT_ACTIVE)
		Tint(btn.label, TEXT_ACTIVE)
	else
		Paint(btn.border, TEXT_WHITE)
		Tint(btn.label, TEXT_CHAT)
	end
	self:ApplyFill(btn, nil)
end

local function AddSquareLayers(f)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetTexture(FRAME_TEX)
	f.bg:SetVertexColor(0, 0, 0)
	f.bg:SetAllPoints()
	f.bg:SetAlpha(FillAlpha())

	f.border = f:CreateTexture(nil, "BORDER")
	f.border:SetTexture(FRAME_TEX)
	f.border:SetAllPoints()
	Paint(f.border, TEXT_WHITE)
end

function Bar:Acquire(index)
	local btn = self.buttons[index]
	if btn then return btn end

	btn = CreateFrame("Button", nil, self.frame)
	AddSquareLayers(btn)

	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetPoint("CENTER")
	btn.icon:SetSize(20, 20)
	btn.icon:Hide()

	btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	btn.label:SetFont(ChatFrame1:GetFont(), FONT_SIZE, "OUTLINE")
	btn.label:SetJustifyH("CENTER")
	btn.label:SetJustifyV("MIDDLE")
	btn.label:SetShadowOffset(0, 0) -- 关掉模板自带投影（会把字看得偏下）
	btn.label:SetPoint("CENTER", btn, "CENTER", 0, 0)

	-- 客户端双击时先派发 OnClick 再派发 OnDoubleClick：doubleClick 格必须挡掉单击
	btn:SetScript("OnClick", function(button)
		local e = button.entry
		local fn = e.func
		if not fn or not fn.doubleClick then ns:SelectEntry(e) end
	end)
	btn:SetScript("OnDoubleClick", function(button)
		local e = button.entry
		local fn = e.func
		if fn and fn.doubleClick then ns:SelectEntry(e) end
	end)
	btn:SetScript("OnEnter", function(button)
		if button:IsEnabled() then self:ApplyFill(button, true) end
		self:ShowTip(button)
	end)
	btn:SetScript("OnLeave", function(button)
		self:Style(button, button.entry.key == self.activeKey)
		GameTooltip:Hide()
	end)

	self.buttons[index] = btn
	return btn
end

-- 鼠标提示只给功能格（频道格的缩写字本身就是信息）
function Bar:ShowTip(btn)
	local e = btn.entry
	if e.kind ~= "func" then return end
	GameTooltip:SetOwner(btn, "ANCHOR_TOP")
	GameTooltip:AddLine(L[e.func.name])
	GameTooltip:AddLine(L[e.func.barTip], 1, 1, 1)
	GameTooltip:Show()
end

function Bar:CreateGrip()
	if self.grip then return self.grip end

	local g = CreateFrame("Button", nil, self.frame)
	g:SetSize(GRIP_W, SIZE)
	AddSquareLayers(g)
	g:SetHitRectInsets(-GRIP_HIT_PAD, 0, 0, 0)

	g:RegisterForDrag("LeftButton")
	g:SetScript("OnDragStart", function()
		if not self:CanDrag() then return end
		self.dragging = true
		self.frame:StartMoving()
	end)
	g:SetScript("OnDragStop", function()
		if not self.dragging then return end
		self.dragging = nil
		self.frame:StopMovingOrSizing()
		if not self:IsInputMode() then
			local point, _, relPoint, x, y = self.frame:GetPoint(1)
			ns.db.point = { point = point, relPoint = relPoint, x = x, y = y }
		end
	end)
	g:SetScript("OnEnter", function(btn)
		self:ApplyFill(btn, true)
		GameTooltip:SetOwner(btn, "ANCHOR_TOP")
		GameTooltip:AddLine(L.TipGripTitle, 1, 1, 1)
		GameTooltip:Show()
	end)
	g:SetScript("OnLeave", function(btn)
		self:ApplyFill(btn, nil)
		GameTooltip:Hide()
	end)

	self.grip = g
	return g
end

-- 本客户端每个聊天窗口各有一个输入框，取法照客户端自己的判据
function Bar:GetEditBox()
	return ChatFrameUtil.GetLastActiveWindow()
		or ChatFrameUtil.GetActiveWindow()
		or _G.ChatFrame1.editBox
end

function Bar:IsInputMode()
	return ns.db.anchor ~= "free"
end

function Bar:CanDrag()
	return (not self:IsInputMode()) and (not ns.db.locked)
end

-- IsShown() 含祖先链，够判断"整扇窗口/输入框是否可见"；im 样式下输入框是常显变暗，不看 alpha
function Bar:SyncVisible()
	self.frame:SetShown(not self:IsInputMode() or self:GetEditBox():IsShown())
end

function Bar:OnEditBoxChanged()
	if self:IsInputMode() then
		self:ApplyPosition()
	end
	self:SyncVisible()
end

function Bar:ApplyPosition()
	local f = self.frame
	f:ClearAllPoints()
	if self:IsInputMode() then
		f:SetPoint("TOPLEFT", self:GetEditBox(), "BOTTOMLEFT", INPUT_DX, INPUT_DY)
		f:SetMovable(false)
	else
		local p = ns.db.point
		if p and p.point then
			f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
		else
			-- 首次切到任意位置：默认落在输入框下方
			f:SetPoint("TOPLEFT", self:GetEditBox(), "BOTTOMLEFT", INPUT_DX, INPUT_DY)
		end
		f:SetMovable(not ns.db.locked)
	end
end

function Bar:HookChatFrameUtil()
	local changed = function() self:OnEditBoxChanged() end
	hooksecurefunc(ChatFrameUtil, "SetLastActiveWindow", changed)
	hooksecurefunc(ChatFrameUtil, "DeactivateChat", changed)
	hooksecurefunc(ChatFrameUtil, "ActivateChat", changed)
end

function Bar:HookEditBoxes()
	local changed = function() ns:RefreshActive() end
	for i = 1, 10 do
		local cf = _G["ChatFrame" .. i]
		local eb = cf and cf.editBox
		if eb then
			-- XML 的 OnShow/OnHide 用 SetScript 存了函数引用，替换字段无效，必须 HookScript
			eb:HookScript("OnShow", function() self:OnEditBoxChanged() end)
			eb:HookScript("OnHide", function() self:SyncVisible() end)
			hooksecurefunc(eb, "SetChatType", changed)
			hooksecurefunc(eb, "SetChannelTarget", changed)
		end
	end
end

function Bar:Update()
	local entries = ns.entries or {}
	local size = SIZE
	local x = PAD
	-- 缩写字用聊天同款字体：聊天字体可调，路径一变就整条重设一遍
	local fontPath = ChatFrame1:GetFont()
	if fontPath ~= self.fontPath then
		self.fontPath = fontPath
		for i = 1, #self.buttons do
			self.buttons[i].label:SetFont(fontPath, FONT_SIZE, "OUTLINE")
		end
	end

	if self:CanDrag() then
		local g = self:CreateGrip()
		g:SetSize(GRIP_W, size)
		g:ClearAllPoints()
		g:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD, -PAD)
		g.bg:SetAlpha(FillAlpha())
		g:Show()
		x = x + GRIP_W
	elseif self.grip then
		self.grip:Hide()
	end

	for i, entry in ipairs(entries) do
		local btn = self:Acquire(i)
		if i > 1 or x > PAD then x = x + GAP end
		btn.entry = entry
		btn:SetSize(size, size)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -PAD)

		if entry.kind == "func" then
			btn.label:SetText("")
			btn.icon:SetTexture(entry.func.icon)
			local iconSize = size * (entry.func.iconRatio or FUNC_ICON_RATIO)
			btn.icon:SetSize(iconSize, iconSize)
			btn.icon:Show()
		else
			btn.icon:Hide()
			btn.label:SetText(entry.label)
		end

		btn:SetEnabled(entry.available ~= false)
		btn:SetAlpha(1)
		self:Style(btn, entry.key == self.activeKey)
		btn:Show()
		x = x + size
	end

	for i = #entries + 1, #self.buttons do
		self.buttons[i]:Hide()
		self.buttons[i].entry = nil
	end

	-- 一格都没有时留一格宽度，框体不至于退化成一条线
	if x == PAD then x = PAD + size end
	self.frame:SetSize(x + PAD, size + PAD * 2)
end

function Bar:RefreshStates()
	for i, btn in ipairs(self.buttons) do
		if btn:IsShown() then
			local e = btn.entry
			btn:SetEnabled(e.available ~= false)
			self:Style(btn, e.key == self.activeKey)
		end
	end
end

-- 只把底色浓度刷一遍（拖透明度滑条时每帧都会进，比重整条便宜得多）
function Bar:RefreshFill()
	local a = FillAlpha()
	if self.grip then self.grip.bg:SetAlpha(a) end
	for i = 1, #self.buttons do
		self.buttons[i].bg:SetAlpha(a)
	end
end

function ns:RefreshActive()
	local bar = self.Bar
	if not bar.frame:IsShown() then return end

	local activeKey = self:ActiveKeyOf(bar:GetEditBox())
	if activeKey == bar.activeKey then return end
	bar.activeKey = activeKey

	for i = 1, #bar.buttons do
		local btn = bar.buttons[i]
		if btn:IsShown() then
			bar:Style(btn, btn.entry.key == activeKey)
		end
	end
end

function Bar:Create()
	if self.frame then return end

	local frame = CreateFrame("Frame", "ChatBarFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(false) -- 点击一律落到底下的方格/抓手上，拖动只认抓手
	frame:SetScript("OnShow", function() ns:RefreshActive() end)

	self.frame = frame
	self.buttons = {}
	self:HookChatFrameUtil()
	self:HookEditBoxes()
	self:ApplyPosition()
	self:Update()
	self:SyncVisible()
end
