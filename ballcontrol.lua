--[[
========================================================
  BALL CONTROL
  repo : supercaptain1233/ballcontrol
  file : ballcontrol.lua
  ------------------------------------------------------
  For ball vs ball 1v1 games.
  ------------------------------------------------------
  TOP BUTTON    = ENEMY CONTROL
    while on, your thumbstick / WASD drives the
    enemy ball. it follows your input anywhere.
  BOTTOM BUTTON = SELF CONTROL
    while on, your own ball follows your input
    instead of the game moving it.
  ------------------------------------------------------
  Both on = both balls follow the same input.
  Toggle either one before the match. It stays
  armed and hooks the balls the moment they spawn.
  ------------------------------------------------------
  X     = unload everything and restore all parts
  MOVE  = hold it and drag the panel anywhere
========================================================
]]

local RAW = "https://raw.githubusercontent.com/"
  .. "supercaptain1233/ballcontrol/main/ballcontrol.lua"

-- one instance only, kill the old one first
pcall(function()
  local old = getgenv().BallControl
  if old and old.destroy then old.destroy() end
end)

task.wait(0.2)

local S = {}
getgenv().BallControl = S

S.alive = true
S.conns = {}
S.enemyOn = false
S.selfOn = false
S.enemyPart = nil
S.selfPart = nil
S.localPart = nil
S.floorY = nil
S.lastEnemyPos = nil
S.saved = {}
S.ui = {}
S.speed = 70
S.scanAcc = 0
S.gui = nil
S.err = nil

-- ======================================================
-- services, every one wrapped so one failure can't
-- take the whole boot down
-- ======================================================
local function svc(name)
  local ok, s = pcall(function()
    return game:GetService(name)
  end)
  if ok then return s end
  return nil
end

local Players = svc("Players")
local RunService = svc("RunService")
local UIS = svc("UserInputService")
local TweenService = svc("TweenService")
local VirtualUser = svc("VirtualUser")

local LP = Players and Players.LocalPlayer

if not LP then
  warn("[BallControl] no LocalPlayer")
  return
end

