-- sketch
-- v 0.1
--
-- isomorphic keyboard 
-- and pattern recorder 
-- for sketching
--
-- e1     scale
-- k1+e1  root note


--
-- LIBRARIES
--
pattern_time = require 'pattern_time'
musicutil = require 'musicutil'
ControlSpec = require "controlspec"
Formatters = require "formatters"
MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
engine.name = "MollyThePoly"
--mxsamples=include("mx.samples/lib/mx.samples")
--engine.name="MxSamples"

--
-- DEVICES
--
g = grid.connect()
m = midi.connect()

--
-- VARIABLES
--
PATH = _path.data.."sketch-mxsamples/"
selected_voice = 1
grid_dirty = true
screen_dirty = true
scale_names = {}
for i = 1, #musicutil.SCALES do
  table.insert(scale_names, musicutil.SCALES[i].name)
end
lit = {}
pat_timer = {}

local specs = {}
local options = {}

options.OSC_WAVE_SHAPE = {"Triangle", "Saw", "Pulse"}
specs.PW_MOD = ControlSpec.new(0, 1, "lin", 0, 0.2, "")
options.PW_MOD_SRC = {"LFO", "Env 1", "Manual"}
specs.FREQ_MOD_LFO = ControlSpec.UNIPOLAR
specs.FREQ_MOD_ENV = ControlSpec.BIPOLAR
specs.GLIDE = ControlSpec.new(0, 5, "lin", 0, 0, "s")
specs.MAIN_OSC_LEVEL = ControlSpec.new(0, 1, "lin", 0, 1, "")
specs.SUB_OSC_LEVEL = ControlSpec.UNIPOLAR
specs.SUB_OSC_DETUNE = ControlSpec.new(-5, 5, "lin", 0, 0, "ST")
specs.NOISE_LEVEL = ControlSpec.new(0, 1, "lin", 0, 0.1, "")
specs.HP_FILTER_CUTOFF = ControlSpec.new(10, 20000, "exp", 0, 10, "Hz")
specs.LP_FILTER_CUTOFF = ControlSpec.new(20, 20000, "exp", 0, 300, "Hz")
specs.LP_FILTER_RESONANCE = ControlSpec.new(0, 1, "lin", 0, 0.1, "")
options.LP_FILTER_TYPE = {"-12 dB/oct", "-24 dB/oct"}
options.LP_FILTER_ENV = {"Env-1", "Env-2"}
specs.LP_FILTER_CUTOFF_MOD_ENV = ControlSpec.new(-1, 1, "lin", 0, 0.25, "")
specs.LP_FILTER_CUTOFF_MOD_LFO = ControlSpec.UNIPOLAR
specs.LP_FILTER_TRACKING = ControlSpec.new(0, 2, "lin", 0, 1, ":1")
specs.LFO_FREQ = ControlSpec.new(0.05, 20, "exp", 0, 5, "Hz")
options.LFO_WAVE_SHAPE = {"Sine", "Triangle", "Saw", "Square", "Random"}
specs.LFO_FADE = ControlSpec.new(-15, 15, "lin", 0, 0, "s")
specs.ENV_ATTACK = ControlSpec.new(0.002, 5, "lin", 0, 0.01, "s")
specs.ENV_DECAY = ControlSpec.new(0.002, 10, "lin", 0, 0.3, "s")
specs.ENV_SUSTAIN = ControlSpec.new(0, 1, "lin", 0, 0.5, "")
specs.ENV_RELEASE = ControlSpec.new(0.002, 10, "lin", 0, 0.5, "s")
specs.AMP = ControlSpec.new(0, 11, "lin", 0, 0.5, "")
specs.AMP_MOD = ControlSpec.UNIPOLAR
specs.RING_MOD_FREQ = ControlSpec.new(10, 300, "exp", 0, 50, "Hz")
specs.RING_MOD_FADE = ControlSpec.new(-15, 15, "lin", 0, 0, "s")
specs.RING_MOD_MIX = ControlSpec.UNIPOLAR
specs.CHORUS_MIX = ControlSpec.new(0, 1, "lin", 0, 0.8, "")

local function format_ratio_to_one(param)
  return util.round(param:get(), 0.01) .. ":1"
end

local function format_fade(param)
  local secs = param:get()
  local suffix = " in"
  if secs < 0 then
    secs = secs - specs.LFO_FADE.minval
    suffix = " out"
  end
  secs = util.round(secs, 0.01)
  return math.abs(secs) .. " s" .. suffix
end


