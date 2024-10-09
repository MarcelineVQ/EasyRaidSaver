-- || Made by and for Weird Vibes of Turtle WoW || --

local function print(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local function ers_print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00ERS:|r "..msg)
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

local roleEnum = {
  ["Melee"] = true,
  ["Healer"] = true,
  ["Tank"] = true,
  ["Range"] = true,
  ["Decurse"] = true,
}

local classEnum = {
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

local roleMap = {
  ["Melee"] = { "Warrior", "Rogue", "Paladin", "Druid" },
  ["Healer"] = { "Priest", "Paladin", "Druid", "Shaman" },
  ["Range"] = { "Hunter", "Mage", "Warlock", "Priest", "Druid", "Shaman" },
  -- ["Tank"] = { "Warrior", "Paladin", "Druid" }, -- I don't really want a _tank_ role, just assign them specifically
  ["Decurse"] = { "Mage", "Druid" },
  -- ["Caster"] = { "Mage", "Warlock", "Priest", "Druid", "Shaman" },
}

local revRoleMap = {}
for role,classes in pairs(roleMap) do
  for _,class in ipairs(classes) do
    revRoleMap[class] = revRoleMap[class] or {}
    table.insert(revRoleMap[class], role)
  end
end

-- TODO make a reverse rolemap that maps classes to roles too, use this in prio layout

------------------------------
-- Table Functions
------------------------------

local function elem(t,item)
  for _,k in pairs(t) do
    if item == k then
      return true
    end
  end
  return false
end

local function key(t,key)
  for k,_ in pairs(t) do
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

function deepcopy(original)
  local copy = {}
  for k, v in pairs(original) do
      if type(v) == "table" then
          copy[k] = deepcopy(v)  -- Recursively copy nested tables
      else
          copy[k] = v
      end
  end
  return copy
end

local function Capitalize(str)
  return (string.upper(string.sub(str,1,1)) .. string.lower(string.sub(str,2)))
end

------------------------------
-- Raid Functions
------------------------------

function MakeRaidLayout(config)
  local groups = {}
  for name,group in pairs(config) do
    if not groups[group] then groups[group] = {} end
    table.insert(groups[group], { name })
  end
  return groups
end

-- option to set assistants
-- option to auto-shift spriests around
-- option to autoswap dead melee out of shaman groups or swap a live shaman into dead spot
-- default templates to order people by class to make optimal groups automatically
-- fuller ui allowing you to specify who is in raid by text but then edit it by dragging

local function RaidLayoutToText(name, layout)
  local groups = {}

  for group,slots in ipairs(layout) do
    local t = {}
    for i,slot in ipairs(slots) do
      table.insert(t,table.concat(slot,">"))
    end
    table.insert(groups, "Group "..group..": "..table.concat(t,", "))
  end

  local sum = "Layout Name: " .. name .. "\n\n" .. table.concat(groups,"\n")
  -- print(sum)
  return sum
end

local function StoredRaidConfigToText(name)
  local config = EasyRaidSaverDB.templates[name]
  if not config then return end
  local layout = config.layout
  local prios = config.prios

  local r = RaidLayoutToText(name, layout) .. "\n\n"

  for extra,members in pairs(prios) do
    r = r .. extra ..": " .. table.concat(members,", ") .. "\n"
  end

  return r -- RaidLayoutToText(name, layout)
end

function TextToRaidConfig(text)
  if not text then return end

  local lower_text = string.lower(text)

  local s,e,template_name = string.find(lower_text,"layout%s*name%s*:%s*([%w _]+)\n*")
  if not s then return end
  -- grab the capitalized version
  local _,_,template_name = string.find(string.sub(text,s,e),":%s*([%w _]+)\n*")

  local rest = string.sub(lower_text,e)
  local config = {}
  for i=1,8 do
    config[i] = {}
  end
  for gnum,members in string.gfind(rest,"[ ]*group%s*(%d+)%s*:([%w> ,]+)") do
    gnum = tonumber(gnum)
    if gnum and members ~= "" then
      local ix = 1
      for member in string.gfind(members,"%s*([%w>]+)%s*[,]*%s*") do
        -- split on >
        config[gnum][ix] = config[gnum][ix] or {}
        for part in string.gfind(member,"(%w+)>?") do
          -- part = string.upper(string.sub(part,1,1)) .. string.lower(string.sub(part,2))
          table.insert(config[gnum][ix],Capitalize(part))
        end
        ix = ix + 1
      end
    end
  end
  -- TODO do a wf search now

  local extras = {}
  table.insert(extras,"Windfury")
  for k,_ in pairs(roleMap) do
    table.insert(extras,k)
  end
  local prios = {}
  for _,extra in ipairs(extras) do
    prios[extra] = {}
    local _,_,extra_str = string.find(rest,"[ ]*"..string.lower(extra).."s*:([%w ,]+)")
    if extra_str then
      -- print(extra_str)
      for member in string.gfind(extra_str,"%s*([%w]+)%s*[,]*%s*") do
        table.insert(prios[extra],Capitalize(member))
      end
    end
  end

  return config,template_name,prios
end

function RandomizeRaid()
  local max = GetNumRaidMembers()
  for i=1,max do
    SwapRaidSubgroup(math.random(1,max),math.random(1,max))
  end
end

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
    -- TODO can't set this in stone with rolemap, a class can be many roles at once
    for role,classList in pairs(roleMap) do -- rolemap is really broad, will probably cause issues
      if elem(classList, class) then
        roles[name] = role
        break
      end
    end
  end
  return currentConfig, raidUnits, classes, roles
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
        -- print("a: "..raidUnits[name])
        -- print("b: "..raidUnits[tempName])
        SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
        currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
        return MoveDirectlyOrSwap(tempName, desiredConfig[tempName], currentConfig, raidUnits, subgroupCount, desiredConfig, visited)
      end
    end
  end
  
  return false
end

-- this takes a simple config of names->subgroup where all members have been assigned a spot
local function ConfigureRaid(desiredConfig)
  local currentConfig, raidUnits = GetCurrentRaidConfiguration()
  local subgroupCount = {}

  for i = 1, 8 do
    subgroupCount[i] = 0
  end

  for _, subgroup in pairs(currentConfig) do
    subgroupCount[subgroup] = subgroupCount[subgroup] + 1
  end

  -- First pass: Move as many members directly as possible
  local queue = {}
  local queue_c = 0
  for name, desiredSubgroup in pairs(desiredConfig) do
    table.insert(queue, {name = name, desiredSubgroup = desiredSubgroup})
    queue_c = queue_c + 1
  end

  while queue_c > 0 do
    local moved = false
    local remainingQueue = {}
    local remainingQueue_c = 0

    for _, entry in ipairs(queue) do
      local name = entry.name
      local desiredSubgroup = entry.desiredSubgroup
      local visited = {}

      if not MoveDirectlyOrSwap(name, desiredSubgroup, currentConfig, raidUnits, subgroupCount, desiredConfig, visited) then
        table.insert(remainingQueue, entry)
        remainingQueue_c = remainingQueue_c + 1
      else
        moved = true
      end
    end

    if not moved then
      -- No progress was made; perform a forced swap to break the deadlock
      local entry = table.remove(remainingQueue, 1)
      remainingQueue_c = remainingQueue_c - 1
      local name = entry.name
      local desiredSubgroup = entry.desiredSubgroup
      local visited = {}

      -- Force a swap with any member in the desired subgroup
      for tempName, tempSubgroup in pairs(currentConfig) do
        if tempSubgroup == desiredSubgroup then
          SwapRaidSubgroup(raidUnits[name], raidUnits[tempName])
          currentConfig[name], currentConfig[tempName] = currentConfig[tempName], currentConfig[name]
          break
        end
      end
    end

    queue = remainingQueue
    queue_c = remainingQueue_c
  end
end

function ArrangeRaid(desiredConfig)
  local layout = deepcopy(desiredConfig.layout)
  local prios = deepcopy(desiredConfig.prios)
  local groups = {}
  local remainingMembers = {}
  local currentRaid, raidUnits, classes, _roles = GetCurrentRaidConfiguration()
  local roles = {}

  -- This should compare current config and desired config, if a desired config name is a prefix of a current config
  -- name, uniquely, then rename the desired config name. This lets you write Ferro when you mean Ferroklast

  -- TODO test this
  do -- resolve prefix names
    for group,group_slots in ipairs(layout) do
      for slot,slot_options in ipairs(group_slots) do
        for i,name_option in ipairs(slot_options) do
          -- skip keywords
          if not key(classEnum,name_option) and not key(roleEnum,name_option) then
            local count = 0
            local t = {}
            for real_name,subgroup in pairs(currentRaid) do
              if string.find(real_name,"^"..name_option) then
                count = count + 1
                table.insert(t,real_name)
              end
            end
            if count == 1 then
              layout[group][slot][i] = t[1]
            elseif count > 0 then
              -- warn multi prefix exists
              print("Multiple raid members could match the layout config name "..name_option..": "..table.concat(t,", "))
            end
          end
        end
      end
    end

    for prio,names in pairs(prios) do
      for i,desired_name in ipairs(names) do
        local count = 0
        local t = {}
        for real_name,_ in pairs(currentRaid) do
          if string.find(real_name,"^"..desired_name) then
            count = count + 1
            table.insert(t,real_name)
          end
        end
        if count == 1 then
          prios[prio][i] = t[1]
          -- print("prioname " .. temp_name)
        elseif count > 0 then
          -- warn multi prefix exists
          print("Multiple raid members could match the prio config name "..desired_name..": "..table.concat(t,", "))
        end
      end
    end
  end

  -- use the prio lists to narrow roles
  -- TODO this is where to assign roles, not with GetCurrentRaidConfiguration
  for role,members in pairs(prios) do
    if role ~= "Windfury" then
      for _,member in ipairs(members) do
        roles[member] = role
        -- print(member .. " : " .. role)
      end
    end
  end

  -- Initialize groups
  for i = 1, 8 do
    groups[i] = {}
  end

  -- Convert the current raid list to a set of names for easy lookup
  local raidSet = {}
  for name, _ in pairs(currentRaid) do
    raidSet[name] = true
  end

  -- Function to check if a name is a role or class
  local function isSpecial(name)
    return roleEnum[name] or classEnum[name]
  end

  -- First pass: Place the first specific name in each slot if possible
  for groupNumber = 1, 8 do
    local members = layout[groupNumber] or {}
    for _, slotOptions in ipairs(members) do
      local firstOption = slotOptions[1]
      if firstOption and not isSpecial(firstOption) and raidSet[firstOption] then
        table.insert(groups[groupNumber], firstOption)
        raidSet[firstOption] = nil -- Mark the name as used
      end
    end
  end

  -- Collect remaining raid members after specific names are placed
  for name, _ in pairs(raidSet) do
      table.insert(remainingMembers, name)
  end

  -- TODO the way to handle WF here is probably to prio wf names in the actual slot options
  -- so if a group would have a shaman, place a wf named melee ahead of any Melee prios
  -- this means shaman, and named slots of shaman class, should probably get filled before generic Melee fill

  -- Second pass: Fill roles with remaining members based on priority, with fallback
  for groupNumber = 1, 8 do
    local members = layout[groupNumber] or {}
    for _, slotOptions in ipairs(members) do
      if getn(groups[groupNumber]) < 5 then
        local filledSlot = false
        -- Start with the first option if it's a role, then try other options
        for _, name in ipairs(slotOptions) do
          if isSpecial(name) then
            -- print(name)
            -- Try to fill with an appropriate remaining member
            -- TODO account for windfury role prio too, wars should get wf prio over rogues
            for i, n in ipairs(remainingMembers) do
              -- local r = roles[n]
              -- if r == "Tank" then r = "Melee" end
              local class = classes[n]
              -- your role matches slotname, or your class matches slot name, or your class _can_ fit the role
              local function hasRole(role,class)
                for role,classes in pairs(roleMap) do
                  for _,mapped_class in ipairs(classes) do
                    if mapped_class == class then return role end
                  end
                end
                return nil
              end
              if roles[n] == name or class == name or (not roles[n] and (hasRole(name,class) == name)) then
                if DEBUG2 then
                  print("placing "..remainingMembers[i].." in group "..groupNumber.." due to having role "..hasRole(name,class))
                end
                table.insert(groups[groupNumber], table.remove(remainingMembers, i))
                filledSlot = true
                break -- Role is filled, stop checking further options
              end
            end
          elseif raidSet[name] then
            -- Fallback to specific name if role/class isn't filled
            table.insert(groups[groupNumber], name)
            for i, n in ipairs(remainingMembers) do
              if n == name then table.remove(remainingMembers,i) end
            end
            raidSet[name] = nil -- Mark the name as used
            filledSlot = true
            break
          end
          if filledSlot then break end
        end
      end
    end
  end

  -- If any members are still left, place them in the first available slot
  local groupIdx = 1
  -- print(table.concat(remainingMembers))
  while getn(remainingMembers) > 0 do
    if getn(groups[groupIdx]) < 5 then
      table.insert(groups[groupIdx], table.remove(remainingMembers, 1))
    else
      groupIdx = groupIdx + 1
      -- if groupIdx > 8 then
      --   print("foo")
      --   for i=1,8 do
      --     print(table.concat(groups[i]))
      --   end
      -- end
    end
  end

  -- Debugging output
  if DEBUG1 then
    for i = 1, 8 do
      print("Group " .. i .. ": " .. table.concat(groups[i], ", "))
    end
  end

  -- Return the simple layout here, so a list of names and their group number
  local t = {}
  for g, members in ipairs(groups) do
    for _, member in ipairs(members) do
      t[member] = g
    end
  end
  return t
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
    if ESRConfigFrame:IsShown() then ESRConfigFrame:Hide() end
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
    rightArrowButton.tex = arrowTextureUp

    local arrowTextureDown = rightArrowButton:CreateTexture(nil, "ARTWORK")
    arrowTextureDown:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")  -- Path to the right arrow texture
    arrowTextureDown:SetAllPoints(rightArrowButton)  -- Make the texture fill the entire button

    -- Set the normal and pushed textures for the button
    rightArrowButton:SetNormalTexture(arrowTextureUp)
    rightArrowButton:SetPushedTexture(arrowTextureDown)

    -- Add a script to handle the button click
    rightArrowButton:SetScript("OnClick", function()
      EasyRaidSaverDB.show_config = not EasyRaidSaverDB.show_config
      EasyRaidSaver:UpdateButtonStates()
      if EasyRaidSaverDB.show_config then
        ConfigFrame:Show()
      else
        ConfigFrame:Hide()
      end
    end)

    -- Show the button
    rightArrowButton:Show()
    ConfigFrame:SetPoint("TOPLEFT", rightArrowButton,"TOPRIGHT", 0, 0)

      
    local EditBox = CreateFrame("EditBox","ERSEditBox",ConfigFrame)
    EditBox:SetMultiLine(true)
    EditBox:SetAutoFocus(false) -- Prevent the box from auto-focusing
    EditBox:SetFontObject(GameFontNormal)
    EditBox:SetWidth(180)
    EditBox:SetHeight(140) -- Set a large height to enable scrolling
    EditBox:SetText("Raid Layout")
    EditBox:SetPoint("TOPLEFT", rightArrowButton,"TOPLEFT", 30, -70)
    EditBox:Hide()
   
    -- Add a background to the frame
    local bg = EditBox:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("LEFT", EditBox,"LEFT", 0, 0)
    bg:SetPoint("LEFT", EditBox,"LEFT", 0, 0)
    bg:SetWidth(EditBox:GetWidth())
    bg:SetHeight(EditBox:GetHeight())
    bg:SetTexture(0, 0, 0, 0.7) -- Black background with some transparency

    -- dynamic size
    local measureFontString = EditBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    measureFontString:Hide()
    measureFontString:SetFontObject(EditBox:GetFontObject())

    function EditBox:Display()
      local text = self:GetText()
      measureFontString:SetText(text)
      local width = measureFontString:GetStringWidth()
      local _,lines = string.gsub(text,"\n","")
      local font = self:GetFontObject()
      local _,font_size = font:GetFont()
      local height = (lines + 1) * font_size + 10

      self:SetWidth(max(width,200))
      self:SetHeight(max(height,90))
      bg:SetHeight(self:GetHeight())
      bg:SetWidth(self:GetWidth())
      self:Show()
    end

    EditBox:SetScript("OnEscapePressed", function ()
      this:ClearFocus()
      this:Display()
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
        EditBox:Display()
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
            EditBox:Display()
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
          local layout = MakeRaidLayout(EasyRaidSaverDB.saved_raid)
          EditBox:SetText(RaidLayoutToText("last_raid_quicksave", layout))
          UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
          EditBox:Display()
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
        local layout = {}
        if not (GetNumRaidMembers() > 0) then
          layout[UnitName("player")] = 1
          for i=1,GetNumPartyMembers() do
            layout[GetUnitName("party"..i)] = 1
          end
        else
          layout = GetCurrentRaidConfiguration()
        end
        EditBox:SetText(RaidLayoutToText("new layout", MakeRaidLayout(layout)))

        UIDropDownMenu_SetSelectedName(MyDropdown, this:GetText())
        EditBox:Display()
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
      local conf,name,prios = TextToRaidConfig(EditBox:GetText())

      if conf then
        EasyRaidSaverDB.templates[name] = { layout = conf, prios = prios }
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
        -- local simple = ToSimpleConfig(EasyRaidSaverDB.templates[name])
        -- ConfigureRaid(simple)
        local simple = ArrangeRaid(EasyRaidSaverDB.templates[name])
        if not DEBUG2 then ConfigureRaid(simple) end
        -- ConfigureRaid(EasyRaidSaverDB.templates[name])
        ers_print("Applying layout: " .. name)
        count_roster_updates = true
        if DEBUG1 then
          ERSRemoveDupes()
          if DidRaidMatch(simple,GetCurrentRaidConfiguration()) then
            print(updates)
            count_roster_updates = false
          end
        end
        EasyRaidSaverDB.settings.active_template = name
        SetCheckboxGreyed(ERSLiveToggle, not EasyRaidSaverDB.settings.active_template)
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
      EasyRaidSaver:UpdateButtonStates()
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
function EasyRaidSaver:UpdateButtonStates()
  if GetNumRaidMembers() > 0 then
    SaveRaidButton:Show()
    RestoreRaidButton:Show()
    if IsRaidOfficer() then
      ApplyTemplateButton:Enable()
    else
      ApplyTemplateButton:Disable()
    end

    if EasyRaidSaverDB.saved_raid and IsRaidOfficer() then
      RestoreRaidButton:Enable()
    else
      RestoreRaidButton:Disable()
    end
  else
    SaveRaidButton:Hide()
    RestoreRaidButton:Hide()
    ApplyTemplateButton:Disable()

    -- ESRConfigFrame:Hide()
  end
  if EasyRaidSaverDB.show_config then ESRConfigFrame:Show() else ESRConfigFrame:Hide() end
  if EasyRaidSaverDB.settings.live_checked and EasyRaidSaverDB.settings.active_template then
    ESRConfigFrameButton.tex:SetVertexColor(0,1,0,1)
  else
    ESRConfigFrameButton.tex:SetVertexColor(1,1,1,1)
  end
  UpdateInfoButton()
end

-- Function to save the raid setup
function ERS_SaveRaid()
  ers_print("Quick-saving current raid layout.")
  saved_raid = GetCurrentRaidConfiguration()
  EasyRaidSaverDB.saved_raid = saved_raid

  EasyRaidSaver:UpdateButtonStates()
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
  EasyRaidSaver[event](this,arg1,arg2,arg3,arg4,arg6,arg7,arg8,arg9,arg9,arg10)
end)

function EasyRaidSaver:Load()
  EasyRaidSaverDB = EasyRaidSaverDB or {}
  EasyRaidSaverDB.settings = EasyRaidSaverDB.settings or {}
  EasyRaidSaverDB.templates = EasyRaidSaverDB.templates or {}
  EasyRaidSaverDB.show_config = EasyRaidSaverDB.show_config or true

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
    EasyRaidSaver:UpdateButtonStates()
  end)

  EasyRaidSaver:UpdateButtonStates()
end

function EasyRaidSaver:ADDON_LOADED(addon)
  if addon ~= "EasyRaidSaver" then return end
  EasyRaidSaver:Load()
  EasyRaidSaver:RegisterEvent("RAID_ROSTER_UPDATE")
  EasyRaidSaver:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function EasyRaidSaver:PLAYER_ENTERING_WORLD()
  EasyRaidSaver:UpdateButtonStates()
end

local last_count = GetNumRaidMembers()
function EasyRaidSaver:RAID_ROSTER_UPDATE()
  if count_roster_updates then updates = updates + 1 end
  EasyRaidSaver:UpdateButtonStates()
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
      ConfigureRaid(ArrangeRaid(EasyRaidSaverDB.templates[EasyRaidSaverDB.settings.active_template]))
    end
  end
end
