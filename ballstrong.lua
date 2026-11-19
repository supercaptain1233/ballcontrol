--[[
========================================================
  BALL CONTROL  STRONG
  repo : supercaptain1233/ballcontrol
  file : ballstrong.lua
  ------------------------------------------------------
  Hard lock version. Grabs the ball by 球 name, by the
  floating label, by shape and by proximity to the right
  avatar, then holds it with a verify loop.
  ------------------------------------------------------
  TOP    = ENEMY CONTROL
  BOTTOM = SELF CONTROL
  SLIDER = speed
  pad    = steer      X = unload      MOVE = drag
  box around a ball = it is locked on
========================================================
]]

local RAW = "https://raw.githubusercontent.com/"
  .. "supercaptain1233/ballcontrol/main/ballstrong.lua"

pcall(function()
  local o = getgenv().BallStrong
  if o and o.destroy then o.destroy() end
end)

task.wait(0.2)

local S = {}
getgenv().BallStrong = S

S.alive = true
S.conns = {}
S.enemyOn = false
S.selfOn = false
S.enemyPart = nil
S.selfPart = nil
S.enemyOwner = nil
S.selfOwner = nil
S.saved = {}
S.ui = {}
S.speed = 75
S.gui = nil
S.stickDir = Vector3.new(0, 0, 0)
S.stickInput = nil
S.anchorY = nil

local function svc(n)
  local ok, s = pcall(function() return game:GetService(n) end)
  if ok then return s end
  return nil
end

local Players = svc("Players")
local RunService = svc("RunService")
local UIS = svc("UserInputService")
local VirtualUser = svc("VirtualUser")

local LP = Players and Players.LocalPlayer
if not LP then return end