--
-- INIT FUNCTIONS
--
function init_parameters()

  params:add_separator("SKETCH")
  params:add_group("SKETCH - ROUTING",3)
  params:add{
    type="option",
    id="output",
    name="output",
    options={"audio","midi","audio+midi"},
    default=1
  }
  params:add{
    type="number",
    id="note_channel",
    name="midi note channel",
    min=1,
    max=16,
    default=1
  }
  params:add{
    type="number",
    id="cc_channel",
    name="midi cc channel",
    min=1,
    max=16,
    default=2
  }
  params:add_group("SKETCH - KEYBOARD",4)
  params:add{
    type="option",
    id="scale",
    name="scale",
    options=scale_names,
    default=41,
    action=function()
      build_scale()
    end
  }
  params:add{
    type="number",
    id="root_note",
    name="root note",
    min=0,
    max=127,
    default=24,
    formatter=function(param)
      return musicutil.note_num_to_name(param:get(),true)
    end,
    action=function(value)
      build_scale()
    end
  }
  params:add{
    type="number",
    id="velocity",
    name="note velocity",
    min=0,
    max=127,
    default=80
  }
  params:add{
    type="number",
    id="row_interval",
    name="row interval",
    min=1,
    max=12,
    default=5,
    action=function(value)
      build_scale()
    end
  }
  params:bang()
end

function init_mxsamples()
  mx=mxsamples:new()
  instrument_list=mx:list_instruments()
  params:add_group("SKETCH - VOICES",56)
  for i=1,8 do
    params:add_separator("Voice "..i)
    params:add{type="option",id=i.."mx_instrument",name="instrument",options=instrument_list,default=1}
    params:add{type="number",id=i.."mx_velocity",name="velocity",min=0,max=127,default=80}
    params:add{type="control",id=i.."mx_amp",name="amp",controlspec=controlspec.new(0,2,'lin',0.01,0.5,'amp',0.01/2)}
    params:add{type="control",id=i.."mx_pan",name="pan",controlspec=controlspec.new(-1,1,'lin',0,0)}
    params:add{type="control",id=i.."mx_attack",name="attack",controlspec=controlspec.new(0,10,'lin',0,0,'s')}
    params:add{type="control",id=i.."mx_release",name="release",controlspec=controlspec.new(0,10,'lin',0,2,'s')}
  end
end

