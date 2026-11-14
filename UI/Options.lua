-- Settings tab of the ledger, plus the minimap button.
local _, ns = ...
local O = {}
ns.Options = O

local CHECKS = {
    { "heraldGuild", "Announce fines in guild chat" },
    { "heraldParty", "Announce fines in party / raid chat (only when earned in a group)" },
    { "pettyPublic", "Also announce Petty (-5) fines" },
    { "quiet", "Quiet mode: announce nothing, answer no whispers" },
    { "whisper", "Answer !dkp and !shame whispers" },
    { "toast", "Show the toast" },
    { "sound", "Play the toast sound" },
    { "tooltip", "Show other users' balance on their tooltip" },
    { "ownTooltip", "Show your balance on your own tooltip" },
    { "repeatable", "Repeatable fines: some feats fine you again (max once an hour)" },
    { "experimental", "Unverified feats: enable C-rated feats that may not work on Forever" },
}
local TIER_STEPS = { 50, 100, 250, 500 }
local SHARE_STEPS = { "GUILD", "PARTY", "SAY" }

local changed = false
local function Changed() changed = true end

local function Check(parent, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    local text = cb.Text or cb.text
    if not text then
        text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetFontObject("GameFontHighlightSmall")
    text:SetTextColor(0.20, 0.12, 0.05)
    text:SetText(label)
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Changed()
    end)
    cb:SetChecked(get())
    return cb
end

local function Cycle(parent, x, y, width, steps, key, label)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    local function Update() b:SetText(label(ns.settings[key])) end
    b:SetScript("OnShow", Update)
    b:SetScript("OnClick", function()
        local at = 1
        for i, v in ipairs(steps) do if v == ns.settings[key] then at = i end end
        ns.settings[key] = steps[at % #steps + 1]
        Update()
        Changed()
    end)
    Update()
    return b
end

local function UrlPopup(title, url)
    StaticPopupDialogs.FIFTYDKPMINUS_URL = StaticPopupDialogs.FIFTYDKPMINUS_URL or {
        text = "%s\nCopy this link (Ctrl+C):",
        button1 = OKAY or "Okay", hasEditBox = true, editBoxWidth = 320,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
            if box then box:SetText(data or "") box:HighlightText() box:SetFocus() end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("FIFTYDKPMINUS_URL", title, nil, url)
end

StaticPopupDialogs.FIFTYDKPMINUS_RESET = {
    text = "Wipe this character's ledger? Every fine, counter and feat is erased. This cannot be undone.",
    button1 = "Wipe it", button2 = CANCEL or "Cancel",
    OnAccept = function() ns.Engine.ResetCharacter() ns.Print("Ledger wiped. A clean sheet. Enjoy it while it lasts.") end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
}

function O.Build(panel)
    local y = -8
    for _, c in ipairs(CHECKS) do
        local key = c[1]
        Check(panel, c[2], 10, y, function() return ns.settings[key] end, function(v) ns.settings[key] = v end)
        y = y - 21
    end

    Cycle(panel, 12, y - 6, 220, TIER_STEPS, "minTier", function(v) return "Announce from: " .. ns.TierOf(v).name .. " (-" .. v .. ")" end)
    Cycle(panel, 240, y - 6, 220, SHARE_STEPS, "shareChannel", function(v) return "/minus last goes to: " .. v:lower() end)
    y = y - 36

    local head = ns.Ledger.Text(panel, "GameFontNormal")
    head:SetPoint("TOPLEFT", 14, y)
    head:SetText("Feat packs")
    y = y - 16
    for i, pack in ipairs(ns.packOrder) do
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        Check(panel, pack, 10 + col * 140, y - row * 21,
            function() return not ns.settings.packsOff[pack] end,
            function(v) ns.Engine.SetPack(pack, v) end)
    end
    y = y - math.ceil(#ns.packOrder / 4) * 21 - 10

    local function Button(label, x, width, fn)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("BOTTOMLEFT", x, 8)
        b:SetText(label)
        b:SetScript("OnClick", fn)
    end
    Button("Report a bug", 10, 110, function()
        UrlPopup("Bugs are fined at the standard rate.", ns.REPO .. "/issues/new?template=bug_report.yml")
        ns:Fire("BUG_REPORT")
    end)
    Button("Suggest a feat", 124, 110, function()
        UrlPopup("Submitters are credited in flavor text.", ns.REPO .. "/issues/new?template=suggest_a_feat.yml")
    end)
    Button("Changelog", 238, 100, function()
        for i = 1, #ns.CHANGELOG do ns.Print(ns.CHANGELOG[i]) end
        ns:Fire("CHANGELOG")
    end)
    Button("Reset character", 446, 124, function() StaticPopup_Show("FIFTYDKPMINUS_RESET") end)

    panel:SetScript("OnShow", function() changed = false end)
    panel:SetScript("OnHide", function() ns:Fire("SETTINGS_CLOSE", { changed = changed }) end)
end

---------------------------------------------------------------------------
-- Minimap button: left-click ledger, right-click quiet mode, drag to move.
---------------------------------------------------------------------------
local function Place(button)
    local angle = math.rad(ns.settings.minimapAngle or 215)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

ns.logins[#ns.logins + 1] = function()
    if not Minimap or ns.settings.minimapHide then return end
    local b = CreateFrame("Button", "FiftyDKPMinusMinimapButton", Minimap)
    b:SetSize(28, 28)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            SlashCmdList.FIFTYDKPMINUS("quiet")
        else
            ns.Ledger:Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            Place(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("50 DKP Minus")
        GameTooltip:AddLine(("%s DKP (%s)"):format(ns.BalanceText(ns.char.balance), ns.Rank(ns.char.balance)), 0.8, 0.13, 0.13)
        GameTooltip:AddLine("Account: " .. ns.BalanceText(ns.AccountTotal()), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Left-click: ledger. Right-click: quiet mode" .. (ns.settings.quiet and " (on)." or "."), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place(b)
end