-- ======================================================
-- small utilities
-- ======================================================
local function track(c)
  if c then
    S.conns[#S.conns + 1] = c
  end
  return c
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function safe(fn, ...)
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

local function zero()
  return Vector3.new(0, 0, 0)
end

local function flat(v)
  return Vector3.new(v.X, 0, v.Z)
end

local function mag(v)
  return math.sqrt(v.X * v.X + v.Z * v.Z)
end

local function unitXZ(v)
  local m = mag(v)
  if m < 0.0001 then return nil end
  return Vector3.new(v.X / m, 0, v.Z / m)
end

-- ======================================================
-- raycast setup for the floor probe
-- ======================================================
local rp = RaycastParams.new()
rp.IgnoreWater = true

local function setFilter(list)
  safe(function()
    rp.FilterType = Enum.RaycastFilterType.Exclude
  end)
  safe(function()
    rp.FilterType = Enum.RaycastFilterType.Blacklist
  end)
  rp.FilterDescendantsInstances = list
end

-- ======================================================
-- ball recognition
-- balls in these games are small unanchored spheres.
-- we score candidates so the real ball always wins
-- over random scenery and over the root part.
-- ======================================================
local NAME_HITS = { "ball", "orb", "sphere", "marble" }

local function ballScore(p)
  if not p then return 0 end
  if not p.Parent then return 0 end
  if not p:IsA("BasePart") then return 0 end
  if p.Anchored then return 0 end
  if p.Transparency >= 0.95 then return 0 end

  local sz = p.Size
  local mx = math.max(sz.X, sz.Y, sz.Z)
  local mn = math.min(sz.X, sz.Y, sz.Z)

  if mx > 22 then return 0 end
  if mn < 0.4 then return 0 end

  local n = string.lower(p.Name)
  local sc = 10

  for _, k in ipairs(NAME_HITS) do
    if string.find(n, k, 1, true) then
      sc = sc + 80
      break
    end
  end

  -- a ball is roughly round, reward that shape
  local ratio = mn / mx
  if ratio > 0.75 then
    sc = sc + 45
  elseif ratio > 0.5 then
    sc = sc + 20
  end

  if p.CanCollide then sc = sc + 12 end

  if string.find(n, "root", 1, true) then sc = sc - 30 end
  if string.find(n, "head", 1, true) then sc = sc - 22 end
  if string.find(n, "handle", 1, true) then sc = sc - 12 end
  if string.find(n, "torso", 1, true) then sc = sc - 25 end
  if string.find(n, "arm", 1, true) then sc = sc - 15 end
  if string.find(n, "leg", 1, true) then sc = sc - 15 end
  if string.find(n, "effect", 1, true) then sc = sc - 10 end
  if string.find(n, "trail", 1, true) then sc = sc - 18 end

  return sc
end

-- best scored part anywhere inside one model
local function bestIn(model)
  if not model then return nil end
  local best = nil
  local bestScore = 0

  local list = safe(function()
    return model:GetDescendants()
  end)

  if not list then return nil end

  for _, d in ipairs(list) do
    local sc = ballScore(d)
    if sc > bestScore then
      best = d
      bestScore = sc
    end
  end

  if bestScore < 20 then return nil end
  return best
end

-- ======================================================
-- finders
-- ======================================================
local function findSelf()
  local char = LP.Character
  if not char then return nil end
  local b = bestIn(char)
  if b then return b end

  -- fallback: the humanoid root, if nothing scored
  local hrp = char:FindFirstChild("HumanoidRootPart")
  if hrp and not hrp.Anchored then return hrp end
  return nil
end

local function findEnemy()
  local anchor = nil
  if S.selfPart and S.selfPart.Parent then
    anchor = S.selfPart.Position
  else
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then anchor = hrp.Position end
  end

  local best = nil
  local bestD = 100000

  local ok = pcall(function()
    for _, p in ipairs(Players:GetPlayers()) do
      if p ~= LP and p.Character then
        local b = bestIn(p.Character)
        if b then
          local d = 0
          if anchor then
            d = (b.Position - anchor).Magnitude
          end
          if d < bestD then
            best = b
            bestD = d
          end
        end
      end
    end
  end)

  if not ok then return nil end
  return best
end

-- ======================================================
-- floor probe, only used to stop the enemy ball
-- sinking under the arena
-- ======================================================
local function floorAt(p)
  if not p or not p.Parent then return nil end
  setFilter({ p, LP.Character })

  local from = p.Position + Vector3.new(0, 4, 0)
  local down = Vector3.new(0, -16, 0)
  local res = safe(function()
    return workspace:Raycast(from, down, rp)
  end)

  if res and res.Position then
    return res.Position.Y + (p.Size.Y * 0.5) + 0.12
  end
  return nil
end

-- ======================================================
-- input reader
-- thumbstick first, keyboard second
-- ======================================================
local function readDir()
  local char = LP.Character
  if char then
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
      local md = hum.MoveDirection
      local u = unitXZ(md)
      if u then return u end
    end
  end

  if not UIS then return zero() end

  local x, z = 0, 0
  if UIS:IsKeyDown(Enum.KeyCode.W) then z = z - 1 end
  if UIS:IsKeyDown(Enum.KeyCode.S) then z = z + 1 end
  if UIS:IsKeyDown(Enum.KeyCode.A) then x = x - 1 end
  if UIS:IsKeyDown(Enum.KeyCode.D) then x = x + 1 end

  local v = Vector3.new(x, 0, z)
  local u = unitXZ(v)
  if u then return u end
  return zero()
end

-- ======================================================
-- drive the self ball
-- pure velocity, Y untouched so it still bounces
-- ======================================================
local function driveSelf(dt, dir)
  local p = S.selfPart
  if not p or not p.Parent then return end

  local v = safe(function()
    return p.AssemblyLinearVelocity
  end) or zero()

  local target = dir * S.speed

  safe(function()
    p.AssemblyLinearVelocity =
      Vector3.new(target.X, v.Y, target.Z)
  end)

  safe(function()
    p.AssemblyAngularVelocity = zero()
  end)
end

-- ======================================================
-- drive the enemy ball
-- position stepping, because we don't own it
-- ======================================================
local function driveEnemy(dt, dir)
  local p = S.enemyPart
  if not p or not p.Parent then return end

  local pos = p.Position
  local target = dir * S.speed
  local step = target * dt
  local nextPos = pos + step

  -- if the game yanks it away, rebuild from last good
  if S.lastEnemyPos then
    local jump = (pos - S.lastEnemyPos).Magnitude
    if jump > 45 then
      nextPos = S.lastEnemyPos + step
    end
  end

  -- keep it above the floor
  if S.floorY and nextPos.Y < (S.floorY - 0.6) then
    nextPos = Vector3.new(nextPos.X, S.floorY, nextPos.Z)
  end

  local rot = safe(function()
    return p.CFrame.Rotation
  end)

  if rot then
    safe(function()
      p.CFrame = CFrame.new(nextPos) * rot
    end)
  else
    safe(function()
      p.CFrame = CFrame.new(nextPos)
    end)
  end

  -- kill its own horizontal drift, keep gravity
  local v = safe(function()
    return p.AssemblyLinearVelocity
  end) or zero()

  safe(function()
    p.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
  end)

  S.lastEnemyPos = nextPos
end

-- ======================================================
-- button paint
-- ======================================================
local COL_ON = Color3.fromRGB(38, 190, 150)
local COL_OFF = Color3.fromRGB(44, 50, 62)
local COL_TXT_ON = Color3.fromRGB(8, 22, 18)
local COL_TXT_OFF = Color3.fromRGB(168, 180, 196)

local function paint(btn, on, label)
  if not btn then return end
  btn.BackgroundColor3 = on and COL_ON or COL_OFF
  btn.TextColor3 = on and COL_TXT_ON or COL_TXT_OFF
  btn.Text = label .. (on and "   [ ON ]" or "   [ OFF ]")
end

function refreshButtons()
  paint(S.ui.enemy, S.enemyOn, "ENEMY CONTROL")
  paint(S.ui.self, S.selfOn, "SELF CONTROL")

  if S.ui.status then
    if S.enemyOn or S.selfOn then
      local e = S.enemyPart and "LOCKED" or "SEARCHING"
      local s = S.selfPart and "LOCKED" or "SEARCHING"
      S.ui.status.Text = "enemy " .. e .. "  /  self " .. s
      S.ui.status.TextColor3 = Color3.fromRGB(150, 235, 200)
    else
      S.ui.status.Text = "both off  -  idle"
      S.ui.status.TextColor3 = Color3.fromRGB(140, 150, 165)
    end
  end
end

-- ======================================================
-- self control on / off
-- ======================================================
function setSelf(on)
  S.selfOn = on and true or false

  if S.selfOn then
    S.selfPart = findSelf()
    if S.selfPart then
      S.saved.selfCollide = S.selfPart.CanCollide
      local char = S.selfPart.Parent
      local hum = char and char:FindFirstChildOfClass("Humanoid")
      if hum then
        S.saved.walk = hum.WalkSpeed
        safe(function() hum.WalkSpeed = 0 end)
      end
    end
  else
    if S.selfPart then
      if S.saved.selfCollide ~= nil then
        safe(function()
          S.selfPart.CanCollide = S.saved.selfCollide
        end)
      end
      local char = S.selfPart.Parent
      local hum = char and char:FindFirstChildOfClass("Humanoid")
      if hum and S.saved.walk then
        safe(function() hum.WalkSpeed = S.saved.walk end)
      end
      safe(function()
        S.selfPart.AssemblyAngularVelocity = zero()
      end)
    end
    S.selfPart = nil
  end

  refreshButtons()
end

-- ======================================================
-- enemy control on / off
-- ======================================================
function setEnemy(on)
  S.enemyOn = on and true or false

  if S.enemyOn then
    S.enemyPart = findEnemy()
    S.lastEnemyPos = nil
    S.floorY = nil
  else
    if S.enemyPart and S.enemyPart.Parent then
      safe(function()
        S.enemyPart.AssemblyAngularVelocity = zero()
      end)
    end
    S.enemyPart = nil
    S.lastEnemyPos = nil
    S.floorY = nil
  end

  refreshButtons()
end

-- ======================================================
-- protection layer
-- ======================================================

-- keep the session from timing out and dropping you
function antiAfk()
  track(LP.Idled:Connect(function()
    safe(function()
      VirtualUser:CaptureController()
      VirtualUser:ClickButton2(Vector2.new())
    end)
  end))
end

-- re-run the script after a teleport so a kick
-- or a lobby shuffle doesn't leave you with nothing
function antiKick()
  safe(function()
    local line = ("loadstring(game:HttpGet('%s'))()")
      :format(RAW)
    queue_on_teleport(line)
  end)
end

-- if the game flings your ball across the map while
-- self control is off, drag the speed back down
function antiFling()
  local p = S.localPart
  if not p or not p.Parent then return end

  local v = safe(function()
    return p.AssemblyLinearVelocity
  end)
  if not v then return end

  if v.Magnitude > 420 then
    local u = unitXZ(v)
    if u then
      safe(function()
        p.AssemblyLinearVelocity =
          Vector3.new(u.X * 420, v.Y, u.Z * 420)
      end)
    end
  end
end

-- if the panel gets deleted by the game, rebuild
function guiWatch()
  if not S.gui then return end
  if S.gui.Parent then return end
  safe(function() S.gui.Parent = getgenv().BallGuiHost end)
end

-- ======================================================
-- shutdown
-- ======================================================
S.destroy = function()
  if not S.alive then return end
  S.alive = false

  safe(function() if S.selfOn then setSelf(false) end end)
  safe(function() if S.enemyOn then setEnemy(false) end end)

  for _, c in ipairs(S.conns) do
    safe(function() c:Disconnect() end)
  end
  S.conns = {}

  safe(function() if S.gui then S.gui:Destroy() end end)

  safe(function()
    if getgenv().BallControl == S then
      getgenv().BallControl = nil
    end
  end)
end

-- ======================================================
-- gui
-- ======================================================
local function mk(class, props, parent)
  local i = Instance.new(class)
  for k, v in pairs(props) do
    i[k] = v
  end
  if parent then i.Parent = parent end
  return i
end

local function host()
  local h = nil
  safe(function() h = gethui() end)
  if not h then
    safe(function() h = game:GetService("CoreGui") end)
  end
  if not h then
    h = LP:FindFirstChild("PlayerGui")
    if not h then
      h = LP:WaitForChild("PlayerGui", 6)
    end
  end
  return h
end

local function buildGui()
  local gui = mk("ScreenGui", {
    Name = "BallControlUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
  })

  safe(function()
    if syn and syn.protect_gui then
      syn.protect_gui(gui)
    end
  end)

  local h = host()
  gui.Parent = h
  getgenv().BallGuiHost = h
  S.gui = gui

  local frame = mk("Frame", {
    Name = "Panel",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(262, 208),
    BackgroundColor3 = Color3.fromRGB(20, 23, 30),
    BorderSizePixel = 0,
  }, gui)

  mk("UICorner", {
    CornerRadius = UDim.new(0, 12),
  }, frame)

  mk("UIStroke", {
    Color = Color3.fromRGB(58, 68, 86),
    Thickness = 1.5,
  }, frame)

  -- title strip
  local bar = mk("Frame", {
    Name = "Bar",
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundColor3 = Color3.fromRGB(28, 32, 42),
    BorderSizePixel = 0,
  }, frame)

  mk("UICorner", {
    CornerRadius = UDim.new(0, 12),
  }, bar)

  mk("Frame", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 1, -14),
    BackgroundColor3 = Color3.fromRGB(28, 32, 42),
    BorderSizePixel = 0,
  }, bar)

  mk("TextLabel", {
    Text = "BALL CONTROL",
    Position = UDim2.new(0, 12, 0, 0),
    Size = UDim2.new(0, 130, 1, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(215, 225, 240),
    TextXAlignment = Enum.TextXAlignment.Left,
  }, bar)

  local moveBtn = mk("TextButton", {
    Text = "MOVE",
    Position = UDim2.new(1, -74, 0, 5),
    Size = UDim2.new(0, 44, 0, 20),
    BackgroundColor3 = Color3.fromRGB(46, 54, 68),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(190, 202, 220),
  }, bar)

  mk("UICorner", { CornerRadius = UDim.new(0, 6) }, moveBtn)

  local closeBtn = mk("TextButton", {
    Text = "X",
    Position = UDim2.new(1, -26, 0, 5),
    Size = UDim2.new(0, 20, 0, 20),
    BackgroundColor3 = Color3.fromRGB(196, 66, 74),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(255, 240, 240),
  }, bar)

  mk("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)

  -- the two control buttons
  local enemyBtn = mk("TextButton", {
    Text = "ENEMY CONTROL   [ OFF ]",
    Position = UDim2.new(0, 16, 0, 42),
    Size = UDim2.new(1, -32, 0, 52),
    BackgroundColor3 = COL_OFF,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COL_TXT_OFF,
  }, frame)

  mk("UICorner", { CornerRadius = UDim.new(0, 10) }, enemyBtn)
  mk("UIStroke", {
    Color = Color3.fromRGB(70, 82, 100),
    Thickness = 1,
  }, enemyBtn)

  local selfBtn = mk("TextButton", {
    Text = "SELF CONTROL   [ OFF ]",
    Position = UDim2.new(0, 16, 0, 102),
    Size = UDim2.new(1, -32, 0, 52),
    BackgroundColor3 = COL_OFF,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COL_TXT_OFF,
  }, frame)

  mk("UICorner", { CornerRadius = UDim.new(0, 10) }, selfBtn)
  mk("UIStroke", {
    Color = Color3.fromRGB(70, 82, 100),
    Thickness = 1,
  }, selfBtn)

  local status = mk("TextLabel", {
    Text = "both off  -  idle",
    Position = UDim2.new(0, 16, 0, 162),
    Size = UDim2.new(1, -32, 0, 16),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(140, 150, 165),
    TextXAlignment = Enum.TextXAlignment.Center,
  }, frame)

  local foot = mk("TextLabel", {
    Text = "thumbstick or WASD steers",
    Position = UDim2.new(0, 16, 0, 180),
    Size = UDim2.new(1, -32, 0, 14),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextColor3 = Color3.fromRGB(108, 118, 134),
    TextXAlignment = Enum.TextXAlignment.Center,
  }, frame)

  S.ui.enemy = enemyBtn
  S.ui.self = selfBtn
  S.ui.status = status
  S.ui.panel = frame

  -- wiring
  track(enemyBtn.MouseButton1Click:Connect(function()
    setEnemy(not S.enemyOn)
  end))

  track(selfBtn.MouseButton1Click:Connect(function()
    setSelf(not S.selfOn)
  end))

  track(closeBtn.MouseButton1Click:Connect(function()
    S.destroy()
  end))

  -- drag
  local dragging = false
  local dragStart = nil
  local startPos = nil

  track(moveBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
      or input.UserInputType == Enum.UserInputType.Touch then
      dragging = true
      dragStart = input.Position
      startPos = frame.Position
      moveBtn.BackgroundColor3 = Color3.fromRGB(70, 84, 104)
    end
  end))

  track(UIS.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
      or input.UserInputType == Enum.UserInputType.Touch then
      local d = input.Position - dragStart
      frame.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + d.X,
        startPos.Y.Scale,
        startPos.Y.Offset + d.Y
      )
    end
  end))

  track(UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
      or input.UserInputType == Enum.UserInputType.Touch then
      if dragging then
        dragging = false
        moveBtn.BackgroundColor3 = Color3.fromRGB(46, 54, 68)
      end
    end
  end))

  refreshButtons()
