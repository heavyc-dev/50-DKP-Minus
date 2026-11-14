-- Toast: slides in top-centre with a red stamp, the feat name, the fine and one
-- line of flavor. Uses a stock raid-warning sound; no bundled audio.
local _, ns = ...
local T = {}
ns.Toast = T

local INK, RED = { 0.20, 0.12, 0.05 }, { 0.72, 0.05, 0.05 }
local frame, queue, busy = nil, {}, false

local function Build()
    frame = CreateFrame("Frame", "FiftyDKPMinusToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(380, 86)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -150)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
            edgeSize = 20, insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        frame:SetBackdropColor(0.91, 0.85, 0.69, 0.97)      -- parchment
    end

    frame.stamp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.stamp:SetPoint("LEFT", 16, 0)
    frame.stamp:SetTextColor(RED[1], RED[2], RED[3], 0.85)
    frame.stamp:SetText("FINED")
    if frame.stamp.SetRotation then frame.stamp:SetRotation(math.rad(14)) end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 112, -14)
    frame.title:SetPoint("RIGHT", -92, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.title:SetTextColor(INK[1], INK[2], INK[3])

    frame.flavor = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.flavor:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.flavor:SetPoint("RIGHT", -14, 0)
    frame.flavor:SetJustifyH("LEFT")
    frame.flavor:SetTextColor(INK[1], INK[2], INK[3])

    frame.fine = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.fine:SetPoint("TOPRIGHT", -14, -12)
    frame.fine:SetTextColor(RED[1], RED[2], RED[3])

    local show = frame:CreateAnimationGroup()
    local slide = show:CreateAnimation("Translation")
    slide:SetOffset(0, -40); slide:SetDuration(0.3); slide:SetSmoothing("OUT")
    local fadeIn = show:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.3)
    local fadeOut = show:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1); fadeOut:SetToAlpha(0); fadeOut:SetDuration(0.6); fadeOut:SetStartDelay(4.8)
    fadeOut:SetOrder(2)
    show:SetScript("OnFinished", function()
        frame:Hide()
        busy = false
        T.Next()
    end)
    frame.show = show

    -- One shake, for the really bad ones.
    local shake = frame:CreateAnimationGroup()
    for i, dx in ipairs({ 12, -24, 20, -14, 6 }) do
        local a = shake:CreateAnimation("Translation")
        a:SetOffset(dx, 0); a:SetDuration(0.05); a:SetOrder(i)
    end
    frame.shake = shake
end

function T.Next()
    if busy or #queue == 0 then return end
    if not frame then Build() end
    local item = table.remove(queue, 1)
    busy = true
    local big = math.abs(item.fine) >= 500
    frame:SetScale(big and 1.3 or 1)
    frame.title:SetText(item.name)
    frame.fine:SetText(ns.FineText(item.fine))
    frame.flavor:SetText(big and "Removed from guild (not really)." or (item.flavor or ""))
    frame.stamp:SetText(item.fine < 0 and "PAID" or "FINED")
    frame:Show()
    frame.show:Stop()
    frame.show:Play()
    if big then frame.shake:Play() end
    if ns.settings.sound and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

function T:Show(f, tier, name, fine)
    if not ns.settings.toast then return end
    if #queue >= 6 then return end      -- a burst of fines should not hold the screen hostage
    queue[#queue + 1] = { name = name, fine = fine, flavor = f.flavor }
    T.Next()
end
