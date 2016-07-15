--------------------------------------------------------------------------------
-- DS18B20 one wire module for NODEMCU
-- NODEMCU TEAM
-- LICENCE: http://opensource.org/licenses/MIT
-- Vowstar <vowstar@nodemcu.com>
-- 2015/02/14 sza2 <sza2trash@gmail.com> Fix for negative values
--------------------------------------------------------------------------------

-- Set module name as parameter of require
local modname = ...
local M = {}
_G[modname] = M
--------------------------------------------------------------------------------
-- Local used variables
--------------------------------------------------------------------------------
-- DS18B20 dq pin
local pin = nil
-- DS18B20 default pin
local defaultPin = 9
--------------------------------------------------------------------------------
-- Local used modules
--------------------------------------------------------------------------------
-- Table module
local table = table
-- String module
local string = string
-- One wire module
local ow = ow
-- Timer module
local tmr = tmr
-- bit module
local bit = bit
local print = print
-- Limited to local environment
setfenv(1,M)
--------------------------------------------------------------------------------
-- Implementation
--------------------------------------------------------------------------------
-- Supported temperature units
--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
C = 'C'
F = 'F'
K = 'K'
--------------------------------------------------------------------------------
-- Public variables
--------------------------------------------------------------------------------
-- Last callback read temperature
temp_result = 0

--------------------------------------------------------------------------------
-- private functions
--------------------------------------------------------------------------------
local function parasitePowered(addr)
  ow.reset(pin)
  ow.select(pin, addr)
  ow.write(pin, 0xB4, 1)
  return ow.read(pin) == 0
end

local function readScratchpad(addr)
  ow.read(pin)
  present = ow.reset(pin)
  ow.select(pin, addr)
  ow.write(pin,0xBE,1)
  -- print("P="..present)
  local data = nil
  data = string.char(ow.read(pin))
  for i = 1, 8 do
    data = data .. string.char(ow.read(pin))
  end
  -- print(data:byte(1,9))
  return data
end

local function convertTemperature(data, addr, unit)
  local t = (data:byte(1) + data:byte(2) * 256)
  if (t > 32767) then
    t = t - 65536
  end

  if (addr:byte(1) == 0x28) then
    t = t * 625  -- DS18B20, 4 fractional bits
  else
    t = 1000 * (bit.rshift(t, 1))
    t = t - 250
    local h = 1000 * (data:byte(8) - data:byte(7))
    h = h / data:byte(8)
    t = t + h
    t = t * 10
  end

  if(unit == nil or unit == 'C') then
   -- do nothing
  elseif(unit == 'F') then
    t = t * 1.8 + 320000
  elseif(unit == 'K') then
    t = t + 2731500
  else
    return "Unknown unit"
  end
  return t / 10000
end

local function checkAddrCrc(addr)
  return ow.crc8(string.sub(addr,1,7)) == addr:byte(8)
end

local function checkDataCrc(data)
  return ow.crc8(string.sub(data,1,8)) == data:byte(9)
end

--------------------------------------------------------------------------------
-- public functions
--------------------------------------------------------------------------------
function setup(dq)
  pin = dq
  if(pin == nil) then
    pin = defaultPin
  end
  ow.setup(pin) 
end

function addrs()
  setup(pin)
  tbl = {}
  ow.reset_search(pin)
  repeat
    addr = ow.search(pin)
    if(addr ~= nil) then
      table.insert(tbl, addr)
    end
    tmr.wdclr()
  until (addr == nil)
  ow.reset_search(pin)
  return tbl
end

function callBack(addr, func)
  -- reset last temp
  temp_result = 0
  print(addr:byte(1,9))
  if checkAddrCrc(addr) then
    if ((addr:byte(1) == 0x10) or (addr:byte(1) == 0x28)) then
      -- print("Device is a DS18S20 family device.")
      parasite = parasitePowered(addr)
      ow.reset(pin)
      ow.select(pin, addr)
      ow.write(pin, 0x44, 1)
      if parasite then
        -- Parasite powered, need to wait ~750ms
        print ("Using parasite power wait")
        -- TODO: use different wait than delay
        tmr.alarm(1, 750, 0, function () processRead(addr, func) end)
      else
        -- external powered, waiting for finish
        print ("Using external powered wait")
        repeat
          local res = ow.read(pin)
          tmr.wdclr()
        until ( res ~= 0 )
        processRead(addr, func)
      end
    end
  end
end

local function processRead(addr, callback_func)
  data = readScratchpad(addr)
  if (checkDataCrc(data)) then
    temp_result = convertTemperature(data, addr, unit)
  else
    temp_result = "Data CRC is not valid"
  end
  tmr.wdclr()
  
  callback_func()
end

local function readNumber(addr, unit)
  result = nil
  setup(pin)
  flag = false
  if(addr == nil) then
    addresses = addrs()
  end
  if(addresses == nil) then
  -- return result
    return "Not found any sensor"
  else
    addr = addresses[1]
  end

  if checkAddrCrc(addr) then
    if ((addr:byte(1) == 0x10) or (addr:byte(1) == 0x28)) then
      -- print("Device is a DS18S20 family device.")
      parasite = parasitePowered(addr)
      ow.reset(pin)
      ow.select(pin, addr)
      ow.write(pin, 0x44, 1)
      if parasite then
        -- Parasite powered, need to wait ~750ms
        print ("Using parasite power wait")
        -- TODO: use different wait than delay
        tmr.delay(750000)
      else
        -- external powered, waiting for finish
        print ("Using external powered wait")
        repeat
          local res = ow.read(pin)
          tmr.wdclr()
        until ( res ~= 0 )
      end

      data = readScratchpad(addr)
      if (checkDataCrc(data)) then
        result = convertTemperature(data, addr, unit)
      else
        result = "Data CRC is not valid"
      end

      tmr.wdclr()
    else
    -- print("Device family is not recognized.")
      result = "Device family is not recognized."
    end
  else
  -- print("CRC is not valid!")
    result = "Address CRC is not valid"
  end
  return result
end

function read(addr, unit)
  t = readNumber(addr, unit)
  if (t == nil) then
    return nil
  else
    return t
  end
end

-- Return module table
return M