end

-- ======================================================
-- main loop
-- ======================================================
function startLoop()
  local slow = 0

  track(RunService.Heartbeat:Connect(function(dt)
    if not S.alive then return end

    slow = slow + dt
    if slow >= 0.4 then
      slow = 0
      guiWatch()

      -- keep targets hooked, rescan if they vanished
      if S.selfOn and (not S.selfPart or not S.selfPart.Parent) then
        S.selfPart = findSelf()
        refreshButtons()
      end

      if S.enemyOn
        and (not S.enemyPart or not S.enemyPart.Parent) then
        S.enemyPart = findEnemy()
        S.lastEnemyPos = nil
        refreshButtons()
      end

      if S.enemyPart and S.enemyPart.Parent then
        S.floorY = floorAt(S.enemyPart)
      end

      -- anti fling only while the game is steering
      if not S.selfOn then
        if not S.localPart or not S.localPart.Parent then
          S.localPart = findSelf()
        end
        antiFling()
      end
    end

    local step = math.min(dt, 0.05)
    local dir = readDir()
    local moving = mag(dir) > 0.05

    if S.selfOn and S.selfPart and moving then
      driveSelf(step, dir)
    end

    if S.enemyOn and S.enemyPart and moving then
      driveEnemy(step, dir)
    end
  end))
end

-- ======================================================
-- boot
-- ======================================================
function boot()
  buildGui()
  antiAfk()
  antiKick()
  startLoop()

  safe(function()
    setthreadidentity(7)
  end)
end

local ok, err = xpcall(boot, function(e)
  return tostring(e) .. "\n" .. debug.traceback()
end)

if not ok then
  S.err = tostring(err)
  safe(function()
    warn("[BallControl] " .. tostring(err))
  end)

  -- visible failure so a dead panel is diagnosable
  safe(function()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return end
    local box = Instance.new("TextLabel")
    box.Size = UDim2.fromOffset(300, 90)
    box.Position = UDim2.new(0.5, -150, 0, 60)
    box.BackgroundColor3 = Color3.fromRGB(30, 16, 16)
    box.TextColor3 = Color3.fromRGB(255, 190, 190)
    box.Font = Enum.Font.Code
    box.TextSize = 10
    box.TextWrapped = true
    box.Text = "BOOT ERROR\n" .. tostring(err)
    box.Parent = pg
    task.delay(14, function()
      safe(function() box:Destroy() end)
    end)
  end)
end