local function track(c)
  if c then S.conns[#S.conns + 1] = c end
  return c
end

local function safe(fn, ...)
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

local function zero() return Vector3.new(0, 0, 0) end

local function mag(v)
  return math.sqrt(v.X * v.X + v.Z * v.Z)
end

local function unitXZ(v)
  local m = mag(v)
  if m < 0.0001 then return nil end
  return Vector3.new(v.X / m, 0, v.Z / m)
end

-- ======================================================
-- raycast
-- ======================================================
local rp = RaycastParams.new()
rp.IgnoreWater = true
safe(function()
  rp.FilterType = Enum.RaycastFilterType.Exclude
end)

-- ======================================================
-- scoring
-- ======================================================
local GOOD = { "球", "ball", "orb", "sphere", "marble" }
local BAD = { "碰撞箱", "装饰", "特效", "扭蛋", "商店",
  "大厅", "handle", "root", "head", "torso", "arm", "leg" }

local function hasLabel(p)
  local found = false
  safe(function()
    for _, d in ipairs(p:GetDescendants()) do
      if d:IsA("BillboardGui") then found = true break end
    end
  end)
  return found
end

local function score(p)
  if not p or not p.Parent then return 0 end
  if not p:IsA("BasePart") then return 0 end
  if p.Transparency >= 0.95 then return 0 end

  local s = p.Size
  local mx = math.max(s.X, s.Y, s.Z)
  local mn = math.min(s.X, s.Y, s.Z)

  if mx > 16 or mn < 0.5 then return 0 end
  if mn / mx < 0.45 then return 0 end

  local n = string.lower(p.Name)
  local sc = 0

  for _, k in ipairs(GOOD) do
    if string.find(n, k, 1, true) then
      sc = sc + 150
      break
    end
  end

  for _, k in ipairs(BAD) do
    if string.find(n, k, 1, true) then
      sc = sc - 55
      break
    end
  end

  if not p.Anchored then sc = sc + 50 end
  if hasLabel(p) then sc = sc + 40 end
  if p.CanCollide then sc = sc + 10 end

  return sc
end

local function resolve(inst)
  if not inst then return nil end
  if inst:IsA("BasePart") then return inst end
  if inst:IsA("Model") then
    local pp = inst.PrimaryPart
    if pp then return pp end
    for _, d in ipairs(inst:GetDescendants()) do
      if d:IsA("BasePart") then return d end
    end
  end
  return nil
end

local function bestIn(model)
  if not model then return nil end
  local best, bs = nil, 0
  for _, d in ipairs(model:GetDescendants()) do
    local sc = score(d)
    if sc > bs then best = d bs = sc end
  end
  if bs < 100 then return nil end
  return best
end

local function hrpOf(plr)
  local c = plr and plr.Character
  if not c then return nil end
  return c:FindFirstChild("HumanoidRootPart")
end

local function nearPart(anchor, skip, radius)
  if not anchor then return nil end
  local best, bd = nil, radius
  for _, d in ipairs(workspace:GetDescendants()) do
    if d ~= skip and d:IsA("BasePart") then
      local sc = score(d)
      if sc >= 100 then
        local dist = (d.Position - anchor).Magnitude
        if dist < bd then best = d bd = dist end
      end
    end
  end
  return best
end

-- ======================================================
-- finders, sticky
-- ======================================================
local function lockSelf()
  local char = LP.Character
  if not char then return nil end

  local b = bestIn(char)
  if b then return resolve(b) end

  local hrp = char:FindFirstChild("HumanoidRootPart")
  if not hrp then return nil end
  return resolve(nearPart(hrp.Position, nil, 45))
end

local function lockEnemy()
  local myHrp = hrpOf(LP)
  local anchor = myHrp and myHrp.Position

  local best, bd = nil, 100000

  pcall(function()
    for _, p in ipairs(Players:GetPlayers()) do
      if p ~= LP and p.Character then
        local b = bestIn(p.Character)
        local hrp = hrpOf(p)
        if not b and hrp then
          b = nearPart(hrp.Position, S.selfPart, 45)
        end
        if b then
          local r = resolve(b)
          if r and r ~= S.selfPart then
            local d = 0
            if anchor then d = (r.Position - anchor).Magnitude end
            if d < bd then best = r bd = d S.enemyOwner = p end
          end
        end
      end
    end
  end)

  return best
end

-- is the lock still sane
local function stillValid(part, plr)
  if not part or not part.Parent then return false end
  local hrp = hrpOf(plr)
  if not hrp then return true end
  return (part.Position - hrp.Position).Magnitude < 70
end

-- ======================================================
-- input
-- ======================================================
local function readDir()
  if mag(S.stickDir) > 0.06 then
    local u = unitXZ(S.stickDir)
    if u then return u end
  end
  if not UIS then return zero() end
  local x, z = 0, 0
  if UIS:IsKeyDown(Enum.KeyCode.W) then z = z - 1 end
  if UIS:IsKeyDown(Enum.KeyCode.S) then z = z + 1 end
  if UIS:IsKeyDown(Enum.KeyCode.A) then x = x - 1 end
  if UIS:IsKeyDown(Enum.KeyCode.D) then x = x + 1 end
  local u = unitXZ(Vector3.new(x, 0, z))
  if u then return u end
  return zero()
end

-- ======================================================
-- constraint kill
-- ======================================================
local KILL = { "AlignPosition", "AlignOrientation",
  "AlignConstraint", "BodyVelocity", "BodyGyro",
  "BodyAngularVelocity", "BodyPosition", "LinearVelocity",
  "AngularVelocity", "BodyForce", "VectorForce" }

function strip(root, key)
  S.saved[key] = {}
  if not root then return end
  for _, d in ipairs(root:GetDescendants()) do
    for _, cls in ipairs(KILL) do
      if d:IsA(cls) then
        local rec = { inst = d }
        local okE = pcall(function()
          rec.enabled = d.Enabled
          rec.prop = "Enabled"
          d.Enabled = false
        end)
        if not okE then
          pcall(function()
            rec.mf = d.MaxForce
            rec.prop = "MaxForce"
            if typeof(d.MaxForce) == "Vector3" then
              d.MaxForce = zero()
            else
              d.MaxForce = 0
            end
          end)
        end
        if rec.prop then
          S.saved[key][#S.saved[key] + 1] = rec
        end
        break
      end
    end
  end
end

function restore(key)
  local r = S.saved[key]
  if not r then return end
  for _, rec in ipairs(r) do
    safe(function()
      if rec.mf ~= nil then
        rec.inst[rec.prop] = rec.mf
      else
        rec.inst[rec.prop] = rec.enabled
      end
    end)
  end
  S.saved[key] = nil
end

-- ======================================================
-- hold part
-- ======================================================
function seize(p, key)
  if not p then return end
  S.saved[key .. "Anchor"] = p.Anchored
  S.saved[key .. "Collide"] = p.CanCollide
  safe(function() p.Anchored = false end)
  safe(function() p.CanCollide = false end)
  safe(function() p:SetNetworkOwner(LP) end)
  strip(p, key .. "Forces")
end

function release(p, key)
  if not p then return end
  restore(key .. "Forces")
  if S.saved[key .. "Anchor"] ~= nil then
    safe(function() p.Anchored = S.saved[key .. "Anchor"] end)
  end
  if S.saved[key .. "Collide"] ~= nil then
    safe(function() p.CanCollide = S.saved[key .. "Collide"] end)
  end
end

-- ======================================================
-- floor snap
-- ======================================================
local function floorY(p)
  if not p or not p.Parent then return nil end
  rp.FilterDescendantsInstances = { p, S.selfPart, S.enemyPart }
  local res = safe(function()
    return workspace:Raycast(p.Position + Vector3.new(0, 4, 0),
      Vector3.new(0, -18, 0), rp)
  end)
  if res and res.Position then
    return res.Position.Y + (p.Size.Y * 0.5) + 0.15
  end
  return nil
end

-- ======================================================
-- step
-- ======================================================
local function step(p, dt, dir, fy)
  local pos = p.Position
  local nxt = pos + (dir * S.speed * dt)

  if fy and nxt.Y < fy - 1 then
    nxt = Vector3.new(nxt.X, fy, nxt.Z)
  end

  local rot = safe(function() return p.CFrame.Rotation end)
  if rot then
    safe(function() p.CFrame = CFrame.new(nxt) * rot end)
  else
    safe(function() p.CFrame = CFrame.new(nxt) end)
  end

  local v = safe(function()
    return p.AssemblyLinearVelocity
  end) or zero()

  safe(function()
    p.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
  end)
  safe(function() p.AssemblyAngularVelocity = zero() end)
end

-- ======================================================
-- highlight
-- ======================================================
local function box(p, color)
  local b = Instance.new("SelectionBox")
  b.Adornee = p
  b.LineThickness = 0.03
  b.Color3 = color
  b.SurfaceTransparency = 1
  b.Parent = p
  return b
end

local function unbox(p)
  if not p then return end
  safe(function()
    for _, d in ipairs(p:GetChildren()) do
      if d:IsA("SelectionBox") then d:Destroy() end
    end
  end)
end

-- ======================================================
-- paint
-- ======================================================
local C_ON = Color3.fromRGB(38, 190, 150)
local C_OFF = Color3.fromRGB(44, 50, 62)
local T_ON = Color3.fromRGB(8, 22, 18)
local T_OFF = Color3.fromRGB(168, 180, 196)

local function paint(b, on, l)
  if not b then return end
  b.BackgroundColor3 = on and C_ON or C_OFF
  b.TextColor3 = on and T_ON or T_OFF
  b.Text = l .. (on and "   [ ON ]" or "   [ OFF ]")
end

function refresh()
  paint(S.ui.enemy, S.enemyOn, "ENEMY CONTROL")
  paint(S.ui.self, S.selfOn, "SELF CONTROL")
  if not S.ui.status then return end
  local e = S.enemyPart and "LOCKED" or "none"
  local s = S.selfPart and "LOCKED" or "none"
  S.ui.status.Text = "self " .. s .. "   enemy " .. e
  S.ui.status.TextColor3 = S.enemyPart or S.selfPart
    and Color3.fromRGB(150, 235, 200)
    or Color3.fromRGB(140, 150, 165)
end

-- ======================================================
-- toggles
-- ======================================================
function setSelf(on)
  S.selfOn = on and true or false
  if S.selfOn then
    local p = lockSelf()
    S.selfPart = p
    if p then
      seize(p, "self")
      unbox(p)
      S.selfBox = box(p, Color3.fromRGB(80, 240, 160))
      S.anchorY = nil
    end
  else
    if S.selfPart then
      unbox(S.selfPart)
      release(S.selfPart, "self")
    end
    S.selfPart = nil
  end
  refresh()
end

function setEnemy(on)
  S.enemyOn = on and true or false
  if S.enemyOn then
    local p = lockEnemy()
    S.enemyPart = p
    if p then
      seize(p, "enemy")
      unbox(p)
      S.enemyBox = box(p, Color3.fromRGB(240, 110, 90))
    end
  else
    if S.enemyPart then
      unbox(S.enemyPart)
      release(S.enemyPart, "enemy")
    end
    S.enemyPart = nil
    S.enemyOwner = nil
  end
  refresh()
end

-- ======================================================
-- protection
-- ======================================================
function antiAfk()
  track(LP.Idled:Connect(function()
    safe(function()
      VirtualUser:CaptureController()
      VirtualUser:ClickButton2(Vector2.new())
    end)
  end))
end

function antiKick()
  safe(function()
    queue_on_teleport(
      ("loadstring(game:HttpGet('%s'))()"):format(RAW))
  end)
end

-- ======================================================
-- destroy
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
    if getgenv().BallStrong == S then
      getgenv().BallStrong = nil
    end
  end)
end

-- ======================================================
-- gui
-- ======================================================
local function mk(c, pr, par)
  local i = Instance.new(c)
  for k, v in pairs(pr) do i[k] = v end
  if par then i.Parent = par end
  return i
end

local function host()
  local h = nil
  safe(function() h = gethui() end)
  if not h then
    safe(function() h = game:GetService("CoreGui") end)
  end
  if not h then h = LP:FindFirstChild("PlayerGui") end
  return h
end

local function bindStick(pad, knob)
  local R = 44
  local function mid()
    return pad.AbsolutePosition + (pad.AbsoluteSize * 0.5)
  end
  local function setK(x, y)
    knob.Position = UDim2.fromScale(0.5, 0.5)
      + UDim2.fromOffset(x, y)
  end
  local function upd(i)
    local c = mid()
    local dx, dy = i.Position.X - c.X, i.Position.Y - c.Y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > R then dx, dy, len = dx / len * R, dy / len * R, R end
    setK(dx, dy)
    if len < 5 then S.stickDir = zero() return end
    S.stickDir = Vector3.new(dx / len, 0, dy / len)
      * math.min(len / R, 1)
  end
  track(pad.InputBegan:Connect(function(i)
    local t = i.UserInputType
    if t == Enum.UserInputType.Touch
      or t == Enum.UserInputType.MouseButton1 then
      S.stickInput = i
      pad.BackgroundColor3 = Color3.fromRGB(52, 62, 80)
      upd(i)
    end
  end))
  track(UIS.InputChanged:Connect(function(i)
    if S.stickInput ~= i then return end
    upd(i)
  end))
  local function rel(i)
    if S.stickInput ~= i then return end
    S.stickInput = nil
    S.stickDir = zero()
    setK(0, 0)
    pad.BackgroundColor3 = Color3.fromRGB(34, 39, 50)
  end
  track(UIS.InputEnded:Connect(rel))
  track(pad.InputEnded:Connect(rel))
end

local function buildGui()
  local gui = mk("ScreenGui", {
    Name = "BallStrongUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 1000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
  })
  safe(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
  end)
  local h = host()
  gui.Parent = h
  getgenv().BallGuiHost = h
  S.gui = gui

  local f = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(268, 366),
    BackgroundColor3 = Color3.fromRGB(18, 21, 28),
    BorderSizePixel = 0,
  }, gui)
  mk("UICorner", { CornerRadius = UDim.new(0, 12) }, f)
  mk("UIStroke", {
    Color = Color3.fromRGB(58, 68, 86), Thickness = 1.5 }, f)

  local bar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundColor3 = Color3.fromRGB(28, 32, 42),
    BorderSizePixel = 0,
  }, f)
  mk("UICorner", { CornerRadius = UDim.new(0, 12) }, bar)
  mk("Frame", {
    Size = UDim2.new(1, 0, 0, 14),
    Position = UDim2.new(0, 0, 1, -14),
    BackgroundColor3 = Color3.fromRGB(28, 32, 42),
    BorderSizePixel = 0,
  }, bar)

  mk("TextLabel", {
    Text = "BALL CONTROL  STRONG",
    Position = UDim2.new(0, 12, 0, 0),
    Size = UDim2.new(0, 170, 1, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = Color3.fromRGB(215, 225, 240),
    TextXAlignment = Enum.TextXAlignment.Left,
  }, bar)

  local mv = mk("TextButton", {
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
  mk("UICorner", { CornerRadius = UDim.new(0, 6) }, mv)

  local x = mk("TextButton", {
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
  mk("UICorner", { CornerRadius = UDim.new(0, 6) }, x)

  local eb = mk("TextButton", {
    Text = "ENEMY CONTROL   [ OFF ]",
    Position = UDim2.new(0, 16, 0, 40),
    Size = UDim2.new(1, -32, 0, 44),
    BackgroundColor3 = C_OFF,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = T_OFF,
  }, f)
  mk("UICorner", { CornerRadius = UDim.new(0, 10) }, eb)
  mk("UIStroke", {
    Color = Color3.fromRGB(70, 82, 100), Thickness = 1 }, eb)

  local sb = mk("TextButton", {
    Text = "SELF CONTROL   [ OFF ]",
    Position = UDim2.new(0, 16, 0, 90),
    Size = UDim2.new(1, -32, 0, 44),
    BackgroundColor3 = C_OFF,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = T_OFF,
  }, f)
  mk("UICorner", { CornerRadius = UDim.new(0, 10) }, sb)
  mk("UIStroke", {
    Color = Color3.fromRGB(70, 82, 100), Thickness = 1 }, sb)

  local pad = mk("TextButton", {
    Text = "",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 142),
    Size = UDim2.fromOffset(110, 110),
    BackgroundColor3 = Color3.fromRGB(34, 39, 50),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    ZIndex = 3,
  }, f)
  mk("UICorner", { CornerRadius = UDim.new(1, 0) }, pad)
  mk("UIStroke", {
    Color = Color3.fromRGB(72, 84, 104), Thickness = 2 }, pad)

  local knob = mk("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(46, 46),
    BackgroundColor3 = Color3.fromRGB(96, 214, 176),
    BorderSizePixel = 0,
    ZIndex = 4,
  }, pad)
  mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

  -- speed row
  local srow = mk("Frame", {
    Position = UDim2.new(0, 16, 0, 260),
    Size = UDim2.new(1, -32, 0, 30),
    BackgroundTransparency = 1,
  }, f)

  local stxt = mk("TextLabel", {
    Text = "SPEED 75",
    Size = UDim2.new(0, 74, 1, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(170, 182, 200),
    TextXAlignment = Enum.TextXAlignment.Left,
  }, srow)

  local sbar = mk("Frame", {
    Position = UDim2.new(0, 76, 0.5, -3),
    Size = UDim2.new(1, -76, 0, 6),
    BackgroundColor3 = Color3.fromRGB(44, 50, 62),
    BorderSizePixel = 0,
  }, srow)
  mk("UICorner", { CornerRadius = UDim.new(1, 0) }, sbar)

  local sfill = mk("Frame", {
    Size = UDim2.new(0.4, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(96, 214, 176),
    BorderSizePixel = 0,
  }, sbar)
  mk("UICorner", { CornerRadius = UDim.new(1, 0) }, sfill)

  local sbtn = mk("TextButton", {
    Text = "",
    Position = UDim2.new(0, 76, 0.5, -11),
    Size = UDim2.new(1, -76, 0, 22),
    BackgroundTransparency = 1,
  }, srow)

  local function setSpeed(frac)
    frac = math.clamp(frac, 0.1, 1)
    S.speed = math.floor(20 + frac * 140)
    sfill.Size = UDim2.new(frac, 0, 1, 0)
    stxt.Text = "SPEED " .. S.speed
  end

  local sDown = false
  track(sbtn.InputBegan:Connect(function(i)
    local t = i.UserInputType
    if t == Enum.UserInputType.Touch
      or t == Enum.UserInputType.MouseButton1 then
      sDown = true
    end
  end))
  track(sbtn.InputEnded:Connect(function() sDown = false end))
  track(UIS.InputChanged:Connect(function(i)
    if not sDown then return end
    local rel = (i.Position.X - sbar.AbsolutePosition.X)
      / math.max(sbar.AbsoluteSize.X, 1)
    setSpeed(rel)
  end))
  setSpeed(0.4)

  local st = mk("TextLabel", {
    Text = "both off",
    Position = UDim2.new(0, 16, 0, 296),
    Size = UDim2.new(1, -32, 0, 16),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(140, 150, 165),
    TextXAlignment = Enum.TextXAlignment.Center,
  }, f)

  mk("TextLabel", {
    Text = "drag pad to steer  -  box = locked",
    Position = UDim2.new(0, 16, 0, 316),
    Size = UDim2.new(1, -32, 0, 14),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextColor3 = Color3.fromRGB(108, 118, 134),
    TextXAlignment = Enum.TextXAlignment.Center,
  }, f)

  S.ui.enemy = eb
  S.ui.self = sb
  S.ui.status = st
  S.ui.pad = pad
  S.ui.knob = knob

  bindStick(pad, knob)

  track(eb.MouseButton1Click:Connect(function()
    setEnemy(not S.enemyOn)
  end))
  track(sb.MouseButton1Click:Connect(function()
    setSelf(not S.selfOn)
  end))
  track(x.MouseButton1Click:Connect(function() S.destroy() end))

  local drag, ds, sp = false, nil, nil
  track(mv.InputBegan:Connect(function(i)
    local t = i.UserInputType
    if t == Enum.UserInputType.Touch
      or t == Enum.UserInputType.MouseButton1 then
      drag, ds, sp = true, i.Position, f.Position
    end
  end))
  track(UIS.InputChanged:Connect(function(i)
    if not drag then return end
    local d = i.Position - ds
    f.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X,
      sp.Y.Scale, sp.Y.Offset + d.Y)
  end))
  track(UIS.InputEnded:Connect(function(i)
    local t = i.UserInputType
    if t == Enum.UserInputType.Touch
      or t == Enum.UserInputType.MouseButton1 then
      drag = false
    end
  end))

  refresh()
end

-- ======================================================
-- loop
-- ======================================================
function startLoop()
  local slow = 0
  track(RunService.Heartbeat:Connect(function(dt)
    if not S.alive then return end

    slow = slow + dt
    if slow >= 0.35 then
      slow = 0

      if S.selfOn then
        if not stillValid(S.selfPart, LP) then
          unbox(S.selfPart)
          S.selfPart = lockSelf()
          if S.selfPart then
            seize(S.selfPart, "self")
            S.selfBox = box(S.selfPart,
              Color3.fromRGB(80, 240, 160))
          end
          refresh()
        else
          safe(function() S.selfPart.Anchored = false end)
        end
      end

      if S.enemyOn then
        if not stillValid(S.enemyPart, S.enemyOwner) then
          unbox(S.enemyPart)
          S.enemyPart = lockEnemy()
          if S.enemyPart then
            seize(S.enemyPart, "enemy")
            S.enemyBox = box(S.enemyPart,
              Color3.fromRGB(240, 110, 90))
          end
          refresh()
        else
          safe(function() S.enemyPart.Anchored = false end)
        end
      end
    end

    local step_dt = math.min(dt, 0.05)
    local dir = readDir()

    if S.selfOn and S.selfPart then
      step(S.selfPart, step_dt, dir, nil)
    end

    if S.enemyOn and S.enemyPart then
      if not S.enemyFY then S.enemyFY = floorY(S.enemyPart) end
      step(S.enemyPart, step_dt, dir, S.enemyFY)
    end
  end))
end

function boot()
  buildGui()
  antiAfk()
  antiKick()
  startLoop()
end

local ok, err = xpcall(boot, function(e)
  return tostring(e) .. "\n" .. debug.traceback()
end)

if not ok then
  safe(function() warn("[BallStrong] " .. tostring(err)) end)
end