function init_molly()
  params:add_group("SKETCH - VOICES",312)
  for i=1,8 do
    params:add_separator("Voice "..i)
    params:add{type="option",id=i.."osc_wave_shape",name="Osc Wave Shape",options=options.OSC_WAVE_SHAPE,default=3}
    params:add{type="control",id=i.."pulse_width_mod",name="Pulse Width Mod",controlspec=specs.PW_MOD}
    params:add{type="option",id=i.."pulse_width_mod_src",name="Pulse Width Mod Src",options=options.PW_MOD_SRC}
    params:add{type="control",id=i.."freq_mod_lfo",name="Frequency Mod (LFO)",controlspec=specs.FREQ_MOD_LFO}
    params:add{type="control",id=i.."freq_mod_env",name="Frequency Mod (Env-1)",controlspec=specs.FREQ_MOD_ENV}
    params:add{type="control",id=i.."glide",name="Glide",controlspec=specs.GLIDE,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."main_osc_level",name="Main Osc Level",controlspec=specs.MAIN_OSC_LEVEL}
    params:add{type="control",id=i.."sub_osc_level",name="Sub Osc Level",controlspec=specs.SUB_OSC_LEVEL}
    params:add{type="control",id=i.."sub_osc_detune",name="Sub Osc Detune",controlspec=specs.SUB_OSC_DETUNE}
    params:add{type="control",id=i.."noise_level",name="Noise Level",controlspec=specs.NOISE_LEVEL,action=engine.noiseLevel}
    params:add{type="control",id=i.."hp_filter_cutoff",name="HP Filter Cutoff",controlspec=specs.HP_FILTER_CUTOFF,formatter=Formatters.format_freq}
    params:add{type="control",id=i.."lp_filter_cutoff",name="LP Filter Cutoff",controlspec=specs.LP_FILTER_CUTOFF,formatter=Formatters.format_freq}
    params:add{type="control",id=i.."lp_filter_resonance",name="LP Filter Resonance",controlspec=specs.LP_FILTER_RESONANCE}
    params:add{type="option",id=i.."lp_filter_type",name="LP Filter Type",options=options.LP_FILTER_TYPE,default=2}
    params:add{type="option",id=i.."lp_filter_env",name="LP Filter Env",options=options.LP_FILTER_ENV}
    params:add{type="control",id=i.."lp_filter_mod_env",name="LP Filter Mod (Env)",controlspec=specs.LP_FILTER_CUTOFF_MOD_ENV}
    params:add{type="control",id=i.."lp_filter_mod_lfo",name="LP Filter Mod (LFO)",controlspec=specs.LP_FILTER_CUTOFF_MOD_LFO}
    params:add{type="control",id=i.."lp_filter_tracking",name="LP Filter Tracking",controlspec=specs.LP_FILTER_TRACKING,formatter=format_ratio_to_one}
    params:add{type="control",id=i.."lfo_freq",name="LFO Frequency",controlspec=specs.LFO_FREQ,formatter=Formatters.format_freq}
    params:add{type="option",id=i.."lfo_wave_shape",name="LFO Wave Shape",options=options.LFO_WAVE_SHAPE}
    params:add{type="control",id=i.."lfo_fade",name="LFO Fade",controlspec=specs.LFO_FADE,formatter=format_fade,action=function(v)
      if v<0 then v=specs.LFO_FADE.minval-0.00001+math.abs(v) end
        engine.lfoFade(v)
      end}
    params:add{type="control",id=i.."env_1_attack",name="Env-1 Attack",controlspec=specs.ENV_ATTACK,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."env_1_decay",name="Env-1 Decay",controlspec=specs.ENV_DECAY,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."env_1_sustain",name="Env-1 Sustain",controlspec=specs.ENV_SUSTAIN}
    params:add{type="control",id=i.."env_1_release",name="Env-1 Release",controlspec=specs.ENV_RELEASE,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."env_2_attack",name="Env-2 Attack",controlspec=specs.ENV_ATTACK,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."env_2_decay",name="Env-2 Decay",controlspec=specs.ENV_DECAY,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."env_2_sustain",name="Env-2 Sustain",controlspec=specs.ENV_SUSTAIN}
    params:add{type="control",id=i.."env_2_release",name="Env-2 Release",controlspec=specs.ENV_RELEASE,formatter=Formatters.format_secs}
    params:add{type="control",id=i.."amp",name="Amp",controlspec=specs.AMP}
    params:add{type="control",id=i.."amp_mod",name="Amp Mod (LFO)",controlspec=specs.AMP_MOD}
    params:add{type="control",id=i.."ring_mod_freq",name="Ring Mod Frequency",controlspec=specs.RING_MOD_FREQ,formatter=Formatters.format_freq}
    params:add{type="control",id=i.."ring_mod_fade",name="Ring Mod Fade",controlspec=specs.RING_MOD_FADE,formatter=format_fade,action=function(v)
      if v<0 then v=specs.RING_MOD_FADE.minval-0.00001+math.abs(v) end
        engine.ringModFade(v)
      end}
    params:add{type="control",id=i.."ring_mod_mix",name="Ring Mod Mix",controlspec=specs.RING_MOD_MIX}
    params:add{type="control",id=i.."chorus_mix",name="Chorus Mix",controlspec=specs.CHORUS_MIX}
    
    --params:bang()
    
    params:add{type = "trigger", id=i.."create_lead", name = "Create Lead", action = function() randomize_params(i,"lead") end}
    params:add{type = "trigger", id=i.."create_pad", name = "Create Pad", action = function() randomize_params(i,"pad") end}
    params:add{type = "trigger", id=i.."create_percussion", name = "Create Percussion", action = function() randomize_params(i,"percussion") end}
  end
end



function init_pattern_recorders()
  grid_pattern = {}
  for i=1,8 do
    grid_pattern[i] = pattern_time.new()
    grid_pattern[i].process = grid_note
  end
  active_grid_pattern = 1
end

function init()
  init_parameters()
  --init_mxsamples()
  init_molly()
  init_pattern_recorders()
  init_pset_callbacks()
  clock.run(grid_redraw_clock)
  clock.run(redraw_clock)
end


