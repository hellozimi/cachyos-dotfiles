-- One slider per controllable display: sysfs backlights on active DRM outputs,
-- and Apple displays exposed as USB HID devices (even when DP has two tiles).
local devices = {}
local order = {}
local opened = false

local function read(path)
  local content = noctalia.readFile(path)
  return content and noctalia.string.trim(content) or nil
end

local function render()
  if not opened then return end

  local rows = {}
  for _, id in ipairs(order) do
    local device = devices[id]
    table.insert(rows, ui.column({ key = id, gap = 7 }, {
      ui.row({ align = "center", justify = "space_between" }, {
        ui.label({ text = device.label, flexGrow = 1 }),
        ui.label({ text = device.percent and (tostring(device.percent) .. "%") or "--", color = "primary" }),
      }),
      ui.slider({
        key = id .. ":slider",
        min = 0, max = 100, step = 1,
        value = device.percent or 0,
        enabled = device.percent ~= nil,
        onChange = function(value) onBrightnessChanged(id, value) end,
      }),
      device.error and ui.label({ text = device.error, color = "error", maxLines = 2 }) or nil,
    }))
  end

  if #order == 0 then
    table.insert(rows, ui.label({ text = "No adjustable displays connected" }))
  end

  panel.render(ui.column({ gap = 14, flexGrow = 1 }, {
    ui.label({ text = "Display brightness", fontSize = 16, fontWeight = "bold" }),
    ui.scroll({ gap = 20, flexGrow = 1 }, rows),
  }))
end

local function discover()
  local found = {}
  local sorted = {}
  local backlights = noctalia.listDir("/sys/class/backlight") or {}
  local drm = noctalia.listDir("/sys/class/drm") or {}

  for _, output in ipairs(noctalia.outputs()) do
    for _, connector in ipairs(drm) do
      if string.sub(connector, -#output.name) == output.name then
        local connectorPath = "/sys/class/drm/" .. connector
        if read(connectorPath .. "/enabled") == "enabled" then
          for _, backlight in ipairs(backlights) do
            if noctalia.fileExists(connectorPath .. "/" .. backlight) then
              local id = "backlight:" .. backlight
              if not found[id] then
                local device = devices[id] or { id = id }
                device.label = string.sub(output.name, 1, 3) == "eDP" and "Laptop display" or (output.description or output.name)
                device.kind = "backlight"
                device.connector = output.name
                device.path = "/sys/class/backlight/" .. backlight
                found[id] = device
                table.insert(sorted, id)
              end
            end
          end
        end
      end
    end
  end

  if noctalia.commandExists("asdbctl") then
    for _, usb in ipairs(noctalia.listDir("/sys/bus/usb/devices") or {}) do
      local path = "/sys/bus/usb/devices/" .. usb
      local vendor = read(path .. "/idVendor")
      local product = read(path .. "/idProduct")
      if vendor == "05ac" and (product == "1114" or product == "1116" or product == "1118") then
        local serial = read(path .. "/serial")
        if serial and serial ~= "" then
          local id = "apple:" .. serial
          if not found[id] then
            local device = devices[id] or { id = id }
            device.label = read(path .. "/product") or "Apple Display"
            device.kind = "apple"
            device.serial = serial
            found[id] = device
            table.insert(sorted, id)
          end
        end
      end
    end
  end

  local labelCounts = {}
  for _, id in ipairs(sorted) do
    if found[id].kind == "apple" then
      local label = found[id].label
      labelCounts[label] = (labelCounts[label] or 0) + 1
    end
  end
  for _, id in ipairs(sorted) do
    local device = found[id]
    if device.kind == "apple" and labelCounts[device.label] > 1 then
      device.label = device.label .. " (" .. string.sub(device.serial, -4) .. ")"
    end
  end

  devices = found
  order = sorted
  render()
end

local function refresh(device)
  if device.writing or device.queued ~= nil or device.reading then return end

  -- A failed read keeps the last known value instead of nagging; only
  -- failed writes surface an error, since those are what the user expects
  -- to have happened.
  if device.kind == "backlight" then
    local current = tonumber(read(device.path .. "/brightness"))
    local max = tonumber(read(device.path .. "/max_brightness"))
    if current and max and max > 0 then
      device.percent = math.clamp(math.floor(current * 100 / max + 0.5), 0, 100)
    end
    render()
    return
  end

  device.reading = true
  local started = noctalia.runAsync({ "asdbctl", "--serial", device.serial, "get" }, function(result)
    device.reading = false
    if devices[device.id] ~= device or device.writing then return end
    local value = result.exitCode == 0 and tonumber(string.match(result.stdout or "", "brightness%s+(%d+)")) or nil
    if value then device.percent = value end
    render()
  end)
  if not started then
    device.reading = false
    device.error = "Could not start asdbctl"
    render()
  end
end

local function write(device, value)
  device.writing = true
  local args
  if device.kind == "apple" then
    args = { "asdbctl", "--serial", device.serial, "set", tostring(value) }
  else
    args = { "noctalia", "msg", "brightness-set", device.connector, tostring(value) .. "%" }
  end

  local started = noctalia.runAsync(args, function(result)
    device.writing = false
    if devices[device.id] ~= device then return end
    if result.exitCode ~= 0 then
      device.queued = nil
      device.error = "Could not set brightness: " .. noctalia.string.trim(result.stderr or "")
      render()
      return
    end
    if device.queued ~= nil and device.queued ~= value then
      local nextValue = device.queued
      device.queued = nil
      write(device, nextValue)
    else
      device.queued = nil
      refresh(device)
    end
  end)
  if not started then
    device.writing = false
    device.queued = nil
    device.error = "Could not start brightness control"
    render()
  end
end

noctalia.setUpdateInterval(3000)

function onOpen(_context)
  opened = true
  discover()
  for _, id in ipairs(order) do refresh(devices[id]) end
end

function onClose()
  opened = false
end

function update()
  if not opened then return end
  discover()
  for _, id in ipairs(order) do refresh(devices[id]) end
end

function onBrightnessChanged(id, value)
  local device = devices[id]
  local percent = tonumber(value)
  if not device or not percent then return end
  percent = math.clamp(math.floor(percent + 0.5), 0, 100)
  device.percent = percent
  device.error = nil
  render()
  if device.writing then
    device.queued = percent
  else
    write(device, percent)
  end
end

-- Also allows an IPC brightness write for a specific display ID.
function onIpc(event, payload)
  if event == "inspect" then
    discover()
    for _, id in ipairs(order) do
      local device = devices[id]
      noctalia.log(device.label .. " [" .. id .. "]: " .. (device.percent and tostring(device.percent) or "loading") .. "%")
    end
  elseif event == "set" then
    local id, value = string.match(payload or "", "^(%S+)%s+(%d+)$")
    if id then onBrightnessChanged(id, value) end
  end
end
