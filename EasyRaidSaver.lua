-- || Made by and for Weird Vibes of Turtle WoW || --

local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function ers_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00ERS:|r "..msg)
end

local function elem(t,item)
  for _,k in t do
    if item == k then
      return true
    end
  end
  return false
end

local function tsize(t)
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c
end

-- Addon ---------------------

-- /// Util functions /// --

local function PostHookFunction(original,hook)
  return function(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
    original(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
    hook(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
  end
end

local function InGroup()
  return (GetNumPartyMembers() + GetNumRaidMembers() > 0)
end

local function PlayerCanRaidMark()
  return InGroup() and (IsRaidOfficer() or IsPartyLeader())
end

-- You may mark when you're a lead, assist, or you're doing soloplay
local function PlayerCanMark()
  return PlayerCanRaidMark() or not InGroup()
end

------------------------------
-- Vars
------------------------------

local saved_raid = nil
shuffle_queue = {}
local EasyRaidSaver = CreateFrame("Frame","EasyRaidSaver")
local active_template = nil

local count_roster_updates = false
local updates = 0

local role = {
  ["Healer"] = true,
  ["Melee"] = true,
  ["Range"] = true,
  ["Tank"] = true,
}

local class = {
  ["Druid"] = true,
  ["Hunter"] = true,
  ["Mage"] = true,
  ["Paladin"] = true,
  ["Priest"] = true,
  ["Rogue"] = true,
  ["Shaman"] = true,
  ["Warrior"] = true,
  ["Warlock"] = true,
}

------------------------------
-- Table Functions
------------------------------

local function member(tbl, item)
  for _, value in ipairs(tbl) do
    -- if type(value) == "string" and type(item) == "string" then
    -- end
    if value == item then
        return true
    end
  end
  return false
end

------------------------------
-- Raid Functions
------------------------------

function MakeRaidConfiguration(config)
  local groups = {}
  for name,group in pairs(config) do
    if not groups[group] then groups[group] = {} end
    table.insert(groups[group], name)
    -- print(name  .. ">>".. group)
  end
  return groups
end

function StoreRaidConfiguration(name,config)
  local r = MakeRaidConfiguration(config)
  EasyRaidSaverDB.templates[name] = r
end

-- option to set assistants
-- option to auto-shift spriests around
-- option to autoswap dead melee out of shaman groups or swap a live shaman into dead spot
-- rabuffs option to show item totals for consumes
-- fr trinket
-- fr gun
-- default templates to order people by class to make optimal groups automatically
-- fuller ui allowing you to specify who is in raid by text but then edit it by dragging

local function StoredRaidConfigToTextRaw(name, temp)
  local config = temp
  local groups = {}
  
  for i=1,8 do
    -- order doens't actually matter comp-wise, sorting here is just for visual consistency
    if config[i] then table.sort(config[i]) end
    table.insert(groups, "Group "..i..": " .. (config[i] and table.concat(config[i], ", ") or ""))
  end

  local sum = "Layout Name: " .. name .. "\n\n" .. table.concat(groups,"\n")
  return sum
end

local function StoredRaidConfigToText(name)
  local config = EasyRaidSaverDB.templates[name]
  if not config then return end
  return StoredRaidConfigToTextRaw(name, config)
end

local function ToSimpleConfig(config)
  local temp = {}
  for i,group in pairs(config) do
    for _,member in pairs(group) do
      temp[member] = i
      -- print(member .. "<<" .. i)
    end
  end

  return temp
end

local function TextToBasicRaidConfig(text)
  if not text then return end

  local lower_text = string.lower(text)

  local s,e,template_name = string.find(lower_text,"layout%s*name%s*:%s*([%w _]+)\n*")
  if not s then return end
  -- grab the capitalized version
  local _,_,template_name = string.find(string.sub(text,s,e),":%s*([%w _]+)\n*")
  -- print("tn "..template_name)

  local rest = string.sub(lower_text,e)
  -- print(rest)
  local config = {}
  for gnum,members in string.gfind(rest,"[ ]*group%s*(%d+):([%w ,]+)") do
    -- print(gnum .. " _ ".. members)
    -- print("num:"..gnum)
    -- print("mem:"..members)
    if gnum ~= "" and members ~= "" then
      for member in string.gfind(members,"%s*(%w+)%s*[,]*%s*") do
        member = string.upper(string.sub(member,1,1)) .. string.lower(string.sub(member,2))
        -- print("member " .. member .. " : gnum " .. gnum)
        config[member] = tonumber(gnum)
      end
    end
  end

  -- local r = MakeRaidConfiguration(config)
  return config,template_name
end

function RandomizeRaid()
  local max = GetNumRaidMembers()
  for i=1,max do
    SwapRaidSubgroup(math.random(1,max),math.random(1,max))
  end
end

-- Function to find a member in a specific subgroup who is not in their desired subgroup
-- local function FindMisplacedMemberInSubgroup(subgroup, config, desiredConfig, excludeName)
--   for name, group in pairs(config) do
--     if group == subgroup and name ~= excludeName and desiredConfig[name] ~= subgroup then
--       -- print(name)
--       return name
--     end
--   end
--   return nil
-- end

-- check raid for names, kick dupers
function ERSRemoveDupes()
  local t = {}
  for i=1,GetNumRaidMembers() do
    local name = GetRaidRosterInfo(i)
    if t[name] then
      UninviteByName(name)
    else
      t[name] = true
    end
  end
end

local ROLE_MAP = {
  ["Tank"] = { "Warrior", "Paladin", "Druid" },
  ["Healer"] = { "Priest", "Paladin", "Druid", "Shaman" },
  ["Melee"] = { "Warrior", "Rogue", "Paladin" },
  ["Ranged"] = { "Hunter", "Mage", "Warlock" },
  ["Caster"] = { "Mage", "Warlock", "Priest" },
}

-- Function to get the current raid configuration
local function GetCurrentRaidConfiguration()
  local currentConfig = {}
  local raidUnits = {}
  local classes = {}
  local roles = {}
  for i = 1, GetNumRaidMembers() do
    local name, _, subgroup, _, class = GetRaidRosterInfo(i)
    currentConfig[name] = subgroup
    raidUnits[name] = i
    classes[name] = class
  end
  for role,classList in pairs(ROLE_MAP) do
    if member(classList, class) then
      roles[name] = role
      break
    end
  end
  return currentConfig, raidUnits, classes, roles
end

-- I want to allow this to sort people into a slot by role, how can I do this.
local function MoveDirectlyOrSwap(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
  local currentSubgroup = currentConfig[name]

  if currentSubgroup == desiredSubgroup then
    return true
  end

  if visited[name] then
    return false
  end
  visited[name] = true

  if subgroupCount[desiredSubgroup] and subgroupCount[desiredSubgroup] < 5 then
    SetRaidSubgroup(raidUnits[name], desiredSubgroup)
    subgroupCount[currentSubgroup] = subgroupCount[currentSubgroup] - 1
    subgroupCount[desiredSubgroup] = subgroupCount[desiredSubgroup] + 1
    currentConfig[name] = desiredSubgroup
    return true
  else
    -- Find a member in the desired subgroup that is out of place
    for tempName, tempSubgroup in pairs(currentConfig) do
      if tempSubgroup == desiredSubgroup and desiredConfig[tempName] ~= desiredSubgroup then
        -- Swap the members
        print(raidUnits[name])
        print(raidUnits[tempName])
        SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
        currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
        return MoveDirectlyOrSwap(tempName, desiredConfig[tempName], currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
      end
    end
  end
  
  return false
end



-- local function ConfigureRaid(desiredConfig)
  -- local currentConfig, raidUnits, classes, roles = GetCurrentRaidConfiguration()
  -- local subgroupCount = {}

  -- -- TODO problem, this treats current config as desired, which isn't actually correct since it gives slots to people that shouldn't have them
  -- -- copy desired config, prune missing names, add new names
  -- local tempDes = {}
  -- for name, _ in pairs(desiredConfig) do
  --     if currentConfig[name] then
  --         tempDes[name] = desiredConfig[name]
  --     end
  -- end
  -- -- track raid members who are not in the config
  -- local extras = {}
  -- for name, id in pairs(currentConfig) do
  --   if not desiredConfig[name] then
  --     extras[name] = id
  --   end
  -- end

  -- -- for name, _ in pairs(currentConfig) do
  -- --     if not desiredConfig[name] then
  -- --         tempDes[name] = currentConfig[name]
  -- --     end
  -- -- end

  -- for i = 1, 8 do
  --   subgroupCount[i] = 0
  -- end

  -- for _, subgroup in pairs(currentConfig) do
  --   subgroupCount[subgroup] = subgroupCount[subgroup] + 1
  -- end

  -- -- First pass: Move as many members directly as possible
  -- local queue = {}
  -- local queue_c = 0
  -- for name, desiredSubgroup in pairs(tempDes) do
  --   table.insert(queue, {name = name, desiredSubgroup = desiredSubgroup})
  --   queue_c = queue_c + 1
  -- end

  -- -- First Pass: Exact Name Placement
  -- for name, desiredSubgroup in pairs(desiredConfig) do
  --   if type(desiredSubgroup) == "number" and currentConfig[name] ~= desiredSubgroup then
  --       local visited = {}
  --       MoveDirectlyOrSwap(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
  --   end
  -- end

  -- -- Second Pass: Class and Role Placement
  -- for name, desiredSubgroup in pairs(desiredConfig) do
  --     if type(desiredSubgroup) ~= "number" then
  --         for memberName, memberSubgroup in pairs(currentConfig) do
  --             if desiredSubgroup == classes[memberName] or desiredSubgroup == roles[memberName] then
  --                 local visited = {}
  --                 MoveDirectlyOrSwap(memberName, currentConfig[name], currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
  --             end
  --         end
  --     end
  -- end

  -- while queue_c > 0 do
  --   local moved = false
  --   local remainingQueue = {}
  --   local remainingQueue_c = 0

  --   for _, entry in ipairs(queue) do
  --     local name = entry.name
  --     local desiredSubgroup = entry.desiredSubgroup
  --     local visited = {}

  --     if not MoveDirectlyOrSwap(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, tempDes, visited) then
  --       table.insert(remainingQueue, entry)
  --       remainingQueue_c = remainingQueue_c + 1
  --     else
  --       moved = true
  --     end
  --   end

  --   if not moved then
  --     -- No progress was made; perform a forced swap to break the deadlock
  --     local entry = table.remove(remainingQueue, 1)
  --     remainingQueue_c = remainingQueue_c - 1
  --     local name = entry.name
  --     local desiredSubgroup = entry.desiredSubgroup
  --     local visited = {}

  --     -- Force a swap with any member in the desired subgroup
  --     for tempName, tempSubgroup in pairs(currentConfig) do
  --       if tempSubgroup == desiredSubgroup then
  --         SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
  --         currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
  --         break
  --       end
  --     end
  --   end

  --   queue = remainingQueue
  --   queue_c = remainingQueue_c
  -- end
-- end

-- local function CountTableElements(tbl)
--   local count = 0
--   for _ in pairs(tbl) do
--       count = count + 1
--   end
--   return count
-- end

-- local function ConfigureRaid(desiredConfig)
--   local function RefreshAndValidateConfig()
--       local currentConfig, raidUnits, classes, roles = GetCurrentRaidConfiguration()
--       local validDesiredConfig = {}

--       -- Validate and adjust desired configuration to remove any members who are no longer in the raid
--       for desiredSubgroup, members in pairs(desiredConfig) do
--           validDesiredConfig[desiredSubgroup] = {}
--           for i, member in pairs(members) do
--               if raidUnits[member] or classes[member] or roles[member] then
--                   table.insert(validDesiredConfig[desiredSubgroup], member)
--               end
--           end
--       end

--       return currentConfig, raidUnits, classes, roles, validDesiredConfig
--   end

--   local currentConfig, raidUnits, classes, roles, validDesiredConfig = RefreshAndValidateConfig()
--   local subgroupCount = {}

--   -- Initialize subgroup counts
--   for i = 1, 8 do
--       subgroupCount[i] = 0
--   end

--   for _, subgroup in pairs(currentConfig) do
--       subgroupCount[subgroup] = subgroupCount[subgroup] + 1
--   end

--   -- First Pass: Exact Name Placement
--   for desiredSubgroup, members in pairs(validDesiredConfig) do
--       for i, member in pairs(members) do
--           if currentConfig[member] and currentConfig[member] ~= desiredSubgroup then
--               local visited = {}
--               MoveDirectlyOrSwap(member, desiredSubgroup, currentConfig, raidUnits, subgroupCount, validDesiredConfig, visited)
--           end
--       end
--   end

--   -- Second Pass: Class and Role Placement
--   for desiredSubgroup, members in pairs(validDesiredConfig) do
--       for i, member in pairs(members) do
--           if not raidUnits[member] then  -- Ensure it's not a specific player already placed
--               for memberName, memberSubgroup in pairs(currentConfig) do
--                   if (member == classes[memberName] or member == roles[memberName]) and not validDesiredConfig[memberSubgroup][memberName] then
--                       local visited = {}
--                       MoveDirectlyOrSwap(memberName, desiredSubgroup, currentConfig, raidUnits, subgroupCount, validDesiredConfig, visited)
--                   end
--               end
--           end
--       end
--   end

--   -- Handle any remaining members by forced swaps if necessary
--   local queue = {}
--   local queueSize = 0
--   for desiredSubgroup, members in pairs(validDesiredConfig) do
--       for i, member in pairs(members) do
--           if currentConfig[member] ~= desiredSubgroup and raidUnits[member] then  -- Ensure member is a real player
--               queueSize = queueSize + 1
--               queue[queueSize] = {name = member, desiredSubgroup = desiredSubgroup}
--           end
--       end
--   end

--   -- Process the queue until empty
--   while queueSize > 0 do
--       local entry = table.remove(queue, 1)
--       queueSize = queueSize - 1
--       local name = entry.name
--       local desiredSubgroup = entry.desiredSubgroup

--       -- Refresh and validate again before final processing
--       currentConfig, raidUnits, classes, roles, validDesiredConfig = RefreshAndValidateConfig()

--       -- Ensure the name is a valid raid member before attempting a swap
--       if raidUnits[name] then
--           -- Force a swap with any member in the desired subgroup
--           for tempName, tempSubgroup in pairs(currentConfig) do
--               if tempSubgroup == desiredSubgroup and raidUnits[tempName] then
--                   SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
--                   currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
--                   break
--               end
--           end
--       end
--   end
-- end

local function ConfigureRaid(desiredConfig)
  local function RefreshAndValidateConfig()
    local currentConfig, raidUnits, classes, roles = GetCurrentRaidConfiguration()
    local validDesiredConfig = {}

    -- Validate and adjust desired configuration to remove any members who are no longer in the raid
    for desiredSubgroup, members in pairs(desiredConfig) do
      validDesiredConfig[desiredSubgroup] = {}
      for i, member in pairs(members) do
        if raidUnits[member] or classes[member] or roles[member] then
          table.insert(validDesiredConfig[desiredSubgroup], member)
        end
      end
    end

    return currentConfig, raidUnits, classes, roles, validDesiredConfig
  end

  local function MoveDirectlyOrSwap(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
    local currentSubgroup = currentConfig[name]

    if currentSubgroup == desiredSubgroup then
      return true
    end

    if visited[name] then
      return false
    end
    visited[name] = true

    if subgroupCount[desiredSubgroup] and subgroupCount[desiredSubgroup] < 5 then
      -- Move directly if there is space
      SetRaidSubgroup(raidUnits[name], desiredSubgroup)
      subgroupCount[currentSubgroup] = subgroupCount[currentSubgroup] - 1
      subgroupCount[desiredSubgroup] = subgroupCount[desiredSubgroup] + 1
      currentConfig[name] = desiredSubgroup
      return true
    else
      -- Attempt to swap with a member that isn't supposed to be in the desired subgroup
      for tempName, tempSubgroup in pairs(currentConfig) do
        if tempSubgroup == desiredSubgroup and desiredConfig[tempSubgroup] and not member(desiredConfig[tempSubgroup], tempName) then
          -- Swap the members
          SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
          currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
          return MoveDirectlyOrSwap(tempName, desiredConfig[tempSubgroup][1], currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
        end
      end
    end

    return false
  end

  local currentConfig, raidUnits, classes, roles, validDesiredConfig = RefreshAndValidateConfig()
  local subgroupCount = {}

  -- Initialize subgroup counts
  for i = 1, 8 do
    subgroupCount[i] = 0
  end

  for _, subgroup in pairs(currentConfig) do
    subgroupCount[subgroup] = subgroupCount[subgroup] + 1
  end

  -- First Pass: Exact Name Placement
  for desiredSubgroup, members in pairs(validDesiredConfig) do
    for i, member in pairs(members) do
      if currentConfig[member] and currentConfig[member] ~= desiredSubgroup then
        local visited = {}
        MoveDirectlyOrSwap(member, desiredSubgroup, currentConfig, raidUnits, subgroupCount, validDesiredConfig, visited)
      end
    end
  end

  -- Second Pass: Class and Role Placement
  for desiredSubgroup, members in pairs(validDesiredConfig) do
    for i, member in pairs(members) do
      if not raidUnits[member] then  -- Ensure it's not a specific player already placed
        for memberName, memberSubgroup in pairs(currentConfig) do
          if (member == classes[memberName] or member == roles[memberName]) and not member(validDesiredConfig[memberSubgroup], memberName) then
            local visited = {}
            MoveDirectlyOrSwap(memberName, desiredSubgroup, currentConfig, raidUnits, subgroupCount, validDesiredConfig, visited)
          end
        end
      end
    end
  end

  -- Handle any remaining members by forced swaps if necessary
  local queue = {}
  -- EasyRaidSaver.queue = {}
  local queueSize = 0
  for desiredSubgroup, members in pairs(validDesiredConfig) do
    for i, member in pairs(members) do
      if currentConfig[member] ~= desiredSubgroup and raidUnits[member] then  -- Ensure member is a real player
        queueSize = queueSize + 1
        queue[queueSize] = {name = member, desiredSubgroup = desiredSubgroup}
        EasyRaidSaver.queue[queueSize] = {name = member, desiredSubgroup = desiredSubgroup}
      end
    end
  end

  -- Process the queue until empty
  while queueSize > 0 do
    local entry = table.remove(queue, 1)
    queueSize = queueSize - 1
    local name = entry.name
    local desiredSubgroup = entry.desiredSubgroup

    -- Refresh and validate again before final processing
    currentConfig, raidUnits, classes, roles, validDesiredConfig = RefreshAndValidateConfig()

    -- Ensure the name is a valid raid member before attempting a swap
    if raidUnits[name] then
      -- Force a swap with any member in the desired subgroup
      for tempName, tempSubgroup in pairs(currentConfig) do
        if tempSubgroup == desiredSubgroup and raidUnits[tempName] then
          SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
          currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
          break
        end
      end
    end
  end
end

local function DidRaidMatch(first,second)
  for name,subgroup in pairs(first) do
    -- print("f "..first[name] .. " ".. name)
    -- print("s "..second[name].. " ".. name)
    if second[name] and (first[name] ~= second[name]) then
        DEFAULT_CHAT_FRAME:AddMessage(name .. " not matched")
        return false
      end
  end
  DEFAULT_CHAT_FRAME:AddMessage("matched")
  return true
end

------------------------------
-- UI
------------------------------

local function SetCheckboxGreyed(checkbox, greyed)
  if greyed then
    -- Make the checkbox appear greyed out
    checkbox:GetCheckedTexture():SetVertexColor(0.3, 0.3, 0.3)
  else
    -- Restore the checkbox's normal colors
    checkbox:GetCheckedTexture():SetVertexColor(1, 1, 1)
  end
end

-- Define a function to create the buttons
local function CreateRaidButtons()
  local AddButton = getglobal("RaidFrameAddMemberButton")
  AddButton:SetText("Add")
  AddButton:SetWidth(35)

  local ReadyButton = getglobal("RaidFrameReadyCheckButton")
  ReadyButton:SetText("Ready")
  ReadyButton:SetPoint("LEFT", AddButton,"RIGHT", 0, 0)
  ReadyButton:SetWidth(35)

  -- Create the Save Raid button
  local SaveRaidButton = CreateFrame("Button", "SaveRaidButton", AddButton, "UIPanelButtonTemplate")
  SaveRaidButton:SetWidth(35) -- Width, Height
  SaveRaidButton:SetHeight(22) -- Width, Height
  SaveRaidButton:SetPoint("LEFT", AddButton, "RIGHT", 35, 0) -- Position relative to RaidFrame
  SaveRaidButton:SetText("Save")
  SaveRaidButton:SetScript("OnClick", function()
      ERS_SaveRaid()
  end)
  -- Add a script to handle showing the tooltip
  SaveRaidButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Quick-Save Current Raid", 1, 1, 0)  -- Tooltip title
    GameTooltip:AddLine("Save the current raid to the quick-save slot", 1, 1, 1, true)  -- Tooltip description
    GameTooltip:Show()
  end)

  -- Add a script to handle hiding the tooltip
  SaveRaidButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- Create the Restore Raid button
  local RestoreRaidButton = CreateFrame("Button", "RestoreRaidButton", RaidFrame, "UIPanelButtonTemplate")
  RestoreRaidButton:SetWidth(35) -- Width, Height
  RestoreRaidButton:SetHeight(22) -- Width, Height
  RestoreRaidButton:SetPoint("LEFT", SaveRaidButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
  RestoreRaidButton:SetText("Load")
  RestoreRaidButton:SetScript("OnClick", function()
      ERS_RestoreRaid()
  end)
  -- Add a script to handle showing the tooltip
  RestoreRaidButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Quick-Load Raid", 1, 1, 0)  -- Tooltip title
    GameTooltip:AddLine("Load the last quick-saved raid", 1, 1, 1, true)  -- Tooltip description
    GameTooltip:Show()
  end)

  -- Add a script to handle hiding the tooltip
  RestoreRaidButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local InfoButton = getglobal("RaidFrameRaidInfoButton")
  InfoButton:SetText("Info")
  InfoButton:SetPoint("LEFT", RestoreRaidButton,"RIGHT", 0, 0)
  InfoButton.orig_width = InfoButton:GetWidth()
  InfoButton:SetWidth(35) -- Width, Height

  local f = InfoButton:GetScript("OnClick")
  InfoButton:SetScript("OnClick", function (a1,a2,a3,a4,a5,a6,a7,a8,a9)
    f(a1,a2,a3,a4,a5,a6,a7,a8,a9)
    if ESRConfigFrame:IsShown() then ESRConfigFrameButton:Click() end
  end)

  local function CreateConfigArea()

    local ConfigFrame = CreateFrame("Frame","ESRConfigFrame",RaidFrame)

    -- Create the button frame
    local rightArrowButton = CreateFrame("Button", "ESRConfigFrameButton", RaidFrame, "UIPanelButtonTemplate")
    rightArrowButton:SetWidth(24)  -- Width, Height
    rightArrowButton:SetHeight(24)  -- Width, Height
    rightArrowButton:SetPoint("TOPLEFT", RaidFrame, "TOPRIGHT",-30, -10)
    -- Add a script to handle showing the tooltip
    rightArrowButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      -- GameTooltip:SetText("Quick-Load Raid", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("Show/Hide the raid Layout Editor", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
    end)

    -- Add a script to handle hiding the tooltip
    rightArrowButton:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Create the arrow texture
    local arrowTextureUp = rightArrowButton:CreateTexture(nil, "ARTWORK")
    arrowTextureUp:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")  -- Path to the right arrow texture
    arrowTextureUp:SetAllPoints(rightArrowButton)  -- Make the texture fill the entire button

    local arrowTextureDown = rightArrowButton:CreateTexture(nil, "ARTWORK")
    arrowTextureDown:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")  -- Path to the right arrow texture
    arrowTextureDown:SetAllPoints(rightArrowButton)  -- Make the texture fill the entire button

    -- Set the normal and pushed textures for the button
    rightArrowButton:SetNormalTexture(arrowTextureUp)
    rightArrowButton:SetPushedTexture(arrowTextureDown)

    -- Add a script to handle the button click
    rightArrowButton:SetScript("OnClick", function()
      if ConfigFrame:IsShown() then
        ConfigFrame:Hide()
      else
        ConfigFrame:Show()
      end
    end)

    -- Show the button
    rightArrowButton:Show()
    ConfigFrame:SetPoint("TOPLEFT", rightArrowButton,"TOPRIGHT", 0, 0)

      
    local EditBox = CreateFrame("EditBox","ERSEditBox",ConfigFrame)
    EditBox:SetMultiLine(true)
    EditBox:SetAutoFocus(false) -- Prevent the box from auto-focusing
    EditBox:SetFontObject(GameFontNormal)
    EditBox:SetWidth(380)
    EditBox:SetHeight(140) -- Set a large height to enable scrolling
    EditBox:SetText("Raid Layout")
    EditBox:SetPoint("LEFT", RaidFrame,"RIGHT", 0, 150)
    EditBox:Hide()

    -- Add a background to the frame
    local bg = EditBox:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("LEFT", EditBox,"LEFT", 0, 0)
    bg:SetWidth(EditBox:GetWidth())
    bg:SetHeight(EditBox:GetHeight())
    bg:SetTexture(0, 0, 0, 0.7) -- Black background with some transparency

    EditBox:SetScript("OnEscapePressed", function ()
      this:ClearFocus()
    end)

    -- OnTextChanged
    -- EditBox:SetScript("OnChar", function ()
    --   local char = arg1
    --   if char == "%" then char = "%%" end
    --   local allowed = "[A-Za-z _:0-9,]"
    --   if not string.find(char,allowed) then
    --     -- remove last entered char
    --     local text = this:GetText()
    --     -- local len = string.len(text)
    --     -- this:SetText(string.sub(text,1,len-1))
    --     this:SetText(string.gsub(text,"(["..char.."])",""))
    --   end
    -- end)

    local MyDropdown = CreateFrame("Frame", "MyDropdownMenu", ConfigFrame, "UIDropDownMenuTemplate")
    MyDropdown:SetPoint("TOPLEFT", RaidFrame,"TOPRIGHT", -17, -7)
    UIDropDownMenu_SetText("Select a Layout", MyDropdown)
    UIDropDownMenu_SetWidth(170,MyDropdown)

    MyDropdown:SetScript("OnShow", function ()
      local selection = UIDropDownMenu_GetSelectedName(MyDropdown)
      if selection then
        -- run selection function?
        EditBox:Show()
      end
    end)

    getglobal("MyDropdownMenuButton"):SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Layout Selection", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("White: player-made templates", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:AddLine("Green: current Applied template", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
    end)

    getglobal("MyDropdownMenuButton"):SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- local function MyDropdown_OnClick()
    --   UIDropDownMenu_SetSelectedValue(MyDropdown, this.value)
    --   print("Selected option: " .. this.value)
    -- end

    local function MyDropdown_Initialize(level)

      for k,_ in pairs(EasyRaidSaverDB.templates) do
        local name = k
        local info = {}
        info.text = name
        if EasyRaidSaverDB.settings.active_template == name then
          info.textR = 0.1
          info.textG = 0.8
          info.textB = 0.1
        end
        info.func = function ()
          local conf = StoredRaidConfigToText(name)
          if conf then
            EditBox:SetText(conf)
            UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
            EasyRaidSaverDB.settings.last_template_selection = this:GetText()
            EditBox:Show()
          end
        end
        -- info.hasArrow = (UIDropDownMenu_GetSelectedName(MyDropdown) == info.text) and 1 or nil
        UIDropDownMenu_AddButton(info, level)
      end

      local info = {}
      info.text = "Current Quick-Saved Raid"
      info.textR = 1 -- yellow
      info.textG = 1 -- yellow
      info.textB = 0 -- yellow
      info.func = function ()
        if EasyRaidSaverDB.saved_raid then
          local config = MakeRaidConfiguration(EasyRaidSaverDB.saved_raid)
          EditBox:SetText(StoredRaidConfigToTextRaw("last_raid_quicksave", config))
          UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
          EditBox:Show()
        end
      end
      UIDropDownMenu_AddButton(info, level)

      local info = {}
      info.text = "Shaman For Melee"
      info.textR = 0.14 -- yellow
      info.textG = 0.35 -- yellow
      info.textB = 1.0 -- yellow
      info.func = function ()
        -- organize shamans and melee here
        print("this layout template doesn't do anything yet")
      end
      UIDropDownMenu_AddButton(info, level)

      local info = {}
      info.text = "New Layout"
      -- info.value = "New Template"
      info.textR = 1 -- yellow
      info.textG = 1 -- yellow
      info.textB = 0 -- yellow
      info.func = function ()
        local config = MakeRaidConfiguration(GetCurrentRaidConfiguration())
        EditBox:SetText(StoredRaidConfigToTextRaw("new layout", config))
        UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
        EditBox:Show()
      end
      UIDropDownMenu_AddButton(info, level)
      -- EasyRaidSaverDB.settings.last_templte = UIDropDownMenu_GetSelectedValue(MyDropdown)
    end

    UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
    if EasyRaidSaverDB.settings.last_template_selection then
      UIDropDownMenu_SetSelectedName(MyDropdown, EasyRaidSaverDB.settings.last_template_selection)
      -- ^ how do I run this func
    end

    -- Create the Save Raid button
    local SaveTemplateButton = CreateFrame("Button", "SaveTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
    SaveTemplateButton:SetWidth(35) -- Width, Height
    SaveTemplateButton:SetHeight(22) -- Width, Height
    SaveTemplateButton:SetPoint("LEFT", MyDropdown, "RIGHT", -10, 3) -- Position relative to RaidFrame
    SaveTemplateButton:SetText("Save")
    SaveTemplateButton:SetScript("OnClick", function()
      local conf,name = TextToBasicRaidConfig(EditBox:GetText())

      if conf then
        StoreRaidConfiguration(name, conf)
        UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
        UIDropDownMenu_SetSelectedName(MyDropdown, name)
        ers_print("Saving layout: " .. name)
      end
    end)

    -- Create the Restore Raid button
    local DeleteTemplateButton = CreateFrame("Button", "DeleteTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
    DeleteTemplateButton:SetWidth(35) -- Width, Height
    DeleteTemplateButton:SetHeight(22) -- Width, Height
    DeleteTemplateButton:SetPoint("BOTTOMLEFT", SaveTemplateButton, "TOPLEFT", 0, 0) -- Position relative to RaidFrame
    DeleteTemplateButton:SetText("Delete")
    DeleteTemplateButton:SetScript("OnClick", function()
      local name = UIDropDownMenu_GetSelectedName(MyDropdown)
      local ix = UIDropDownMenu_GetSelectedID(MyDropdown)
      if EasyRaidSaverDB.templates[name] then
        EasyRaidSaverDB.templates[name] = nil
        ers_print("Deleted layout: " .. name)
        UIDropDownMenu_Initialize(MyDropdown, MyDropdown_Initialize)
        -- UIDropDownMenu_SetSelectedID(MyDropdown,ix-1)
      end
    end)
    -- Add a script to handle showing the tooltip
    DeleteTemplateButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Delete Current Layout", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("This operation will not ask for confirmation", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
      -- TODO: Make it ask for confirmation
    end)

    -- Add a script to handle hiding the tooltip
    DeleteTemplateButton:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- Create the Restore Raid button
    local ApplyTemplateButton = CreateFrame("Button", "ApplyTemplateButton", ConfigFrame, "UIPanelButtonTemplate")
    ApplyTemplateButton:SetWidth(42) -- Width, Height
    ApplyTemplateButton:SetHeight(22) -- Width, Height
    ApplyTemplateButton:SetPoint("LEFT", SaveTemplateButton, "RIGHT", 0, 0) -- Position relative to RaidFrame
    ApplyTemplateButton:SetText("Apply")
    ApplyTemplateButton:SetScript("OnClick", function()
      local name = UIDropDownMenu_GetSelectedName(MyDropdown)
      if EasyRaidSaverDB.templates[name] then
        local simple = ToSimpleConfig(EasyRaidSaverDB.templates[name])
        -- ConfigureRaid(simple)
        ConfigureRaid(EasyRaidSaverDB.templates[name])
        -- ConfigureRaid(EasyRaidSaverDB.templates[name])
        ers_print("Applying layout: " .. name)
        count_roster_updates = true
        if DEBUG then
          ERSRemoveDupes()
          if DidRaidMatch(simple,GetCurrentRaidConfiguration()) then
            print(updates)
            count_roster_updates = false
          end
        end
        EasyRaidSaverDB.settings.active_template = name
        SetCheckboxGreyed(ERSLiveToggle,not EasyRaidSaverDB.settings.active_template)
      end
    end)
    -- Add a script to handle showing the tooltip
    ApplyTemplateButton:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Apply Layout", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("Apply the current Layout, re-organising the raid to match", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
    end)

    -- Add a script to handle hiding the tooltip
    ApplyTemplateButton:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    -- highlight the last template set to _active_

    local LiveToggle = CreateFrame("CheckButton", "ERSLiveToggle", ConfigFrame, "UICheckButtonTemplate")
    LiveToggle:SetWidth(24)
    LiveToggle:SetHeight(24)
    LiveToggle:SetPoint("LEFT", ApplyTemplateButton, "RIGHT", 0, 0)
    -- LiveToggle.tooltipText = "Toggle Live Apply"
    -- LiveToggle.tooltipRequirement = "Apply the current layout as people join the raid"
    LiveToggle:SetChecked(EasyRaidSaverDB.settings.live_checked)

    LiveToggle:SetScript("OnClick", function ()
      EasyRaidSaverDB.settings.live_checked = this:GetChecked() and true or false
      SetCheckboxGreyed(this,not EasyRaidSaverDB.settings.active_template)
    end)

    -- Add a script to handle showing the tooltip
    LiveToggle:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Toggle Live Apply", 1, 1, 0)  -- Tooltip title
      GameTooltip:AddLine("Re-apply the Applied layout as people join the raid", 1, 1, 1, true)  -- Tooltip description
      GameTooltip:Show()
    end)

    -- Add a script to handle hiding the tooltip
    LiveToggle:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

  end
  CreateConfigArea()
end

local function UpdateInfoButton()
  if GetNumRaidMembers() > 0 then
    RaidFrameRaidInfoButton:SetText("Info")
    RaidFrameRaidInfoButton:SetWidth(35)
    RaidFrameRaidInfoButton:SetPoint("LEFT", RestoreRaidButton,"RIGHT", 0, 0)
  else
    RaidFrameRaidInfoButton:SetPoint("LEFT", RaidFrameConvertToRaidButton,"RIGHT", 65, 0)
    RaidFrameRaidInfoButton:SetText(RAID_INFO)
    RaidFrameRaidInfoButton:SetWidth(RaidFrameRaidInfoButton.orig_width)
  end
end

-- Function to update the button states based on raid status
local function UpdateButtonStates()
  if GetNumRaidMembers() > 0 then
    SaveRaidButton:Show()
    RestoreRaidButton:Show()
    if IsRaidOfficer() then
      ApplyTemplateButton:Enable()
    else
      ApplyTemplateButton:Disable()
    end

    ESRConfigFrame:Show()

    if EasyRaidSaverDB.saved_raid and IsRaidOfficer() then
      RestoreRaidButton:Enable()
    else
      RestoreRaidButton:Disable()
    end
  else
    SaveRaidButton:Hide()
    RestoreRaidButton:Hide()
    ApplyTemplateButton:Disable()

    ESRConfigFrame:Hide()
  end
  UpdateInfoButton()
end

-- Function to save the raid setup
function ERS_SaveRaid()
  ers_print("Quick-saving current raid layout.")
  saved_raid = GetCurrentRaidConfiguration()
  EasyRaidSaverDB.saved_raid = saved_raid

  UpdateButtonStates()
end

function ERS_RestoreRaid()
  ers_print("Quick-loading saved raid layout.")
  if EasyRaidSaverDB.saved_raid then
    ConfigureRaid(EasyRaidSaverDB.saved_raid)
  end
end

local function Matches()
  DidRaidMatch(GetCurrentRaidConfiguration(),saved_raid)
end

-- Register the ADDON_LOADED event
EasyRaidSaver:RegisterEvent("ADDON_LOADED")
EasyRaidSaver:SetScript("OnEvent", function ()
  EasyRaidSaver[event](arg1,arg2,arg3,arg4,arg6,arg7,arg8,arg9,arg9,arg10)
end)

function EasyRaidSaver:Load()
  EasyRaidSaverDB = EasyRaidSaverDB or {}
  EasyRaidSaverDB.settings = EasyRaidSaverDB.settings or {}
  EasyRaidSaverDB.templates = EasyRaidSaverDB.templates or {}

  CreateRaidButtons()

  local rgfu = RaidGroupFrame_Update
  ERS_RaidGroupFrame_Update = function ()
    rgfu()
    UpdateInfoButton()
  end
  RaidGroupFrame_Update = ERS_RaidGroupFrame_Update

  local rgonshow = RaidFrame:GetScript("OnShow")
  RaidFrame:SetScript("OnShow", function ()
    if rgonshow then rgonshow() end
    UpdateButtonStates()
  end)

  UpdateButtonStates()
end

function EasyRaidSaver.ADDON_LOADED(addon)
  if addon ~= "EasyRaidSaver" then return end
  EasyRaidSaver:Load()
  EasyRaidSaver:RegisterEvent("RAID_ROSTER_UPDATE")
  EasyRaidSaver:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function EasyRaidSaver.PLAYER_ENTERING_WORLD(addon)
  UpdateButtonStates()
end

local last_count = GetNumRaidMembers()
function EasyRaidSaver.RAID_ROSTER_UPDATE(addon)

  if next() then
  end

  if count_roster_updates then updates = updates + 1 end
  UpdateButtonStates()
  local current_count = GetNumRaidMembers()
  if current_count == 0 then
    -- raid over
    EasyRaidSaverDB.settings.active_template = nil
  end
  if current_count > 0 and last_count ~= current_count then
    -- print("count change")
    last_count = current_count
    -- print("live "..(EasyRaidSaverDB.settings.live_checked and "y" or "n"))
    -- print("temp "..EasyRaidSaverDB.settings.active_template)
    if EasyRaidSaverDB.settings.live_checked and EasyRaidSaverDB.settings.active_template and EasyRaidSaverDB.templates[EasyRaidSaverDB.settings.active_template] then
      -- print("waf")
      ConfigureRaid(ToSimpleConfig(EasyRaidSaverDB.templates[EasyRaidSaverDB.settings.active_template]))
    end
  end
end