--
-- CALLBACK FUNCTIONS
--
function init_pset_callbacks()
  params.action_write = function(filename,name,number)
    local pattern_data = {}
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if grid_pattern[i].count > 0 then
        pattern_data[i] = {}
        pattern_data[i].event = grid_pattern[i].event
        pattern_data[i].time = grid_pattern[i].time
        pattern_data[i].count = grid_pattern[i].count
        pattern_data[i].time_factor = grid_pattern[i].time_factor
        tab.save(pattern_data[i],pattern_file)
      else
        if util.file_exists(pattern_file) then
          os.execute("rm "..pattern_file)
        end    
      end
    end
    print("finished writing '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
  
  params.action_read = function(filename,silent,number)
    local pset_file = io.open(filename, "r")
    local pattern_data = {}
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if util.file_exists(pattern_file) then
        pattern_data[i] = {}
        grid_pattern[i]:rec_stop()
        grid_pattern[i]:stop()
        grid_pattern[i]:clear()
        pattern_data[i] = tab.load(pattern_file)
        for k,v in pairs(pattern_data[i]) do
          grid_pattern[i][k] = v
        end
      end
    end
    grid_dirty = true
    screen_dirty = true
    print("finished reading '"..filename.."' as PSET number: "..number)
  end
  
  params.action_delete = function(filename,name,number)
    print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      print(pattern_file)
      if util.file_exists(pattern_file) then
        os.execute("rm "..pattern_file)
      end
    end
  print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
end


--
-- CLOCK FUNCTIONS
--
function grid_redraw_clock()
  while true do
    clock.sleep(1/30) -- refresh at 30fps.
    if grid_dirty then
      grid_redraw()
      grid_dirty = false
    end
  end
end

function redraw_clock()
  while true do
    clock.sleep(1/30) -- refresh at 30fps.
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end


--
-- NOTE FUNCTIONS
--
function note_on(id,voice,note_num)
  if params:get("output") == 1 then
    engine.oscWaveShape(params:get(voice.."osc_wave_shape"))
    engine.pwMod(params:get(voice.."pulse_width_mod"))
    engine.pwModSource(params:get(voice.."pulse_width_mod_src"))
    engine.freqModEnv(params:get(voice.."freq_mod_env"))
    engine.freqModLfo(params:get(voice.."freq_mod_lfo"))
    engine.glide(params:get(voice.."glide"))
    engine.mainOscLevel(params:get(voice.."main_osc_level"))
    engine.subOscLevel(params:get(voice.."sub_osc_level"))
    engine.subOscDetune(params:get(voice.."sub_osc_detune"))
    engine.noiseLevel(params:get(voice.."noise_level"))
    engine.hpFilterCutoff(params:get(voice.."hp_filter_cutoff"))
    engine.lpFilterCutoff(params:get(voice.."lp_filter_cutoff"))
    engine.lpFilterResonance(params:get(voice.."lp_filter_resonance"))
    engine.lpFilterType(params:get(voice.."lp_filter_type"))
    engine.lpFilterCutoffEnvSelect(params:get(voice.."lp_filter_env"))
    engine.lpFilterCutoffModEnv(params:get(voice.."lp_filter_mod_env"))
    engine.lpFilterCutoffModLfo(params:get(voice.."lp_filter_mod_lfo"))
    engine.lpFilterTracking(params:get(voice.."lp_filter_tracking"))
    engine.lfoFreq(params:get(voice.."lfo_freq"))
    engine.lfoFade(params:get(voice.."lfo_fade"))
    engine.lfoWaveShape(params:get(voice.."lfo_wave_shape"))
    engine.env1Attack(params:get(voice.."env_1_attack"))
    engine.env1Decay(params:get(voice.."env_1_decay"))
    engine.env1Sustain(params:get(voice.."env_1_sustain"))
    engine.env1Release(params:get(voice.."env_1_release"))
    engine.env2Attack(params:get(voice.."env_2_attack"))
    engine.env2Decay(params:get(voice.."env_2_decay"))
    engine.env2Sustain(params:get(voice.."env_2_sustain"))
    engine.env2Release(params:get(voice.."env_2_release"))
    engine.amp(params:get(voice.."amp"))
    engine.ampMod(params:get(voice.."amp_mod"))
    engine.ringModFreq(params:get(voice.."ring_mod_freq"))
    engine.ringModFade(params:get(voice.."ring_mod_fade"))
    engine.ringModMix(params:get(voice.."ring_mod_mix"))
    engine.chorusMix(params:get(voice.."chorus_mix"))
    print("note on: "..id)
    engine.noteOn(id,musicutil.note_num_to_freq(note_num),80) --hardcoding velocity
  elseif params:get("output") == 2 then
    m:note_on(id,note_num, vel)
  elseif params:get("output") == 3 then
    m:note_on(note_num, vel)
    mx:on(
      {name=params:string(voice.."mx_instrument"),
      midi=note_num,
      velocity=params:get(voice.."mx_velocity"),
      amp=params:get(voice.."mx_amp"),
      pan=params:get(voice.."mx_pan")})
  end
end

function note_off(id,voice,note_num)
  if params:get("output") == 1 then
    print("note off: "..id)
    engine.noteOff(id)
  elseif params:get("output") == 2 then
    m:note_off(note_num)
  elseif params:get("output") == 3 then
    m:note_off(note_num)
    mx:off({name=params:string(voice.."mx_instrument"),midi=note_num})
  end
end

function all_notes_off()
  if params:get("output") == 1 then
    --engine.noteOffAll()
    for k,v in pairs(active_midi_notes) do
      note_off(selected_voice,k)
    end
  elseif params:get("output") == 2 then
    for k,v in pairs(active_midi_notes) do
      note_off(v)
    end
  elseif params:get("output") == 3 then
    engine.noteOffAll()
    for k,v in pairs(active_midi_notes) do
      note_off(v)
    end
  end
end

function clear_lit()
  for i,e in pairs(lit) do
    if e.id == nil and e.pattern == active_grid_pattern then
      print(e.voice.." "..midi_note[e.y][e.x].value)
      note_off(e.id,e.voice,midi_note[e.y][e.x].value)
      lit[i] = nil
    end
  end
end


function build_scale()
  if params:get("scale") ~= 41 then
    note_nums = musicutil.generate_scale_of_length(params:get("root_note"),params:get("scale"),112)
  else
    note_nums = {}
    for i=1,112 do
      note_nums[i] = nil
    end
  end

  row_start_note = params:get("root_note")
  note = {}
  for row = 8,1,-1 do
    note_value = row_start_note
    note[row] = {}
    for col = 3,16 do
      note[row][col] = {}
      note[row][col].value = note_value
      for i=1,112 do
        if note[row][col].value == note_nums[i] then
          note[row][col].in_scale = true
        end
      end
      note_value = note_value + 1
    end
    row_start_note = row_start_note + params:get("row_interval")
  end
  grid_dirty = true
end

function grid_note(e)
  --local note = ((7-e.y)*5) + e.x
  if e.state > 0 then
    note_on(e.id,e.voice,note[e.y][e.x].value)
    lit[e.id] = {}
    lit[e.id].voice = e.voice
    lit[e.id].pattern = e.pattern
    lit[e.id].x = e.x
    lit[e.id].y = e.y
  else
    if lit[e.id] ~= nil then
      note_off(e.id,e.voice,note[e.y][e.x].value)
      lit[e.id] = nil
    end
  end
  grid_redraw()
end


--
-- UI FUNCTIONS
--
function key(n,z)
  if n == 1 then
    shifted = z == 1
  elseif n == 2 and z == 1 then
    selected_voice = util.clamp(selected_voice-1,1,8)
  elseif n == 3 and z == 1 then
    selected_voice = util.clamp(selected_voice+1,1,8)
  end
  screen_dirty = true
end

function enc(n,d)
  if shifted and n == 1 then
    params:delta("root_note",d)
  elseif n == 1 then
    params:delta("scale",d)
  end
  screen_dirty = true
end

function g.key(x,y,z)
  -- pattern recorders
  if x == 1 then
    active_grid_pattern = y
    if z == 1 then
      pattern_rec_press(y)
    end
  elseif x == 2 then
    active_grid_pattern = y
    if z == 1 then
      pat_timer[y] = clock.run(pattern_clear_press,y)
    elseif z == 0 then
      if pat_timer[y] then
        clock.cancel(pat_timer[y])
        pattern_stop_press(y)
      end
    end

  -- notes
  elseif x > 2 then
    local e = {}
    e.id = selected_voice..x..y
    print(e.id)
    e.voice = selected_voice
    e.pattern = active_grid_pattern
    e.x = x
    e.y = y
    e.state = z
    grid_pattern[active_grid_pattern]:watch(e)
    grid_note(e)
  end
  grid_dirty = true
end

function pattern_clear_press(y)
  clock.sleep(0.5)
  grid_pattern[y]:stop()
  clear_lit()
  --all_notes_off()
  grid_pattern[y]:clear()
  pat_timer[y] = nil
  grid_dirty = true
end

function pattern_stop_press(y)
  --all_notes_off()
  grid_pattern[y]:rec_stop()
  grid_pattern[y]:stop()
  clear_lit()
  grid_dirty = true
end

function pattern_rec_press(y)
  if grid_pattern[y].rec == 0 and grid_pattern[y].count == 0 then
    grid_pattern[y]:stop()
    grid_pattern[y]:rec_start()
  elseif grid_pattern[y].rec == 1 then
    --all_notes_off()
    grid_pattern[y]:rec_stop()
    grid_pattern[y]:start()
  elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 0 then
    grid_pattern[y]:set_overdub(1)
  elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 1 then
    grid_pattern[y]:set_overdub(0)
  elseif grid_pattern[y].play == 0 and grid_pattern[y].count > 0 then
    grid_pattern[y]:start()
  end
  grid_dirty = true
end


--
-- REDRAW FUNCTIONS
--
function redraw()
  screen.clear()
  screen.level(15)

  
  screen.move(0,40)
  screen.text("selected voice: "..selected_voice)
  screen.move(0,60)
  screen.text("scale: "..scale_names[params:get("scale")])
  screen.move(0,50)
  screen.text("root: "..musicutil.note_num_to_name(params:get("root_note"), true))
  screen.update()
end

function grid_redraw()
  g:all(0)
  for y= 1,8 do
    for x= 1,2 do
      if x == 1 then
        if grid_pattern[y].play == 1 and grid_pattern[y].overdub == 1 then
          g:led(x,y,15)
        elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 0 then
          g:led(x,y,8)
        elseif grid_pattern[y].rec == 1 then
          g:led(x,y,15)
        else
          g:led(x,y,4)
        end
      elseif x == 2 then
        if grid_pattern[y].count > 0 then
          g:led(x,y,15)
        else
          g:led(x,y,4)
        end
      end
    end
  end

  for x = 3,16 do
    for y = 8,1,-1 do
      -- scale notes
      if note[y][x].in_scale == true then
        g:led(x,y,4)
      end
      -- root notes
      if (note[y][x].value - params:get("root_note")) % 12 == 0 then
        g:led(x,y,8)
      end
    end
  end
  -- lit when pressed
  for i,e in pairs(lit) do
    if e.voice == selected_voice then
      g:led(e.x, e.y,15)
    end
  end
  g:refresh()
end


function randomize_params(voice,sound_type)
  
  params:set(voice.."osc_wave_shape", math.random(#options.OSC_WAVE_SHAPE))
  params:set(voice.."pulse_width_mod", math.random())
  params:set(voice.."pulse_width_mod_src", math.random(#options.PW_MOD_SRC))
  
  params:set(voice.."lp_filter_type", math.random(#options.LP_FILTER_TYPE))
  params:set(voice.."lp_filter_env", math.random(#options.LP_FILTER_ENV))
  params:set(voice.."lp_filter_tracking", util.linlin(0, 1, specs.LP_FILTER_TRACKING.minval, specs.LP_FILTER_TRACKING.maxval, math.random()))
  
  params:set(voice.."lfo_freq", util.linlin(0, 1, specs.LFO_FREQ.minval, specs.LFO_FREQ.maxval, math.random()))
  params:set(voice.."lfo_wave_shape", math.random(#options.LFO_WAVE_SHAPE))
  params:set(voice.."lfo_fade", util.linlin(0, 1, specs.LFO_FADE.minval, specs.LFO_FADE.maxval, math.random()))
  
  params:set(voice.."env_1_decay", util.linlin(0, 1, specs.ENV_DECAY.minval, specs.ENV_DECAY.maxval, math.random()))
  params:set(voice.."env_1_sustain", math.random())
  params:set(voice.."env_1_release", util.linlin(0, 1, specs.ENV_RELEASE.minval, specs.ENV_RELEASE.maxval, math.random()))
  
  params:set(voice.."ring_mod_freq", util.linlin(0, 1, specs.RING_MOD_FREQ.minval, specs.RING_MOD_FREQ.maxval, math.random()))
  params:set(voice.."chorus_mix", math.random())
  
  
  if sound_type == "lead" then
    
    params:set(voice.."freq_mod_lfo", util.linexp(0, 1, 0.0000001, 0.1, math.pow(math.random(), 2)))
    if math.random() > 0.95 then
      params:set(voice.."freq_mod_env", util.linlin(0, 1, -0.06, 0.06, math.random()))
    else
      params:set(voice.."freq_mod_env", 0)
    end
    
    params:set(voice.."glide", util.linexp(0, 1, 0.0000001, 1, math.pow(math.random(), 2)))
    
    if math.random() > 0.8 then
      params:set(voice.."main_osc_level", 1)
      params:set(voice.."sub_osc_level", 0)
    else
      params:set(voice.."main_osc_level", math.random())
      params:set(voice.."sub_osc_level", math.random())
    end
    if math.random() > 0.9 then
      params:set(voice.."sub_osc_detune", util.linlin(0, 1, specs.SUB_OSC_DETUNE.minval, specs.SUB_OSC_DETUNE.maxval, math.random()))
    else
      local detune = {0, 0, 0, 4, 5, -4, -5}
      params:set(voice.."sub_osc_detune", detune[math.random(1, #detune)] + math.random() * 0.01)
    end
    params:set(voice.."noise_level", util.linexp(0, 1, 0.0000001, 1, math.random()))
    
    if math.abs(params:get(voice.."sub_osc_detune")) > 0.7 and params:get(voice.."sub_osc_level") > params:get(voice.."main_osc_level")  and params:get(voice.."sub_osc_level") > params:get(voice.."noise_level") then
      params:set(voice.."main_osc_level", params:get(voice.."sub_osc_level") + 0.2)
    end
    
    params:set(voice.."lp_filter_cutoff", util.linexp(0, 1, 100, specs.LP_FILTER_CUTOFF.maxval, math.pow(math.random(), 2)))
    params:set(voice.."lp_filter_resonance", math.random() * 0.9)
    params:set(voice.."lp_filter_mod_env", util.linlin(0, 1, math.random(-1, 0), 1, math.random()))
    params:set(voice.."lp_filter_mod_lfo", math.random() * 0.2)
    
    params:set(voice.."env_2_attack", util.linexp(0, 1, specs.ENV_ATTACK.minval, 0.5, math.random()))
    params:set(voice.."env_2_decay", util.linlin(0, 1, specs.ENV_DECAY.minval, specs.ENV_DECAY.maxval, math.random()))
    params:set(voice.."env_2_sustain", math.random())
    params:set(voice.."env_2_release", util.linlin(0, 1, specs.ENV_RELEASE.minval, 3, math.random()))
    
    if(math.random() > 0.8) then
      params:set(voice.."env_1_attack", params:get(voice.."env_2_attack"))
    else
      params:set(voice.."env_1_attack", util.linlin(0, 1, specs.ENV_ATTACK.minval, 1, math.random()))
    end
    
    if params:get(voice.."env_2_decay") < 0.2 and params:get(voice.."env_2_sustain") < 0.15 then
      params:set(voice.."env_2_decay", util.linlin(0, 1, 0.2, specs.ENV_DECAY.maxval, math.random()))
    end
    
    local amp_max = 0.9
    if math.random() > 0.8 then amp_max = 11 end
    params:set(voice.."amp", util.linlin(0, 1, 0.75, amp_max, math.random()))
    params:set(voice.."amp_mod", util.linlin(0, 1, 0, 0.5, math.random()))
    
    params:set(voice.."ring_mod_fade", util.linlin(0, 1, specs.RING_MOD_FADE.minval * 0.8, specs.RING_MOD_FADE.maxval * 0.3, math.random()))
    if(math.random() > 0.8) then
      params:set(voice.."ring_mod_mix", math.pow(math.random(), 2))
    else
      params:set(voice.."ring_mod_mix", 0)
    end
    
    
  elseif sound_type == "pad" then
    
    params:set(voice.."freq_mod_lfo", util.linexp(0, 1, 0.0000001, 0.2, math.pow(math.random(), 4)))
    if math.random() > 0.8 then
      params:set(voice.."freq_mod_env", util.linlin(0, 1, -0.1, 0.2, math.pow(math.random(), 4)))
    else
      params:set(voice.."freq_mod_env", 0)
    end
    
    params:set(voice.."glide", util.linexp(0, 1, 0.0000001, specs.GLIDE.maxval, math.pow(math.random(), 2)))
    
    params:set(voice.."main_osc_level", math.random())
    params:set(voice.."sub_osc_level", math.random())
    if math.random() > 0.7 then
      params:set(voice.."sub_osc_detune", util.linlin(0, 1, specs.SUB_OSC_DETUNE.minval, specs.SUB_OSC_DETUNE.maxval, math.random()))
    else
      params:set(voice.."sub_osc_detune", math.random(specs.SUB_OSC_DETUNE.minval, specs.SUB_OSC_DETUNE.maxval) + math.random() * 0.01)
    end
    params:set(voice.."noise_level", util.linexp(0, 1, 0.0000001, 1, math.random()))
    
    if math.abs(params:get(voice.."sub_osc_detune")) > 0.7 and params:get(voice.."sub_osc_level") > params:get(voice.."main_osc_level")  and params:get(voice.."sub_osc_level") > params:get(voice.."noise_level") then
      params:set(voice.."main_osc_level", params:get(voice.."sub_osc_level") + 0.2)
    end
    
    params:set(voice.."lp_filter_cutoff", util.linexp(0, 1, 100, specs.LP_FILTER_CUTOFF.maxval, math.random()))
    params:set(voice.."lp_filter_resonance", math.random())
    params:set(voice.."lp_filter_mod_env", util.linlin(0, 1, -1, 1, math.random()))
    params:set(voice.."lp_filter_mod_lfo", math.random())
    
    params:set(voice.."env_1_attack", util.linlin(0, 1, specs.ENV_ATTACK.minval, specs.ENV_ATTACK.maxval, math.random()))
    
    params:set(voice.."env_2_attack", util.linlin(0, 1, specs.ENV_ATTACK.minval, specs.ENV_ATTACK.maxval, math.random()))
    params:set(voice.."env_2_decay", util.linlin(0, 1, specs.ENV_DECAY.minval, specs.ENV_DECAY.maxval, math.random()))
    params:set(voice.."env_2_sustain", 0.1 + math.random() * 0.9)
    params:set(voice.."env_2_release", util.linlin(0, 1, 0.5, specs.ENV_RELEASE.maxval, math.random()))
    
    params:set(voice.."amp", util.linlin(0, 1, 0.5, 0.8, math.random()))
    params:set(voice.."amp_mod", math.random())
    
    params:set(voice.."ring_mod_fade", util.linlin(0, 1, specs.RING_MOD_FADE.minval, specs.RING_MOD_FADE.maxval, math.random()))
    if(math.random() > 0.8) then
      params:set(voice.."ring_mod_mix", math.random())
    else
      params:set(voice.."ring_mod_mix", 0)
    end
    
    
  else -- Perc
    
    params:set(voice.."freq_mod_lfo", util.linexp(0, 1, 0.0000001, 1, math.pow(math.random(), 2)))
    params:set(voice.."freq_mod_env", util.linlin(0, 1, specs.FREQ_MOD_ENV.minval, specs.FREQ_MOD_ENV.maxval, math.pow(math.random(), 4)))
    
    params:set(voice.."glide", util.linexp(0, 1, 0.0000001, specs.GLIDE.maxval, math.pow(math.random(), 2)))
    
    params:set(voice.."main_osc_level", math.random())
    params:set(voice.."sub_osc_level", math.random())
    params:set(voice.."sub_osc_detune", util.linlin(0, 1, specs.SUB_OSC_DETUNE.minval, specs.SUB_OSC_DETUNE.maxval, math.random()))
    params:set(voice.."noise_level", util.linlin(0, 1, 0.1, 1, math.random()))
    
    params:set(voice.."lp_filter_cutoff", util.linexp(0, 1, 100, 6000, math.random()))
    if math.random() > 0.6 then
      params:set(voice.."lp_filter_resonance", util.linlin(0, 1, 0.5, 1, math.random()))
    else
      params:set(voice.."lp_filter_resonance", math.random())
    end
    params:set(voice.."lp_filter_mod_env", util.linlin(0, 1, -0.3, 1, math.random()))
    params:set(voice.."lp_filter_mod_lfo", math.random())
    
    params:set(voice.."env_1_attack", util.linlin(0, 1, specs.ENV_ATTACK.minval, specs.ENV_ATTACK.maxval, math.random()))
    
    params:set(voice.."env_2_attack", specs.ENV_ATTACK.minval)
    params:set(voice.."env_2_decay", util.linlin(0, 1, 0.008, 1.8, math.pow(math.random(), 4)))
    params:set(voice.."env_2_sustain", 0)
    params:set(voice.."env_2_release", params:get(voice.."env_2_decay"))
    
    if params:get(voice.."env_2_decay") < 0.15 and params:get(voice.."env_1_attack") > 1 then
      params:set(voice.."env_1_attack", params:get(voice.."env_2_decay"))
    end
    
    local amp_max = 1
    if math.random() > 0.7 then amp_max = 11 end
    params:set(voice.."amp", util.linlin(0, 1, 0.75, amp_max, math.random()))
    params:set(voice.."amp_mod", util.linlin(0, 1, 0, 0.2, math.random()))
    
    params:set(voice.."ring_mod_fade", util.linlin(0, 1, specs.RING_MOD_FADE.minval, 2, math.random()))
    if(math.random() > 0.4) then
      params:set(voice.."ring_mod_mix", math.random())
    else
      params:set(voice.."ring_mod_mix", 0)
    end
    
  end
  
  if params:get(voice.."main_osc_level") < 0.6 and params:get(voice.."sub_osc_level") < 0.6 and params:get(voice.."noise_level") < 0.6 then
    params:set(voice.."main_osc_level", util.linlin(0, 1, 0.6, 1, math.random()))
  end
  
  if params:get(voice.."lp_filter_cutoff") > 12000 and math.random() > 0.7 then
    params:set(voice.."hp_filter_cutoff", util.linexp(0, 1, specs.HP_FILTER_CUTOFF.minval, params:get(voice.."lp_filter_cutoff") * 0.05, math.random()))
  else
    params:set(voice.."hp_filter_cutoff", specs.HP_FILTER_CUTOFF.minval)
  end
  
  if params:get(voice.."lp_filter_cutoff") < 600 and params:get(voice.."lp_filter_mod_env") < 0 then
    params:set(voice.."lp_filter_mod_env", math.abs(params:get(voice.."lp_filter_mod_env")))
  end
  
end
